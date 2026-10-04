package dev.rizwan.showtime

import java.time.Duration
import java.time.Instant
import javax.sql.DataSource

/**
 * A catalogue to look at, inserted only when the database is empty.
 *
 * Seeding on every start would fight the booking data; seeding never would
 * leave the app showing an empty screen on first run, which reads as broken.
 */
object Seed {

    fun run(dataSource: DataSource) {
        dataSource.connection.use { c ->
            val empty = c.prepareStatement("SELECT count(*) FROM movies").executeQuery().use {
                it.next() && it.getLong(1) == 0L
            }
            if (!empty) return

            c.autoCommit = false

            val movies = listOf(
                Triple("Laapataa Ladies", "Hindi", 122) to
                    "Two brides are swapped on a crowded train, and neither family notices until morning.",
                Triple("Kantara", "Kannada", 148) to
                    "A dancer, a landlord and a forest officer collide over land that was promised by a king.",
                Triple("Dune: Part Two", "English", 166) to
                    "Paul Atreides unites with the Fremen to wage war against the conspirators who destroyed his family.",
                Triple("Sita Ramam", "Telugu", 163) to
                    "A soldier with no family receives a letter from a stranger, and spends a lifetime answering it.",
                Triple("The Kerala Story", "Malayalam", 138) to
                    "A nursing student's quiet life in Kozhikode turns on a single decision.",
            )

            val movieIds = movies.map { (triple, synopsis) ->
                val (title, language, minutes) = triple
                c.prepareStatement(
                    "INSERT INTO movies (title, language, duration_min, certificate, synopsis) " +
                        "VALUES (?, ?, ?, ?, ?) RETURNING id",
                ).use { ps ->
                    ps.setString(1, title)
                    ps.setString(2, language)
                    ps.setInt(3, minutes)
                    ps.setString(4, if (minutes > 150) "UA" else "U")
                    ps.setString(5, synopsis)
                    ps.executeQuery().use { rs -> rs.next(); rs.getLong(1) }
                }
            }

            // Rows A-H, 12 seats each: big enough that the map needs scrolling
            // on a phone, which is the layout problem worth solving.
            val screens = listOf("Audi 1 - Dolby Atmos" to 96, "Audi 2 - IMAX" to 96)
            val screenIds = screens.map { (name, total) ->
                c.prepareStatement(
                    "INSERT INTO screens (name, total_seats) VALUES (?, ?) RETURNING id",
                ).use { ps ->
                    ps.setString(1, name)
                    ps.setInt(2, total)
                    ps.executeQuery().use { rs -> rs.next(); rs.getLong(1) }
                }
            }

            screenIds.forEach { screenId ->
                ('A'..'H').forEach { row ->
                    (1..12).forEach { num ->
                        c.prepareStatement(
                            "INSERT INTO seats (screen_id, row_label, seat_num) VALUES (?, ?, ?)",
                        ).use { ps ->
                            ps.setLong(1, screenId)
                            ps.setString(2, row.toString())
                            ps.setInt(3, num)
                            ps.executeUpdate()
                        }
                    }
                }
            }

            val now = Instant.now()
            movieIds.forEachIndexed { index, movieId ->
                listOf(3L, 7L, 11L).forEachIndexed { slot, hours ->
                    c.prepareStatement(
                        "INSERT INTO shows (movie_id, screen_id, starts_at, price_paise) " +
                            "VALUES (?, ?, ?, ?)",
                    ).use { ps ->
                        ps.setLong(1, movieId)
                        ps.setLong(2, screenIds[(index + slot) % screenIds.size])
                        ps.setTimestamp(
                            3,
                            java.sql.Timestamp.from(now.plus(Duration.ofHours(hours + index))),
                        )
                        // Evening shows cost more, as they do.
                        ps.setInt(4, if (hours > 7) 32000 else 21000)
                        ps.executeUpdate()
                    }
                }
            }

            c.commit()
        }
    }
}
