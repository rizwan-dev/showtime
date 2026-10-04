package dev.rizwan.showtime

import dev.rizwan.showtime.booking.BookingFailure
import dev.rizwan.showtime.booking.BookingRepository
import dev.rizwan.showtime.model.SeatStatus
import java.time.Duration
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.assertThrows

class HoldTest : DatabaseTest() {

    @Test
    fun `a held seat shows as held, not booked and not free`() {
        val (showId, seats) = firstShow()
        repository.hold(showId, listOf(seats[0]))

        val map = repository.seatMap(showId).rows.flatMap { it.seats }
        assertEquals(SeatStatus.HELD, map.first { it.id == seats[0] }.status)
        assertEquals(SeatStatus.FREE, map.first { it.id == seats[1] }.status)
    }

    @Test
    fun `twenty threads racing for one seat produce exactly one hold`() {
        val (showId, seats) = firstShow()
        val seat = seats[0]

        val threads = 20
        val ready = CountDownLatch(threads)
        val go = CountDownLatch(1)
        val won = AtomicInteger()
        val lost = AtomicInteger()
        val pool = Executors.newFixedThreadPool(threads)

        repeat(threads) {
            pool.submit {
                ready.countDown()
                go.await()
                try {
                    repository.hold(showId, listOf(seat))
                    won.incrementAndGet()
                } catch (_: BookingFailure.SeatsUnavailable) {
                    lost.incrementAndGet()
                } catch (_: Exception) {
                    // A unique-violation surfacing as a raw SQL error is still
                    // a loss, not a win. What must never happen is two wins.
                    lost.incrementAndGet()
                }
            }
        }

        ready.await(10, TimeUnit.SECONDS)
        go.countDown()
        pool.shutdown()
        assertTrue(pool.awaitTermination(30, TimeUnit.SECONDS), "threads did not finish")

        assertEquals(1, won.get(), "exactly one thread may hold the seat")
        assertEquals(threads - 1, lost.get())
    }

    @Test
    fun `holding is all or nothing`() {
        val (showId, seats) = firstShow()
        repository.hold(showId, listOf(seats[1]))

        // Asking for two seats where one is already held must leave the other
        // free - a partial hold is useless to the customer and blocks everyone.
        assertThrows<BookingFailure.SeatsUnavailable> {
            repository.hold(showId, listOf(seats[0], seats[1]))
        }

        val map = repository.seatMap(showId).rows.flatMap { it.seats }
        assertEquals(
            SeatStatus.FREE,
            map.first { it.id == seats[0] }.status,
            "the seat that was won must be rolled back, not left held",
        )
    }

    @Test
    fun `an expired hold frees its seat with no sweeper running`() {
        val (showId, seats) = firstShow()

        // A hold that is already dead on arrival. Nothing deletes it; the seat
        // has to come back on its own.
        val instant = BookingRepository(dataSource, holdDuration = Duration.ofMillis(-1))
        instant.hold(showId, listOf(seats[0]))

        val map = repository.seatMap(showId).rows.flatMap { it.seats }
        assertEquals(SeatStatus.FREE, map.first { it.id == seats[0] }.status)

        // And someone else can take it over.
        repository.hold(showId, listOf(seats[0]))
    }

    @Test
    fun `releasing a hold early returns the seat immediately`() {
        val (showId, seats) = firstShow()
        val hold = repository.hold(showId, listOf(seats[0]))
        repository.release(hold.token)

        val map = repository.seatMap(showId).rows.flatMap { it.seats }
        assertEquals(SeatStatus.FREE, map.first { it.id == seats[0] }.status)
    }

    @Test
    fun `availability counts holds, so a seat is not sold twice over`() {
        val (showId, seats) = firstShow()
        val before = repository.shows(null).first { it.id == showId }.seatsAvailable

        repository.hold(showId, listOf(seats[0], seats[1]))

        val after = repository.shows(null).first { it.id == showId }.seatsAvailable
        assertEquals(before - 2, after)
    }
}
