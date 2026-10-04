package dev.rizwan.showtime

import dev.rizwan.showtime.booking.BookingFailure
import dev.rizwan.showtime.model.ApiError
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.plugins.cors.routing.*
import io.ktor.server.plugins.statuspages.*
import io.ktor.server.response.*
import kotlinx.serialization.json.Json

fun Application.configurePlugins() {
    install(ContentNegotiation) {
        json(Json { prettyPrint = false; ignoreUnknownKeys = true })
    }

    install(CORS) {
        allowMethod(HttpMethod.Post)
        allowMethod(HttpMethod.Delete)
        allowHeader(HttpHeaders.ContentType)
        // A Flutter app sends no Origin, so this matters only for a browser
        // client. anyHost() is acceptable for a read-mostly demo API with no
        // credentials or cookies; it would not be if sessions existed.
        anyHost()
    }

    /**
     * One place where a domain failure becomes a status code.
     *
     * The repository throws HoldExpired without knowing that means 410. Keeping
     * the mapping here is what lets the same repository be driven from a test
     * or a CLI with no HTTP in sight.
     */
    install(StatusPages) {
        exception<BookingFailure.SeatsUnavailable> { call, e ->
            call.respond(
                HttpStatusCode.Conflict,
                ApiError("seats_unavailable", "Someone else is holding: ${e.seatIds}"),
            )
        }
        exception<BookingFailure.HoldExpired> { call, _ ->
            // 410 Gone, not 409: the hold is not in conflict with anything, it
            // simply no longer exists. The seats may well be free again.
            call.respond(HttpStatusCode.Gone, ApiError("hold_expired", "That hold has expired"))
        }
        exception<BookingFailure.HoldNotFound> { call, _ ->
            call.respond(HttpStatusCode.NotFound, ApiError("hold_not_found", "No such hold"))
        }
        exception<BookingFailure.ShowNotFound> { call, e ->
            call.respond(HttpStatusCode.NotFound, ApiError("show_not_found", e.message ?: ""))
        }
        exception<BookingFailure.NothingSelected> { call, _ ->
            call.respond(HttpStatusCode.BadRequest, ApiError("no_seats", "Select at least one seat"))
        }
        exception<Throwable> { call, cause ->
            call.application.log.error("Unhandled", cause)
            call.respond(
                HttpStatusCode.InternalServerError,
                ApiError("internal_error", "Something went wrong"),
            )
        }
    }
}
