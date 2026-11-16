package it.arcade.backend.support;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import it.arcade.backend.security.Role;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.ResultActions;

/** Aiuti per i test dei preventivi e dei contratti. */
public abstract class CommercialApiTest extends ApiTest {

    protected static final int YEAR = 2098;

    @Autowired protected ObjectMapper json;

    protected String staff() { return bearer(null, Role.COMMERCIAL); }

    protected static String key() { return UUID.randomUUID().toString(); }

    protected int espositore() { return exhibitorId("ESP901"); }

    protected Map<String, Object> spaceLine(int year, int standEditionId) {
        return Map.of("priceItemId", Fixtures.priceItem(year, "SP-P1"), "standEditionId", standEditionId, "quantity", 1);
    }

    protected Map<String, Object> extraLine(int year, int qty) {
        return Map.of("priceItemId", Fixtures.priceItem(year, "EX-EL6"), "quantity", qty);
    }

    protected Map<String, Object> quoteBody(int year, int exhibitorId, double discount, List<Map<String, Object>> lines) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("editionId", Fixtures.edition(year));
        body.put("exhibitorId", exhibitorId);
        body.put("discountPct", discount);
        body.put("lines", lines);
        return body;
    }

    protected ResultActions postQuote(String key, Object body) throws Exception {
        return mvc.perform(post("/quotes")
                .header(HttpHeaders.AUTHORIZATION, staff())
                .header("Idempotency-Key", key)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(body)));
    }

    protected JsonNode read(ResultActions r) throws Exception {
        return json.readTree(r.andReturn().getResponse().getContentAsString());
    }

    protected JsonNode createdQuote(int year, int exhibitorId, double discount, List<Map<String, Object>> lines)
            throws Exception {
        return read(postQuote(key(), quoteBody(year, exhibitorId, discount, lines)).andExpect(status().isCreated()));
    }

    protected ResultActions confirmedQuoteAction(int quoteId) throws Exception {
        mvc.perform(post("/quotes/" + quoteId + "/send").header(HttpHeaders.AUTHORIZATION, staff()).header("If-Match", 0))
                .andExpect(status().isOk());
        return mvc.perform(post("/quotes/" + quoteId + "/confirm").header(HttpHeaders.AUTHORIZATION, staff()).header("If-Match", 1));
    }

    /** Crea, invia e conferma un preventivo; restituisce il preventivo creato. */
    protected JsonNode confirmedQuote(int year, int exhibitorId, double discount, List<Map<String, Object>> lines)
            throws Exception {
        JsonNode q = createdQuote(year, exhibitorId, discount, lines);
        confirmedQuoteAction(q.get("quoteId").asInt()).andExpect(status().isOk());
        return q;
    }

    protected ResultActions convert(int quoteId, String key, String signedOn) throws Exception {
        return mvc.perform(post("/quotes/" + quoteId + "/contract")
                .header(HttpHeaders.AUTHORIZATION, staff()).header("Idempotency-Key", key)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(Map.of("signedOn", signedOn, "isRenewal", false))));
    }

    protected ResultActions getQuote(int quoteId) throws Exception {
        return mvc.perform(get("/quotes/" + quoteId).header(HttpHeaders.AUTHORIZATION, staff()));
    }
}
