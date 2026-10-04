package dev.rizwan.showtime

import dev.rizwan.showtime.booking.BookingFailure
import dev.rizwan.showtime.booking.BookingRepository
import dev.rizwan.showtime.model.*
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Application.configureRouting(repository: BookingRepository) = routing {

    get("/health") { call.respond(mapOf("status" to "UP")) }

    get("/api/movies") { call.respond(repository.movies()) }

    get("/api/shows") {
        val movieId = call.request.queryParameters["movieId"]?.toLongOrNull()
        call.respond(repository.shows(movieId))
    }

    get("/api/shows/{id}/seats") {
        val id = call.parameters["id"]?.toLongOrNull()
            ?: throw BookingFailure.ShowNotFound(-1)
        call.respond(repository.seatMap(id))
    }

    post("/api/shows/{id}/holds") {
        val id = call.parameters["id"]?.toLongOrNull()
            ?: throw BookingFailure.ShowNotFound(-1)
        val request = call.receive<HoldRequest>()
        call.respond(HttpStatusCode.Created, repository.hold(id, request.seatIds))
    }

    delete("/api/holds/{token}") {
        repository.release(call.parameters["token"].orEmpty())
        call.respond(HttpStatusCode.NoContent)
    }

    post("/api/bookings") {
        val request = call.receive<ConfirmRequest>()
        val name = request.customerName.trim().ifEmpty { "Guest" }
        call.respond(HttpStatusCode.Created, repository.confirm(request.token, name))
    }

    get("/api/bookings/{reference}") {
        val booking = repository.booking(call.parameters["reference"].orEmpty())
            ?: throw BookingFailure.HoldNotFound()
        call.respond(booking)
    }
}
