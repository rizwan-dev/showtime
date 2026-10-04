package dev.rizwan.showtime

import dev.rizwan.showtime.booking.BookingFailure
import dev.rizwan.showtime.booking.BookingRepository
import dev.rizwan.showtime.model.SeatStatus
import java.time.Duration
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.assertThrows

class ConfirmTest : DatabaseTest() {

    @Test
    fun `confirming a live hold produces a booking with the right total`() {
        val (showId, seats) = firstShow()
        val price = repository.seatMap(showId).pricePaise
        val hold = repository.hold(showId, listOf(seats[0], seats[1]))

        val booking = repository.confirm(hold.token, "Rizwan")

        assertEquals(2 * price, booking.amountPaise)
        assertEquals(2, booking.seats.size)
        assertTrue(booking.reference.startsWith("PC-"))
        assertEquals("Rizwan", booking.customerName)
    }

    @Test
    fun `a confirmed seat reads as booked, not merely held`() {
        val (showId, seats) = firstShow()
        val hold = repository.hold(showId, listOf(seats[0]))
        repository.confirm(hold.token, "Rizwan")

        val map = repository.seatMap(showId).rows.flatMap { it.seats }
        assertEquals(SeatStatus.BOOKED, map.first { it.id == seats[0] }.status)
    }

    @Test
    fun `confirming an expired hold fails, and no booking or charge is created`() {
        val (showId, seats) = firstShow()

        // The race this whole design exists for: the hold lapses, then the
        // confirmation arrives. Taking money here would be the real bug.
        val instant = BookingRepository(dataSource, holdDuration = Duration.ofMillis(-1))
        val dead = instant.hold(showId, listOf(seats[0]))

        assertThrows<BookingFailure.HoldExpired> { repository.confirm(dead.token, "Rizwan") }

        val map = repository.seatMap(showId).rows.flatMap { it.seats }
        assertEquals(
            SeatStatus.FREE,
            map.first { it.id == seats[0] }.status,
            "a failed confirmation must not leave the seat looking taken",
        )
    }

    @Test
    fun `a seat lost to an expired hold cannot be confirmed by the original holder`() {
        val (showId, seats) = firstShow()

        val instant = BookingRepository(dataSource, holdDuration = Duration.ofMillis(-1))
        val dead = instant.hold(showId, listOf(seats[0]))

        // Someone else takes the seat over while the first customer is paying.
        val live = repository.hold(showId, listOf(seats[0]))
        repository.confirm(live.token, "Second customer")

        // The first customer must not get a booking for a seat that now
        // belongs to somebody else.
        assertThrows<BookingFailure.HoldExpired> { repository.confirm(dead.token, "First customer") }
    }

    @Test
    fun `releasing a hold makes it unconfirmable`() {
        val (showId, seats) = firstShow()
        val hold = repository.hold(showId, listOf(seats[0]))
        repository.release(hold.token)

        assertThrows<BookingFailure.HoldExpired> { repository.confirm(hold.token, "Rizwan") }
    }

    @Test
    fun `an unknown token is not found rather than expired`() {
        assertThrows<BookingFailure.HoldNotFound> {
            repository.confirm("11111111-2222-3333-4444-555555555555", "Rizwan")
        }
    }

    @Test
    fun `a booking can be read back by its reference`() {
        val (showId, seats) = firstShow()
        val hold = repository.hold(showId, listOf(seats[0]))
        val created = repository.confirm(hold.token, "Rizwan")

        val fetched = repository.booking(created.reference)
        assertEquals(created, fetched)
    }
}
