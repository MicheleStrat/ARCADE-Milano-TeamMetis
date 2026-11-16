package it.arcade.backend.config;

import static org.assertj.core.api.Assertions.assertThat;

import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.configuration.FluentConfiguration;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.testcontainers.postgresql.PostgreSQLContainer;

class BaselineExistingSchemaStrategyTest {

    private static FluentConfiguration config(PostgreSQLContainer pg) {
        return Flyway.configure()
                .dataSource(pg.getJdbcUrl(), pg.getUsername(), pg.getPassword())
                .locations("filesystem:../database/migrations")
                .baselineVersion("5");
    }

    private static JdbcTemplate jdbc(PostgreSQLContainer pg) {
        return new JdbcTemplate(new DriverManagerDataSource(pg.getJdbcUrl(), pg.getUsername(), pg.getPassword()));
    }

    @Test
    void suDatabaseVuotoApplicaTutteLeMigrazioni() {
        try (PostgreSQLContainer pg = new PostgreSQLContainer("postgres:16-alpine")) {
            pg.start();
            Flyway flyway = config(pg).load();

            new BaselineExistingSchemaStrategy().migrate(flyway);

            assertThat(flyway.info().current().getVersion().getVersion()).isEqualTo("6");
            assertThat(flyway.info().applied()).hasSize(6);
        }
    }

    @Test
    void suVolumeCreatoQuandoV6NonCeraImpostaIlRiferimentoEApplicaSoloV6() {
        try (PostgreSQLContainer pg = new PostgreSQLContainer("postgres:16-alpine")) {
            pg.start();
            config(pg).target("5").load().migrate(); // simula il database creato da Docker con V1..V5
            JdbcTemplate jdbc = jdbc(pg);
            jdbc.execute("DROP TABLE flyway_schema_history"); // Docker non crea lo storico di Flyway

            Flyway flyway = config(pg).load();
            new BaselineExistingSchemaStrategy().migrate(flyway);

            assertThat(flyway.info().current().getVersion().getVersion()).isEqualTo("6");
            assertThat(flyway.info().applied()).hasSize(2); // riferimento + V6, nessuna altra migrazione rieseguita
            assertThat(jdbc.queryForObject("SELECT count(*) FROM core.edition", Integer.class)).isEqualTo(3);
        }
    }

    @Test
    void suVolumeCreatoConTutteLeMigrazioniLaV6RipetibileNonDaErrori() {
        try (PostgreSQLContainer pg = new PostgreSQLContainer("postgres:16-alpine")) {
            pg.start();
            config(pg).load().migrate(); // simula Docker con V1..V6 gia' applicate
            JdbcTemplate jdbc = jdbc(pg);
            jdbc.execute("DROP TABLE flyway_schema_history");

            Flyway flyway = config(pg).load();
            new BaselineExistingSchemaStrategy().migrate(flyway); // riesegue V6: deve essere innocua

            assertThat(flyway.info().current().getVersion().getVersion()).isEqualTo("6");
            assertThat(flyway.info().applied()).hasSize(2);
        }
    }
}
