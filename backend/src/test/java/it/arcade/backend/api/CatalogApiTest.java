package it.arcade.backend.api;

import static org.hamcrest.Matchers.nullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import it.arcade.backend.security.Role;
import it.arcade.backend.support.ApiTest;
import it.arcade.backend.support.Fixtures;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;

class CatalogApiTest extends ApiTest {

    @Autowired private ObjectMapper json;

    @Test
    void legge_edizione_dettaglio_padiglioni_e_categorie_con_i_ruoli_previsti() throws Exception {
        int editionId = Fixtures.edition(2098);
        mvc.perform(get("/editions/" + editionId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(exhibitorId("ESP901"), Role.EXHIBITOR)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.year").value(2098))
                .andExpect(jsonPath("$.days.length()").value(3));
        mvc.perform(get("/pavilions").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.EXHIBITOR)))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].code").value("P1"));
        mvc.perform(get("/exhibitor-categories").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.OPS)))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].name").exists());
        mvc.perform(get("/exhibitor-categories").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.EXHIBITOR)))
                .andExpect(status().isForbidden());
        mvc.perform(get("/editions/999999").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.ADMIN)))
                .andExpect(status().isNotFound());
    }

    @Test
    void floorplan_e_lista_stand_usano_i_filtri_e_la_paginazione_del_contratto() throws Exception {
        int standEditionId = Fixtures.newStand(2098, "P1", "12.50", "LINEA");
        int editionId = Fixtures.edition(2098);
        mvc.perform(get("/editions/" + editionId + "/floorplan")
                        .header(HttpHeaders.AUTHORIZATION, bearer(null, Role.OPS)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.editionId").value(editionId))
                .andExpect(jsonPath("$.pavilions.length()").value(3));
        mvc.perform(get("/editions/" + editionId + "/stands")
                        .param("pavilionCode", "P1").param("commercialStatus", "AVAILABLE")
                        .param("sort", "standCode,asc").param("page", "0").param("size", "1")
                        .header(HttpHeaders.AUTHORIZATION, bearer(null, Role.COMMERCIAL)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.page").value(0))
                .andExpect(jsonPath("$.size").value(1))
                .andExpect(jsonPath("$.totalElements").isNumber())
                .andExpect(jsonPath("$.content.length()").value(1));
        mvc.perform(get("/editions/" + editionId + "/stands")
                        .param("sort", "standCode;DROP TABLE core.stand")
                        .header(HttpHeaders.AUTHORIZATION, bearer(null, Role.ADMIN)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
        mvc.perform(get("/editions/999999/stands")
                        .header(HttpHeaders.AUTHORIZATION, bearer(null, Role.ADMIN)))
                .andExpect(status().isNotFound());
    }

    @Test
    void listino_espone_condizioni_e_voci_dell_edizione() throws Exception {
        mvc.perform(get("/editions/" + Fixtures.edition(2098) + "/price-list")
                        .header(HttpHeaders.AUTHORIZATION, bearer(null, Role.ADMIN)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("PUBLISHED"))
                .andExpect(jsonPath("$.depositPct").value(0.3))
                .andExpect(jsonPath("$.items[0].code").isString());
    }

    @Test
    void aggiorna_una_voce_non_usata_e_registra_audit() throws Exception {
        String code = "TEST-" + UUID.randomUUID().toString().substring(0, 8);
        int priceItemId = Fixtures.owner().queryForObject("""
                INSERT INTO core.price_item (price_list_id, code, name, item_type, unit, unit_price)
                SELECT price_list_id, ?, 'Voce test', 'EXTRA', 'EACH', 10.00
                  FROM core.price_list WHERE edition_id = ? RETURNING price_item_id
                """, Integer.class, code, Fixtures.edition(2099));
        mvc.perform(patch("/price-items/" + priceItemId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(null, Role.ADMIN))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"unitPrice\":12.35}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.unitPrice").value(12.35));
        org.junit.jupiter.api.Assertions.assertEquals(1, Fixtures.owner().queryForObject("""
                SELECT count(*) FROM core.audit_log WHERE entity = 'price_item' AND entity_id = ?
                """, Integer.class, String.valueOf(priceItemId)));
    }

    @Test
    void api_espositori_crea_modifica_filtra_e_protegge_i_contatti_dai_ruoli_ops() throws Exception {
        int categoryId = Fixtures.owner().queryForObject("""
                SELECT category_id FROM core.exhibitor_category WHERE name = 'Categoria di prova'
                """, Integer.class);
        String vat = vat();
        String body = json.writeValueAsString(Map.of("legalName", "Arcade Demo Srl", "vatNumber", vat,
                "categoryId", categoryId, "city", "Milano", "contactName", "Ada Esempio",
                "contactEmail", "ada@example.test"));
        JsonNode created = json.readTree(mvc.perform(post("/exhibitors")
                        .header(HttpHeaders.AUTHORIZATION, bearer(null, Role.COMMERCIAL))
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.exhibitorCode").value(org.hamcrest.Matchers.matchesPattern("ESP[0-9]{3,}")))
                .andExpect(jsonPath("$.primaryContact.email").value("ada@example.test"))
                .andReturn().getResponse().getContentAsString());
        int id = created.get("exhibitorId").asInt();

        mvc.perform(get("/exhibitors/" + id).header(HttpHeaders.AUTHORIZATION, bearer(null, Role.OPS)))
                .andExpect(status().isOk()).andExpect(jsonPath("$.primaryContact").value(nullValue()));
        mvc.perform(get("/exhibitors").param("q", "Arcade Demo")
                        .header(HttpHeaders.AUTHORIZATION, bearer(null, Role.COMMERCIAL)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content[0].exhibitorId").value(id))
                .andExpect(jsonPath("$.content[0].primaryContact.email").value("ada@example.test"));

        String update = json.writeValueAsString(Map.of("legalName", "Arcade Demo Aggiornata", "vatNumber", vat(),
                "categoryId", categoryId, "city", "Roma"));
        mvc.perform(put("/exhibitors/" + id)
                        .header(HttpHeaders.AUTHORIZATION, bearer(null, Role.ADMIN))
                        .contentType(MediaType.APPLICATION_JSON).content(update))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.legalName").value("Arcade Demo Aggiornata"))
                .andExpect(jsonPath("$.primaryContact").value(nullValue()));
    }

    @Test
    void rifiuta_partita_iva_duplicata_e_corpi_non_validi() throws Exception {
        int categoryId = Fixtures.owner().queryForObject("""
                SELECT category_id FROM core.exhibitor_category WHERE name = 'Categoria di prova'
                """, Integer.class);
        String duplicate = json.writeValueAsString(Map.of("legalName", "Duplicato Spa", "vatNumber", "IT00000000901",
                "categoryId", categoryId));
        mvc.perform(post("/exhibitors").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.ADMIN))
                        .contentType(MediaType.APPLICATION_JSON).content(duplicate))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("EXHIBITOR_ALREADY_EXISTS"));
        mvc.perform(post("/exhibitors").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.ADMIN))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"legalName\":\"X\",\"vatNumber\":\"bad\",\"categoryId\":-1}"))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void ruoli_fuori_perimetro_non_possono_scrivere_le_anagrafiche() throws Exception {
        mvc.perform(post("/exhibitors").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.OPS))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isForbidden())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"));
        mvc.perform(patch("/price-items/1").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.COMMERCIAL))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"unitPrice\":1}"))
                .andExpect(status().isForbidden());
    }

    private static String vat() {
        return "T" + UUID.randomUUID().toString().replace("-", "").substring(0, 13).toUpperCase();
    }
}
