package it.arcade.backend.config;

import static org.assertj.core.api.Assertions.assertThat;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.testcontainers.postgresql.PostgreSQLContainer;

class BaselineExistingSchemaStrategyTest {

    private static Flyway flyway(PostgreSQLContainer pg) {
        return Flyway.configure()
                .dataSource(pg.getJdbcUrl(), pg.getUsername(), pg.getPassword())
                .locations("filesystem:../database/migrations")
                .baselineVersion("5")
                .load();
    }

    @Test
    void suDatabaseVuotoApplicaTutteLeMigrazioni() {
        try (PostgreSQLContainer pg = new PostgreSQLContainer("postgres:16-alpine")) {
            pg.start();
            Flyway flyway = flyway(pg);

            new BaselineExistingSchemaStrategy().migrate(flyway);

            assertThat(flyway.info().current().getVersion().getVersion()).isEqualTo("5");
            assertThat(flyway.info().applied()).hasSize(5);
        }
    }

    @Test
    void suSchemaGiaCreatoSenzaStoricoImpostaSoloIlRiferimentoAllaVersione5() {
        try (PostgreSQLContainer pg = new PostgreSQLContainer("postgres:16-alpine")) {
            pg.start();
            flyway(pg).migrate(); // simula il database creato da Docker
            JdbcTemplate jdbc = new JdbcTemplate(
                    new DriverManagerDataSource(pg.getJdbcUrl(), pg.getUsername(), pg.getPassword()));
            jdbc.execute("DROP TABLE flyway_schema_history"); // Docker non crea lo storico di Flyway

            Flyway flyway = flyway(pg);
            new BaselineExistingSchemaStrategy().migrate(flyway);

            assertThat(flyway.info().current().getVersion().getVersion()).isEqualTo("5");
            assertThat(flyway.info().applied()).hasSize(1); // solo il riferimento, nessuna migrazione rieseguita
            assertThat(jdbc.queryForObject("SELECT count(*) FROM core.edition", Integer.class)).isEqualTo(3);
        }
    }
}
