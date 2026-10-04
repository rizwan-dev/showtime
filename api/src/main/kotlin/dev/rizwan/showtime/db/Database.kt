package dev.rizwan.showtime.db

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import javax.sql.DataSource
import org.flywaydb.core.Flyway

object Database {

    fun dataSource(
        url: String = System.getenv("DB_URL") ?: "jdbc:postgresql://localhost:55433/showtime",
        user: String = System.getenv("DB_USER") ?: "showtime",
        password: String = System.getenv("DB_PASSWORD") ?: "showtime",
    ): DataSource {
        val config = HikariConfig().apply {
            jdbcUrl = url
            username = user
            this.password = password
            maximumPoolSize = 10
            // The booking path is short and transactional; a long timeout here
            // only delays the moment a caller is told the database is gone.
            connectionTimeout = 5_000
        }
        return HikariDataSource(config)
    }

    fun migrate(dataSource: DataSource) {
        Flyway.configure()
            .dataSource(dataSource)
            .locations("classpath:db/migration")
            .load()
            .migrate()
    }
}
