package it.arcade.backend.db;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import it.arcade.backend.support.Fixtures;
import it.arcade.backend.support.PostgresSupport;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

class SchemaV6Test {

    private final JdbcTemplate owner = Fixtures.owner();

    @Test
    void la_colonna_della_riserva_esiste() {
        Integer n = owner.queryForObject("""
                SELECT count(*) FROM information_schema.columns
                 WHERE table_schema = 'core' AND table_name = 'stand_edition'
                   AND column_name = 'reserved_by_quote_id'""", Integer.class);
        assertThat(n).isEqualTo(1);
    }

    @Test
    void reserved_by_quote_id_richiede_lo_stato_reserved() {
        int standEdition = Fixtures.newStand(2098, "P1", "10.00", "LINEA");
        // lo stand e' AVAILABLE: indicare un preventivo che lo riserva viola il vincolo
        assertThatThrownBy(() -> owner.update(
                "UPDATE core.stand_edition SET reserved_by_quote_id = 1 WHERE stand_edition_id = ?", standEdition))
                .isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
    }

    @Test
    void la_chiave_idempotente_e_unica_per_utente_operazione_e_chiave() {
        owner.update("INSERT INTO core.idempotency_key (principal, operation, idem_key, request_hash) "
                + "VALUES ('u', 'op', 'chiave-unica-1', 'h')");
        assertThatThrownBy(() -> owner.update("INSERT INTO core.idempotency_key "
                + "(principal, operation, idem_key, request_hash) VALUES ('u', 'op', 'chiave-unica-1', 'h2')"))
                .hasMessageContaining("duplicate key");
    }

    @Test
    void la_migrazione_si_puo_rieseguire_senza_errori() throws Exception {
        String sql = java.nio.file.Files.readString(java.nio.file.Path.of(
                "../database/migrations/V6__commercial_idempotency_and_reservation.sql"));
        owner.execute(sql);
        owner.execute(sql);
        assertThat(PostgresSupport.DB.isRunning()).isTrue();
    }
}
