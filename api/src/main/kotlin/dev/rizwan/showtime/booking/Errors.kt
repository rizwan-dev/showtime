package dev.rizwan.showtime.booking

/** Failures a caller can act on, kept distinct from each other on purpose. */
sealed class BookingFailure(message: String) : RuntimeException(message) {

    /** Someone else holds at least one of these seats, and their hold is live. */
    class SeatsUnavailable(val seatIds: List<Long>) :
        BookingFailure("Seats no longer available: $seatIds")

    /**
     * The hold ran out before confirmation arrived.
     *
     * Deliberately not merged with SeatsUnavailable: the seats may well still
     * be free, and the honest thing to tell someone is "your time ran out,
     * try again", not "those seats are gone".
     */
    class HoldExpired : BookingFailure("That hold has expired")

    class HoldNotFound : BookingFailure("No such hold")

    class ShowNotFound(val showId: Long) : BookingFailure("No show with id $showId")

    class NothingSelected : BookingFailure("No seats selected")
}
