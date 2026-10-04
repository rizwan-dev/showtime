package dev.rizwan.showtime

import dev.rizwan.showtime.booking.BookingRepository
import dev.rizwan.showtime.db.Database
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*

fun main() {
    val port = System.getenv("PORT")?.toIntOrNull() ?: 9193
    embeddedServer(Netty, port = port, host = "0.0.0.0") {
        val dataSource = Database.dataSource()
        Database.migrate(dataSource)
        Seed.run(dataSource)
        module(BookingRepository(dataSource))
    }.start(wait = true)
}

fun Application.module(repository: BookingRepository) {
    configurePlugins()
    configureRouting(repository)
}
