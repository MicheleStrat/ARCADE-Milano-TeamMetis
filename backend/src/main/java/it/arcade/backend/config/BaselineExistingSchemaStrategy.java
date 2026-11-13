package it.arcade.backend.config;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import org.flywaydb.core.Flyway;
import org.springframework.boot.autoconfigure.flyway.FlywayMigrationStrategy;
import org.springframework.stereotype.Component;

/**
 * Il database locale e' creato da Docker eseguendo V1..V5 direttamente, senza lo storico di Flyway.
 * Se lo schema esiste gia' ma lo storico no, si imposta il riferimento alla versione di base
 * (spring.flyway.baseline-version) invece di rieseguire V1. Su un database vuoto si migra normalmente.
 */
@Component
public class BaselineExistingSchemaStrategy implements FlywayMigrationStrategy {

    @Override
    public void migrate(Flyway flyway) {
        if (flyway.info().current() == null && coreSchemaExists(flyway)) {
            flyway.baseline();
        }
        flyway.migrate();
    }

    private static boolean coreSchemaExists(Flyway flyway) {
        try (Connection c = flyway.getConfiguration().getDataSource().getConnection();
             Statement s = c.createStatement();
             ResultSet rs = s.executeQuery("SELECT to_regclass('core.edition') IS NOT NULL")) {
            rs.next();
            return rs.getBoolean(1);
        } catch (SQLException e) {
            throw new IllegalStateException("Impossibile controllare lo schema del database", e);
        }
    }
}
