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

class ConvertApiTest extends CommercialApiTest {

    private JsonNode preventivoConfermato(int stand) throws Exception {
        return confirmedQuote(YEAR, espositore(), 0.1, List.of(spaceLine(YEAR, stand), extraLine(YEAR, 2)));
    }

    @Test
    void il_percorso_completo_crea_il_contratto_con_acconto_e_saldo() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "ANGOLO");
        int quoteId = preventivoConfermato(stand).get("quoteId").asInt();

        JsonNode c = read(convert(quoteId, key(), "2098-06-01").andExpect(status().isCreated()));

        assertThat(c.get("contractNumber").asText()).matches("C2098-\\d{4}");
        assertThat(c.get("status").asText()).isEqualTo("SIGNED");
        assertThat(c.get("quoteId").asInt()).isEqualTo(quoteId);
        assertThat(c.get("netAmount").decimalValue()).isEqualByComparingTo("1080.00");
        assertThat(c.get("stands")).hasSize(1);
        assertThat(c.get("lines")).hasSize(3);
        JsonNode pay = c.get("payments");
        assertThat(pay).hasSize(2);
        assertThat(pay.get(0).get("kind").asText()).isEqualTo("DEPOSIT");
        assertThat(pay.get(0).get("dueAmount").decimalValue()).isEqualByComparingTo("324.00");   // 30 % di 1080
        assertThat(pay.get(0).get("dueOn").asText()).isEqualTo("2098-06-16");                    // firma + 15 giorni
        assertThat(pay.get(0).get("dueAmountBasis").asText()).isEqualTo("RULE_DERIVED");
        assertThat(pay.get(1).get("kind").asText()).isEqualTo("BALANCE");
        assertThat(pay.get(1).get("dueAmount").decimalValue()).isEqualByComparingTo("756.00");
        assertThat(pay.get(1).get("dueOn").asText()).isEqualTo("2098-11-18");                    // 18/12 - 30 giorni

        assertThat(Fixtures.owner().queryForMap("SELECT commercial_status, reserved_by_quote_id "
                + "FROM core.stand_edition WHERE stand_edition_id = ?", stand))
                .containsEntry("commercial_status", "SOLD").containsEntry("reserved_by_quote_id", null);
        assertThat(Fixtures.owner().queryForObject("SELECT status FROM core.quote WHERE quote_id = ?", String.class, quoteId))
                .isEqualTo("CONVERTED");
    }

    @Test
    void il_contratto_si_legge_e_serve_il_ruolo_giusto() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        JsonNode c = read(convert(preventivoConfermato(stand).get("quoteId").asInt(), key(), "2098-06-01")
                .andExpect(status().isCreated()));
        int id = c.get("contractId").asInt();

        mvc.perform(get("/contracts/" + id).header(HttpHeaders.AUTHORIZATION, bearer(null, Role.OPS)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.contractNumber").value(c.get("contractNumber").asText()));
        mvc.perform(get("/contracts/" + id).header(HttpHeaders.AUTHORIZATION, bearer(espositore(), Role.EXHIBITOR)))
                .andExpect(status().isForbidden());
        mvc.perform(get("/contracts/999999").header(HttpHeaders.AUTHORIZATION, staff())).andExpect(status().isNotFound());
    }

    @Test
    void la_sponsorizzazione_crea_la_riga_di_tracciamento() throws Exception {
        Map<String, Object> sponsor = Map.of("priceItemId", Fixtures.priceItem(YEAR, "SPN-GOLD"), "quantity", 1);
        JsonNode q = confirmedQuote(YEAR, exhibitorId("ESP902"), 0, List.of(sponsor));

        JsonNode c = read(convert(q.get("quoteId").asInt(), key(), "2098-06-01").andExpect(status().isCreated()));

        assertThat(Fixtures.owner().queryForObject("""
                SELECT count(*) FROM core.sponsorship s JOIN core.contract_line l ON l.contract_line_id = s.contract_line_id
                 WHERE l.contract_id = ?""", Integer.class, c.get("contractId").asInt())).isEqualTo(1);
    }

    @Test
    void un_preventivo_non_confermato_risponde_409_quote_not_confirmed() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int id = createdQuote(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand))).get("quoteId").asInt();

        convert(id, key(), "2098-06-01")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("QUOTE_NOT_CONFIRMED"));
    }

    @Test
    void la_data_di_firma_e_obbligatoria() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int id = preventivoConfermato(stand).get("quoteId").asInt();

        mvc.perform(post("/quotes/" + id + "/contract")
                        .header(HttpHeaders.AUTHORIZATION, staff()).header("Idempotency-Key", key())
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.errors[0].field").value("signedOn"));
    }

    @Test
    void la_ripetizione_con_la_stessa_chiave_non_duplica_il_contratto() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int quoteId = preventivoConfermato(stand).get("quoteId").asInt();
        String k = key();

        JsonNode first = read(convert(quoteId, k, "2098-06-01").andExpect(status().isCreated()));
        JsonNode second = read(convert(quoteId, k, "2098-06-01").andExpect(status().isCreated())
                .andExpect(header().string("Idempotent-Replayed", "true")));

        assertThat(second).isEqualTo(first);
        assertThat(Fixtures.owner().queryForObject("SELECT count(*) FROM core.contract WHERE quote_id = ?", Integer.class, quoteId))
                .isEqualTo(1);
        convert(quoteId, key(), "2098-06-01") // chiave nuova dopo la conversione
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("QUOTE_NOT_CONFIRMED"));
    }

    @Test
    void se_un_altro_preventivo_ha_ripreso_lo_stand_la_conversione_risponde_409_e_non_cambia_nulla() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int quoteA = preventivoConfermato(stand).get("quoteId").asInt();
        Fixtures.owner().update("UPDATE core.stand_edition SET reserved_until = now() - interval '1 hour' "
                + "WHERE stand_edition_id = ?", stand);
        createdQuote(YEAR, exhibitorId("ESP902"), 0, List.of(spaceLine(YEAR, stand))); // B riprende lo stand

        convert(quoteA, key(), "2098-06-01")
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("STAND_ALREADY_RESERVED"));

        assertThat(Fixtures.owner().queryForObject("SELECT status FROM core.quote WHERE quote_id = ?", String.class, quoteA))
                .isEqualTo("CONFIRMED");
        assertThat(Fixtures.owner().queryForObject("SELECT count(*) FROM core.contract WHERE quote_id = ?", Integer.class, quoteA))
                .isZero();
    }

    @Test
    void edizione_senza_date_risponde_422_e_non_lascia_nulla() throws Exception {
        int stand = Fixtures.newStand(2099, "P1", "10.00", "LINEA");
        int quoteId = confirmedQuote(2099, espositore(), 0, List.of(spaceLine(2099, stand))).get("quoteId").asInt();

        convert(quoteId, key(), "2099-06-01")
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("EDITION_DATES_MISSING"));

        assertThat(Fixtures.owner().queryForObject("SELECT status FROM core.quote WHERE quote_id = ?", String.class, quoteId))
                .isEqualTo("CONFIRMED");
        assertThat(Fixtures.owner().queryForObject(
                "SELECT commercial_status FROM core.stand_edition WHERE stand_edition_id = ?", String.class, stand))
                .isEqualTo("RESERVED");
        assertThat(Fixtures.owner().queryForObject("SELECT count(*) FROM core.contract WHERE quote_id = ?", Integer.class, quoteId))
                .isZero();
    }

    @Test
    void condizioni_di_pagamento_mancanti_nel_listino_rispondono_422() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int quoteId = preventivoConfermato(stand).get("quoteId").asInt();
        int edition = Fixtures.edition(YEAR);
        Fixtures.owner().update("UPDATE core.price_list SET deposit_pct = NULL WHERE edition_id = ?", edition);
        try {
            convert(quoteId, key(), "2098-06-01")
                    .andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.code").value("PRICE_LIST_CONDITIONS_MISSING"));
        } finally {
            Fixtures.owner().update("UPDATE core.price_list SET deposit_pct = 0.3000 WHERE edition_id = ?", edition);
        }
    }

    @Test
    void l_acconto_non_scade_dopo_il_saldo() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int quoteId = preventivoConfermato(stand).get("quoteId").asInt();

        JsonNode c = read(convert(quoteId, key(), "2098-11-10").andExpect(status().isCreated())); // saldo il 18/11

        assertThat(c.get("payments").get(0).get("dueOn").asText()).isEqualTo("2098-11-18"); // non 25/11
    }
}
