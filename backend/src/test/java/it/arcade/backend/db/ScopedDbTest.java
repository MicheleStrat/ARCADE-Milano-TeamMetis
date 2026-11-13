package it.arcade.backend.db;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import it.arcade.backend.support.PostgresSupport;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

@SpringBootTest
class ScopedDbTest {

    @Autowired ScopedDb db;
    @Autowired JdbcClient jdbc;

    @DynamicPropertySource
    static void database(DynamicPropertyRegistry registry) {
        PostgresSupport.register(registry);
    }

    private int exhibitorId(String code) {
        return PostgresSupport.owner().queryForObject(
                "SELECT exhibitor_id FROM core.exhibitor WHERE exhibitor_code = ?", Integer.class, code);
    }

    private static int countExhibitors(JdbcClient jdbc) {
        return jdbc.sql("SELECT count(*) FROM core.exhibitor").query(Integer.class).single();
    }

    @Test
    void lo_staff_vede_tutti_gli_espositori() {
        assertThat(db.read(DbRole.STAFF, null, ScopedDbTest::countExhibitors)).isGreaterThanOrEqualTo(2);
    }

    @Test
    void il_portale_vede_solo_il_proprio_espositore() {
        int alfa = exhibitorId("ESP901");
        assertThat(db.read(DbRole.PORTAL, alfa, ScopedDbTest::countExhibitors)).isEqualTo(1);
    }

    @Test
    void il_portale_senza_exhibitor_id_non_vede_nulla() {
        assertThat(db.read(DbRole.PORTAL, null, ScopedDbTest::countExhibitors)).isZero();
    }

    @Test
    void ruolo_e_exhibitor_id_non_restano_sulla_connessione() {
        int alfa = exhibitorId("ESP901");
        db.read(DbRole.PORTAL, alfa, ScopedDbTest::countExhibitors); // il pool ha una sola connessione

        String utente = jdbc.sql("SELECT current_user").query(String.class).single();
        assertThat(utente).isEqualTo("arcade_backend");
        assertThat(db.read(DbRole.STAFF, null, ScopedDbTest::countExhibitors)).isGreaterThanOrEqualTo(2);
    }

    @Test
    void l_account_del_backend_senza_set_role_non_legge_core() {
        // Spring avvolge l'errore SQL: il testo "permission denied" sta nella causa, non nel messaggio esterno.
        assertThatThrownBy(() -> countExhibitors(jdbc)).rootCause().hasMessageContaining("permission denied");
    }
}
