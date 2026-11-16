package it.arcade.backend.commercial;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import it.arcade.backend.security.Role;
import it.arcade.backend.support.CommercialApiTest;
import it.arcade.backend.support.Fixtures;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

class CreateQuoteApiTest extends CommercialApiTest {

    @Test
    void calcola_i_prezzi_e_riserva_lo_stand() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "ANGOLO");

        JsonNode q = createdQuote(YEAR, espositore(), 0.1, List.of(spaceLine(YEAR, stand), extraLine(YEAR, 2)));

        assertThat(q.get("status").asText()).isEqualTo("DRAFT");
        assertThat(q.get("quoteNumber").asText()).startsWith("Q2098-");
        assertThat(q.get("lines")).hasSize(3);
        assertThat(q.get("listAmount").decimalValue()).isEqualByComparingTo("1200.00");
        assertThat(q.get("netAmount").decimalValue()).isEqualByComparingTo("1080.00");
        assertThat(q.get("rowVersion").asInt()).isZero();
        assertThat(Fixtures.owner().queryForMap(
                "SELECT commercial_status, reserved_by_quote_id FROM core.stand_edition WHERE stand_edition_id = ?",
                stand))
                .containsEntry("commercial_status", "RESERVED")
                .containsEntry("reserved_by_quote_id", q.get("quoteId").asInt());
    }

    @Test
    void uno_stand_gia_riservato_risponde_409_e_non_crea_nulla() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        createdQuote(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand)));

        postQuote(key(), quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand))))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("STAND_ALREADY_RESERVED"));
        assertThat(Fixtures.owner().queryForObject(
                "SELECT count(*) FROM core.quote_line WHERE stand_edition_id = ?", Integer.class, stand)).isEqualTo(1);
    }

    @Test
    void uno_stand_venduto_risponde_409() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        Fixtures.owner().update("UPDATE core.stand_edition SET commercial_status = 'SOLD' WHERE stand_edition_id = ?", stand);

        postQuote(key(), quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand))))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("STAND_ALREADY_SOLD"));
    }

    @Test
    void uno_stand_non_vendibile_risponde_422() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        Fixtures.owner().update("UPDATE core.stand_edition SET commercial_status = 'NOT_SELLABLE' WHERE stand_edition_id = ?", stand);

        postQuote(key(), quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand))))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("STAND_NOT_SELLABLE"));
    }

    @Test
    void una_riserva_scaduta_puo_essere_ripresa_da_un_altro_preventivo() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        createdQuote(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand)));
        Fixtures.owner().update("UPDATE core.stand_edition SET reserved_until = now() - interval '1 hour' "
                + "WHERE stand_edition_id = ?", stand);

        JsonNode second = createdQuote(YEAR, exhibitorId("ESP902"), 0, List.of(spaceLine(YEAR, stand)));

        assertThat(Fixtures.owner().queryForObject(
                "SELECT reserved_by_quote_id FROM core.stand_edition WHERE stand_edition_id = ?", Integer.class, stand))
                .isEqualTo(second.get("quoteId").asInt());
    }

    @Test
    void i_dati_non_validi_rispondono_422_con_errors() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P2", "10.00", "LINEA");

        postQuote(key(), quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand)))) // voce SP-P1 su stand P2
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.errors[0].field").value("lines[0].priceItemId"));
        postQuote(key(), quoteBody(YEAR, espositore(), 1.5, List.of(extraLine(YEAR, 1))))
                .andExpect(status().isUnprocessableEntity());
        postQuote(key(), quoteBody(YEAR, espositore(), 0, List.of()))
                .andExpect(status().isUnprocessableEntity());
        postQuote(key(), quoteBody(YEAR, 999999, 0, List.of(extraLine(YEAR, 1))))
                .andExpect(status().isUnprocessableEntity());
        postQuote(key(), quoteBody(2024, espositore(), 0, List.of(extraLine(YEAR, 1)))) // edizione chiusa
                .andExpect(status().isUnprocessableEntity());
    }

    @Test
    void uno_sconto_con_piu_di_quattro_decimali_e_rifiutato_con_422() throws Exception {
        postQuote(key(), quoteBody(YEAR, espositore(), 0.12345, List.of(extraLine(YEAR, 1))))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.errors[0].field").value("discountPct"));
    }

    @Test
    void una_riga_extra_con_uno_stand_non_lo_riserva() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        Map<String, Object> extraConStand = Map.of("priceItemId", Fixtures.priceItem(YEAR, "EX-EL6"),
                "standEditionId", stand, "quantity", 1);

        postQuote(key(), quoteBody(YEAR, espositore(), 0, List.of(extraConStand)))
                .andExpect(status().isUnprocessableEntity());
        assertThat(Fixtures.owner().queryForObject(
                "SELECT commercial_status FROM core.stand_edition WHERE stand_edition_id = ?", String.class, stand))
                .isEqualTo("AVAILABLE");
    }

    @Test
    void uno_stand_riservato_senza_scadenza_non_si_puo_riprendere() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        Fixtures.owner().update("UPDATE core.stand_edition SET commercial_status = 'RESERVED', reserved_until = NULL "
                + "WHERE stand_edition_id = ?", stand);

        postQuote(key(), quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand))))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("STAND_ALREADY_RESERVED"));
    }

    @Test
    void senza_idempotency_key_risponde_400() throws Exception {
        mvc.perform(post("/quotes").header(HttpHeaders.AUTHORIZATION, staff())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(quoteBody(YEAR, espositore(), 0, List.of(extraLine(YEAR, 1))))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void la_ripetizione_con_la_stessa_chiave_restituisce_la_prima_risposta() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        String k = key();
        Map<String, Object> body = quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand)));

        JsonNode first = read(postQuote(k, body).andExpect(status().isCreated()));
        JsonNode second = read(postQuote(k, body).andExpect(status().isCreated())
                .andExpect(header().string("Idempotent-Replayed", "true")));

        assertThat(second).isEqualTo(first);
        assertThat(Fixtures.owner().queryForObject(
                "SELECT count(*) FROM core.quote_line WHERE stand_edition_id = ?", Integer.class, stand)).isEqualTo(1);
    }

    @Test
    void la_stessa_chiave_con_contenuto_diverso_risponde_409_duplicate_request() throws Exception {
        String k = key();
        postQuote(k, quoteBody(YEAR, espositore(), 0, List.of(extraLine(YEAR, 1)))).andExpect(status().isCreated());

        postQuote(k, quoteBody(YEAR, espositore(), 0, List.of(extraLine(YEAR, 2))))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("DUPLICATE_REQUEST"));
    }

    @Test
    void una_richiesta_fallita_non_consuma_la_chiave_e_una_chiave_vecchia_riparte() throws Exception {
        String k = key();
        postQuote(k, quoteBody(YEAR, espositore(), 1.5, List.of(extraLine(YEAR, 1)))) // non valida
                .andExpect(status().isUnprocessableEntity());
        postQuote(k, quoteBody(YEAR, espositore(), 0, List.of(extraLine(YEAR, 1)))).andExpect(status().isCreated());

        Fixtures.owner().update("UPDATE core.idempotency_key SET created_at = now() - interval '25 hours' "
                + "WHERE idem_key = ?", k);
        postQuote(k, quoteBody(YEAR, espositore(), 0, List.of(extraLine(YEAR, 3)))) // contenuto diverso, chiave scaduta
                .andExpect(status().isCreated());
    }

    @Test
    void il_dettaglio_si_legge_e_un_id_inesistente_o_non_numerico_da_errore() throws Exception {
        JsonNode q = createdQuote(YEAR, espositore(), 0, List.of(extraLine(YEAR, 1)));

        getQuote(q.get("quoteId").asInt()).andExpect(status().isOk())
                .andExpect(jsonPath("$.quoteNumber").value(q.get("quoteNumber").asText()));
        getQuote(999999).andExpect(status().isNotFound());
        mvc.perform(get("/quotes/abc").header(HttpHeaders.AUTHORIZATION, staff()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void solo_admin_e_commercial_possono_creare_e_leggere_preventivi() throws Exception {
        String body = json.writeValueAsString(quoteBody(YEAR, espositore(), 0, List.of(extraLine(YEAR, 1))));
        for (Role ruolo : List.of(Role.EXHIBITOR, Role.OPS, Role.SCANNER)) {
            mvc.perform(post("/quotes").header(HttpHeaders.AUTHORIZATION, bearer(espositore(), ruolo))
                            .header("Idempotency-Key", key()).contentType(MediaType.APPLICATION_JSON).content(body))
                    .andExpect(status().isForbidden());
        }
        mvc.perform(post("/quotes").header("Idempotency-Key", key()).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isUnauthorized());
        mvc.perform(post("/quotes").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.ADMIN))
                        .header("Idempotency-Key", key()).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated());
    }
}
