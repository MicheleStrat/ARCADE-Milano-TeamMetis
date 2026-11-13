package it.arcade.backend.support;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.testcontainers.postgresql.PostgreSQLContainer;

/** Un solo PostgreSQL per tutti i test dell'esecuzione, creato dalle migrazioni V1..V5 piu' i dati di prova. */
public final class PostgresSupport {

    public static final PostgreSQLContainer DB = new PostgreSQLContainer("postgres:16-alpine");

    static {
        DB.start();
    }

    private PostgresSupport() {}

    public static void register(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url", DB::getJdbcUrl);
        r.add("spring.datasource.username", () -> "arcade_backend");
        r.add("spring.datasource.password", () -> "test");
        r.add("spring.datasource.hikari.maximum-pool-size", () -> "1"); // forza il riuso della connessione
        r.add("spring.flyway.url", DB::getJdbcUrl);
        r.add("spring.flyway.user", DB::getUsername);
        r.add("spring.flyway.password", DB::getPassword);
        r.add("spring.flyway.locations", () -> "filesystem:../database/migrations,classpath:db/testdata");
        r.add("arcade.jwt.secret", () -> "chiave-di-prova-chiave-di-prova-0123456789");
    }

    /** Connessione come superutente del container: serve solo ai test per leggere gli id inseriti. */
    public static JdbcTemplate owner() {
        return new JdbcTemplate(new DriverManagerDataSource(DB.getJdbcUrl(), DB.getUsername(), DB.getPassword()));
    }
}
