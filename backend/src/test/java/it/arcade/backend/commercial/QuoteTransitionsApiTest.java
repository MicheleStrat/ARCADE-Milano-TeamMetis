package it.arcade.backend.commercial;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import it.arcade.backend.support.CommercialApiTest;
import it.arcade.backend.support.Fixtures;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.test.web.servlet.ResultActions;

class QuoteTransitionsApiTest extends CommercialApiTest {

    private ResultActions transition(int quoteId, String azione, Object ifMatch) throws Exception {
        var req = post("/quotes/" + quoteId + "/" + azione).header(HttpHeaders.AUTHORIZATION, staff());
        if (ifMatch != null) {
            req = req.header("If-Match", ifMatch);
        }
        return mvc.perform(req);
    }

    private JsonNode nuovo() throws Exception {
        return createdQuote(YEAR, espositore(), 0, List.of(extraLine(YEAR, 1)));
    }

    @Test
    void il_percorso_bozza_inviato_confermato_aggiorna_stato_e_versione() throws Exception {
        int id = nuovo().get("quoteId").asInt();

        transition(id, "send", 0).andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("SENT")).andExpect(jsonPath("$.rowVersion").value(1));
        transition(id, "confirm", "\"1\"").andExpect(status().isOk()) // anche con le virgolette
                .andExpect(jsonPath("$.status").value("CONFIRMED")).andExpect(jsonPath("$.rowVersion").value(2));
    }

    @Test
    void una_versione_non_attuale_risponde_409_optimistic_lock_conflict() throws Exception {
        int id = nuovo().get("quoteId").asInt();
        transition(id, "send", 0).andExpect(status().isOk());

        transition(id, "confirm", 0)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("OPTIMISTIC_LOCK_CONFLICT"));
    }

    @Test
    void un_passaggio_non_permesso_risponde_409_invalid_state_transition() throws Exception {
        int id = nuovo().get("quoteId").asInt();

        transition(id, "confirm", 0) // dalla bozza non si conferma
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("INVALID_STATE_TRANSITION"));
        transition(id, "send", 0).andExpect(status().isOk());
        transition(id, "send", 1) // gia' inviato
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("INVALID_STATE_TRANSITION"));
    }

    @Test
    void if_match_mancante_o_non_numerico_risponde_400_e_un_id_inesistente_404() throws Exception {
        int id = nuovo().get("quoteId").asInt();

        transition(id, "send", null).andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
        transition(id, "send", "abc").andExpect(status().isBadRequest());
        transition(999999, "send", 0).andExpect(status().isNotFound());
    }

    @Test
    void un_preventivo_scaduto_non_si_conferma() throws Exception {
        int id = nuovo().get("quoteId").asInt();
        transition(id, "send", 0).andExpect(status().isOk());
        Fixtures.owner().update("UPDATE core.quote SET valid_until = CURRENT_DATE - 1 WHERE quote_id = ?", id);

        transition(id, "confirm", 1)
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("QUOTE_EXPIRED"));
    }
}
