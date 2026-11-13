package it.arcade.backend.db;

import java.util.function.Function;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Unico punto che cambia il ruolo del database. Ogni lettura gira in una transazione in sola lettura:
 * SET LOCAL ROLE e set_config(..., true) valgono solo fino alla fine della transazione, quindi
 * non restano sulla connessione del pool.
 */
@Component
public class ScopedDb {

    private final JdbcClient jdbc;
    private final TransactionTemplate tx;

    public ScopedDb(JdbcClient jdbc, PlatformTransactionManager transactionManager) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(transactionManager);
        this.tx.setReadOnly(true);
    }

    public <T> T read(DbRole role, Integer exhibitorId, Function<JdbcClient, T> work) {
        return tx.execute(status -> {
            jdbc.sql("SET LOCAL ROLE " + role.sqlName()).update();
            if (role == DbRole.PORTAL && exhibitorId != null) {
                jdbc.sql("SELECT set_config('app.exhibitor_id', :id, true)")
                        .param("id", String.valueOf(exhibitorId))
                        .query(String.class)
                        .single();
            }
            return work.apply(jdbc);
        });
    }
}
