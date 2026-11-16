package it.arcade.backend.commercial;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/** Numeri progressivi per anno (es. Q2026-0001). Chiamare dentro una transazione in scrittura. */
@Component
public class NumberGenerator {

    /** `table` e `column` sono costanti del codice, mai testo del client. */
    public String next(JdbcClient jdbc, String prefix, int year, String table, String column) {
        // Blocco consultivo per tabella e anno: due richieste parallele non prendono lo stesso numero.
        jdbc.sql("SELECT 1 FROM (SELECT pg_advisory_xact_lock(hashtext(:k))) t")
                .param("k", table + ":" + year).query(Integer.class).single();
        int next = jdbc.sql("SELECT COALESCE(MAX(CAST(substring(" + column + " from '[0-9]+$') AS integer)), 0) + 1 "
                        + "FROM " + table + " WHERE " + column + " LIKE :p")
                .param("p", prefix + year + "-%").query(Integer.class).single();
        return String.format("%s%d-%04d", prefix, year, next);
    }
}
