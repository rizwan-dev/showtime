package dev.rizwan.showtime

import dev.rizwan.showtime.booking.BookingRepository
import dev.rizwan.showtime.db.Database
import java.time.Duration
import javax.sql.DataSource
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.testcontainers.containers.PostgreSQLContainer

/**
 * Tests run against a real PostgreSQL, not an in-memory stand-in.
 *
 * Everything interesting here is a database guarantee - a unique index, an
 * ON CONFLICT takeover, now() evaluated server-side. A fake would be testing
 * the fake.
 */
abstract class DatabaseTest {

    protected lateinit var dataSource: DataSource
    protected lateinit var repository: BookingRepository

    @BeforeEach
    fun prepare() {
        dataSource = Database.dataSource(
            url = container.jdbcUrl,
            user = container.username,
            password = container.password,
        )
        wipe()
        Database.migrate(dataSource)
        Seed.run(dataSource)
        repository = BookingRepository(dataSource, holdDuration = Duration.ofMinutes(5))
    }

    /**
     * Pools hold connections open, and Postgres allows about a hundred. A pool
     * per test that is never closed exhausts the server a dozen tests in, and
     * the failure ("too many clients") points at the database rather than at
     * the leak.
     */
    @AfterEach
    fun release() {
        (dataSource as? AutoCloseable)?.close()
    }

    private fun wipe() {
        dataSource.connection.use { c ->
            c.createStatement().execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
        }
    }

    /** The first show, and the ids of its seats in row order. */
    protected fun firstShow(): Pair<Long, List<Long>> {
        val show = repository.shows(null).first()
        val seats = repository.seatMap(show.id).rows.flatMap { it.seats }.map { it.id }
        return show.id to seats
    }

    companion object {
        /**
         * One container for the whole run, deliberately never stopped here.
         *
         * An @AfterAll that stops it runs when the *first* test class finishes
         * and leaves every later class without a database. Testcontainers'
         * reaper removes it when the JVM exits, which is the right lifetime.
         */
        @JvmStatic
        protected val container: PostgreSQLContainer<*> =
            PostgreSQLContainer("postgres:16-alpine").apply { start() }
    }
}
