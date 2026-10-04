package dev.rizwan.showtime.booking

import dev.rizwan.showtime.model.*
import java.sql.Connection
import java.sql.Timestamp
import java.time.Duration
import java.time.Instant
import java.util.UUID
import javax.sql.DataSource

/**
 * Every operation that must be correct under concurrency is one SQL statement.
 *
 * The pattern throughout: do not read, decide in Kotlin, then write. Between
 * the read and the write another request can take the seat, and no amount of
 * application-level checking closes that window. Each statement below either
 * affects rows or it does not, and that outcome *is* the decision.
 */
class BookingRepository(
    private val dataSource: DataSource,
    private val holdDuration: Duration = Duration.ofMinutes(5),
) {

    private fun <T> tx(block: (Connection) -> T): T =
        dataSource.connection.use { connection ->
            connection.autoCommit = false
            try {
                val result = block(connection)
                connection.commit()
                result
            } catch (e: Throwable) {
                connection.rollback()
                throw e
            }
        }

    fun movies(): List<Movie> = tx { c ->
        c.prepareStatement(
            """
            SELECT id, title, language, duration_min, certificate, synopsis
            FROM movies ORDER BY title
            """,
        ).executeQuery().use { rs ->
            buildList {
                while (rs.next()) {
                    add(
                        Movie(
                            id = rs.getLong("id"),
                            title = rs.getString("title"),
                            language = rs.getString("language"),
                            durationMin = rs.getInt("duration_min"),
                            certificate = rs.getString("certificate"),
                            synopsis = rs.getString("synopsis"),
                        ),
                    )
                }
            }
        }
    }

    /**
     * Shows with a live availability count.
     *
     * A seat counts as available when it is neither booked nor under a hold
     * that is still running. Expiry is evaluated by the database at query time,
     * so a lapsed hold frees its seat the instant it lapses - nothing has to
     * sweep it first.
     */
    fun shows(movieId: Long?): List<Show> = tx { c ->
        val sql = """
            SELECT sh.id, sh.movie_id, m.title, sc.name AS screen_name,
                   sh.starts_at, sh.price_paise,
                   (SELECT count(*) FROM seats s WHERE s.screen_id = sh.screen_id)
                     - (SELECT count(*) FROM booking_seats bs WHERE bs.show_id = sh.id)
                     - (SELECT count(*) FROM seat_holds h
                        WHERE h.show_id = sh.id
                          AND h.released_at IS NULL
                          AND h.expires_at > now()) AS available
            FROM shows sh
            JOIN movies m ON m.id = sh.movie_id
            JOIN screens sc ON sc.id = sh.screen_id
            WHERE (? IS NULL OR sh.movie_id = ?)
            ORDER BY sh.starts_at
        """
        c.prepareStatement(sql).use { ps ->
            if (movieId == null) {
                ps.setNull(1, java.sql.Types.BIGINT)
                ps.setNull(2, java.sql.Types.BIGINT)
            } else {
                ps.setLong(1, movieId)
                ps.setLong(2, movieId)
            }
            ps.executeQuery().use { rs ->
                buildList {
                    while (rs.next()) {
                        add(
                            Show(
                                id = rs.getLong("id"),
                                movieId = rs.getLong("movie_id"),
                                movieTitle = rs.getString("title"),
                                screenName = rs.getString("screen_name"),
                                startsAt = rs.getTimestamp("starts_at").toInstant().toString(),
                                pricePaise = rs.getInt("price_paise"),
                                seatsAvailable = rs.getInt("available"),
                            ),
                        )
                    }
                }
            }
        }
    }

    fun seatMap(showId: Long): SeatMap = tx { c ->
        val header = c.prepareStatement(
            """
            SELECT m.title, sc.name AS screen_name, sh.starts_at, sh.price_paise
            FROM shows sh
            JOIN movies m ON m.id = sh.movie_id
            JOIN screens sc ON sc.id = sh.screen_id
            WHERE sh.id = ?
            """,
        ).use { ps ->
            ps.setLong(1, showId)
            ps.executeQuery().use { rs ->
                if (!rs.next()) throw BookingFailure.ShowNotFound(showId)
                listOf(
                    rs.getString("title"),
                    rs.getString("screen_name"),
                    rs.getTimestamp("starts_at").toInstant().toString(),
                    rs.getInt("price_paise").toString(),
                )
            }
        }

        // One query decides all three states, so the map cannot be internally
        // inconsistent - a seat cannot come back both booked and free because
        // two queries ran a moment apart.
        val seats = c.prepareStatement(
            """
            SELECT s.id, s.row_label, s.seat_num,
                   EXISTS (SELECT 1 FROM booking_seats bs
                           WHERE bs.show_id = ? AND bs.seat_id = s.id) AS booked,
                   EXISTS (SELECT 1 FROM seat_holds h
                           WHERE h.show_id = ? AND h.seat_id = s.id
                             AND h.released_at IS NULL AND h.expires_at > now()) AS held
            FROM seats s
            WHERE s.screen_id = (SELECT screen_id FROM shows WHERE id = ?)
            ORDER BY s.row_label, s.seat_num
            """,
        ).use { ps ->
            ps.setLong(1, showId)
            ps.setLong(2, showId)
            ps.setLong(3, showId)
            ps.executeQuery().use { rs ->
                buildList {
                    while (rs.next()) {
                        add(
                            Seat(
                                id = rs.getLong("id"),
                                row = rs.getString("row_label"),
                                number = rs.getInt("seat_num"),
                                status = when {
                                    rs.getBoolean("booked") -> SeatStatus.BOOKED
                                    rs.getBoolean("held") -> SeatStatus.HELD
                                    else -> SeatStatus.FREE
                                },
                            ),
                        )
                    }
                }
            }
        }

        SeatMap(
            showId = showId,
            movieTitle = header[0],
            screenName = header[1],
            startsAt = header[2],
            pricePaise = header[3].toInt(),
            rows = seats.groupBy { it.row }.map { (label, s) -> SeatRow(label, s) },
        )
    }

    /**
     * Take a hold on seats, or fail because somebody else already has one.
     *
     * The insert is the decision. `ON CONFLICT ... DO UPDATE ... WHERE the
     * existing hold has expired` means a lapsed hold is taken over atomically,
     * while a live one makes the statement affect no rows. There is no window
     * between checking and claiming, because there is no check - only a write
     * that either lands or does not.
     *
     * All seats are claimed in one statement and the whole transaction is
     * rolled back unless every seat was won. Partially holding three of four
     * seats is worse than failing: the customer cannot use them and nobody
     * else can either until they expire.
     */
    fun hold(showId: Long, seatIds: List<Long>): Hold = tx { c ->
        if (seatIds.isEmpty()) throw BookingFailure.NothingSelected()

        val price = c.prepareStatement("SELECT price_paise FROM shows WHERE id = ?").use { ps ->
            ps.setLong(1, showId)
            ps.executeQuery().use { rs ->
                if (!rs.next()) throw BookingFailure.ShowNotFound(showId)
                rs.getInt(1)
            }
        }

        // A seat already in booking_seats can never be held again: the booking
        // is permanent, so it is checked separately and plainly.
        val alreadyBooked = c.prepareStatement(
            "SELECT seat_id FROM booking_seats WHERE show_id = ? AND seat_id = ANY (?)",
        ).use { ps ->
            ps.setLong(1, showId)
            ps.setArray(2, c.createArrayOf("bigint", seatIds.toTypedArray()))
            ps.executeQuery().use { rs ->
                buildList { while (rs.next()) add(rs.getLong(1)) }
            }
        }
        if (alreadyBooked.isNotEmpty()) throw BookingFailure.SeatsUnavailable(alreadyBooked)

        val token = UUID.randomUUID()
        val expiresAt = Instant.now().plus(holdDuration)

        // Step one: retire holds on these seats that have already lapsed.
        // The old row is marked released rather than overwritten, so the
        // previous customer's token still resolves and they can be told their
        // hold expired instead of "no such hold" - and the history survives.
        c.prepareStatement(
            """
            UPDATE seat_holds SET released_at = now()
            WHERE show_id = ? AND seat_id = ANY (?)
              AND released_at IS NULL AND expires_at <= now()
            """,
        ).use { ps ->
            ps.setLong(1, showId)
            ps.setArray(2, c.createArrayOf("bigint", seatIds.toTypedArray()))
            ps.executeUpdate()
        }

        // Step two: claim. DO NOTHING rather than DO UPDATE, so a seat whose
        // hold is still live is simply not returned. Two transactions racing to
        // take over the same expired hold both reach here; the unique index
        // lets exactly one insert land, and the loser sees its seat missing
        // from the result rather than an aborted transaction.
        val claimed = c.prepareStatement(
            """
            INSERT INTO seat_holds (token, show_id, seat_id, expires_at)
            SELECT ?, ?, seat_id, ?
            FROM unnest(?::bigint[]) AS seat_id
            ON CONFLICT (show_id, seat_id) WHERE released_at IS NULL DO NOTHING
            RETURNING seat_id
            """,
        ).use { ps ->
            ps.setObject(1, token)
            ps.setLong(2, showId)
            ps.setTimestamp(3, Timestamp.from(expiresAt))
            ps.setArray(4, c.createArrayOf("bigint", seatIds.toTypedArray()))
            ps.executeQuery().use { rs ->
                buildList { while (rs.next()) add(rs.getLong(1)) }
            }
        }

        // All or nothing. The rollback happens in tx(), so the seats this
        // attempt did win are released by the same failure that reports it.
        val lost = seatIds - claimed.toSet()
        if (lost.isNotEmpty()) throw BookingFailure.SeatsUnavailable(lost)

        Hold(
            token = token.toString(),
            showId = showId,
            seatIds = seatIds,
            expiresAt = expiresAt.toString(),
            secondsRemaining = holdDuration.seconds,
            totalPaise = price * seatIds.size,
        )
    }

    /**
     * Turn a live hold into a booking, or fail if it died first.
     *
     * The race this exists for: the hold expires in the same instant
     * confirmation arrives. Reading the hold, deciding it is valid, and then
     * inserting the booking would leave a window in which the seat is taken
     * over by someone else - and the customer is charged for a seat they do
     * not have.
     *
     * So the expiry check is a WHERE clause on the insert itself. If the hold
     * lapsed, the INSERT ... SELECT matches nothing, no booking row is created,
     * and the caller is told the hold expired. The seats are then genuinely
     * free, which is the honest outcome.
     */
    fun confirm(token: String, customerName: String): Booking = tx { c ->
        val uuid = runCatching { UUID.fromString(token) }.getOrNull()
            ?: throw BookingFailure.HoldNotFound()

        val showId = c.prepareStatement(
            "SELECT show_id FROM seat_holds WHERE token = ? LIMIT 1",
        ).use { ps ->
            ps.setObject(1, uuid)
            ps.executeQuery().use { rs ->
                if (!rs.next()) throw BookingFailure.HoldNotFound()
                rs.getLong(1)
            }
        }

        val reference = "PC-" + UUID.randomUUID().toString().take(8).uppercase()

        val bookingId = c.prepareStatement(
            """
            INSERT INTO bookings (reference, show_id, customer_name, amount_paise)
            SELECT ?, ?, ?,
                   count(*) * (SELECT price_paise FROM shows WHERE id = h.show_id)
            FROM seat_holds h
            WHERE h.token = ?
              AND h.released_at IS NULL
              AND h.expires_at > now()
            GROUP BY h.show_id
            RETURNING id
            """,
        ).use { ps ->
            ps.setString(1, reference)
            ps.setLong(2, showId)
            ps.setString(3, customerName)
            ps.setObject(4, uuid)
            ps.executeQuery().use { rs ->
                if (!rs.next()) throw BookingFailure.HoldExpired()
                rs.getLong(1)
            }
        }

        // Claiming the seats re-checks expiry rather than trusting the line
        // above: between the two statements is still a gap, and the UNIQUE on
        // (show_id, seat_id) is the last line of defence either way.
        c.prepareStatement(
            """
            INSERT INTO booking_seats (booking_id, show_id, seat_id)
            SELECT ?, h.show_id, h.seat_id
            FROM seat_holds h
            WHERE h.token = ? AND h.released_at IS NULL AND h.expires_at > now()
            """,
        ).use { ps ->
            ps.setLong(1, bookingId)
            ps.setObject(2, uuid)
            if (ps.executeUpdate() == 0) throw BookingFailure.HoldExpired()
        }

        c.prepareStatement("UPDATE seat_holds SET released_at = now() WHERE token = ?").use { ps ->
            ps.setObject(1, uuid)
            ps.executeUpdate()
        }

        readBooking(c, reference)
    }

    /** Give the seats back before the timer runs out. */
    fun release(token: String) {
        val uuid = runCatching { UUID.fromString(token) }.getOrNull() ?: return
        tx { c ->
            c.prepareStatement(
                "UPDATE seat_holds SET released_at = now() WHERE token = ? AND released_at IS NULL",
            ).use { ps ->
                ps.setObject(1, uuid)
                ps.executeUpdate()
            }
        }
    }

    fun booking(reference: String): Booking? = tx { c ->
        runCatching { readBooking(c, reference) }.getOrNull()
    }

    private fun readBooking(c: Connection, reference: String): Booking {
        return c.prepareStatement(
            """
            SELECT b.reference, b.show_id, m.title, sc.name AS screen_name,
                   sh.starts_at, b.amount_paise, b.customer_name,
                   string_agg(s.row_label || s.seat_num, ',' ORDER BY s.row_label, s.seat_num) AS seats
            FROM bookings b
            JOIN shows sh ON sh.id = b.show_id
            JOIN movies m ON m.id = sh.movie_id
            JOIN screens sc ON sc.id = sh.screen_id
            JOIN booking_seats bs ON bs.booking_id = b.id
            JOIN seats s ON s.id = bs.seat_id
            WHERE b.reference = ?
            GROUP BY b.reference, b.show_id, m.title, sc.name, sh.starts_at,
                     b.amount_paise, b.customer_name
            """,
        ).use { ps ->
            ps.setString(1, reference)
            ps.executeQuery().use { rs ->
                if (!rs.next()) throw BookingFailure.HoldNotFound()
                Booking(
                    reference = rs.getString("reference"),
                    showId = rs.getLong("show_id"),
                    movieTitle = rs.getString("title"),
                    screenName = rs.getString("screen_name"),
                    startsAt = rs.getTimestamp("starts_at").toInstant().toString(),
                    seats = rs.getString("seats").split(","),
                    amountPaise = rs.getInt("amount_paise"),
                    customerName = rs.getString("customer_name"),
                )
            }
        }
    }
}
