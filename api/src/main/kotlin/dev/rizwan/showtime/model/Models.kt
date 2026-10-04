package dev.rizwan.showtime.model

import kotlinx.serialization.Serializable

@Serializable
data class Movie(
    val id: Long,
    val title: String,
    val language: String,
    val durationMin: Int,
    val certificate: String,
    val synopsis: String,
)

@Serializable
data class Show(
    val id: Long,
    val movieId: Long,
    val movieTitle: String,
    val screenName: String,
    val startsAt: String,
    val pricePaise: Int,
    val seatsAvailable: Int,
)

/**
 * A seat as the app needs to draw it.
 *
 * Three states, not two. "Held" is not "booked": it is someone else's seat for
 * the next few minutes, and the app should say so rather than showing it as
 * taken forever or free to tap.
 */
@Serializable
data class Seat(
    val id: Long,
    val row: String,
    val number: Int,
    val status: SeatStatus,
)

enum class SeatStatus { FREE, HELD, BOOKED }

@Serializable
data class SeatMap(
    val showId: Long,
    val movieTitle: String,
    val screenName: String,
    val startsAt: String,
    val pricePaise: Int,
    val rows: List<SeatRow>,
)

@Serializable
data class SeatRow(val label: String, val seats: List<Seat>)

@Serializable
data class HoldRequest(val seatIds: List<Long>)

/**
 * The server decides when a hold dies, and says so in absolute time.
 *
 * The client counts down to [expiresAt] rather than from [secondsRemaining]:
 * a device clock can be wrong, but it is the only thing that can tick. Sending
 * both lets the app show a countdown immediately and still correct itself
 * against the server's deadline.
 */
@Serializable
data class Hold(
    val token: String,
    val showId: Long,
    val seatIds: List<Long>,
    val expiresAt: String,
    val secondsRemaining: Long,
    val totalPaise: Int,
)

@Serializable
data class ConfirmRequest(val token: String, val customerName: String)

@Serializable
data class Booking(
    val reference: String,
    val showId: Long,
    val movieTitle: String,
    val screenName: String,
    val startsAt: String,
    val seats: List<String>,
    val amountPaise: Int,
    val customerName: String,
)

@Serializable
data class ApiError(val code: String, val message: String)
