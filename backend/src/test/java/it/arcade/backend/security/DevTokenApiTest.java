package it.arcade.backend.security;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import it.arcade.backend.support.ApiTest;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;

@ActiveProfiles("dev")
class DevTokenApiTest extends ApiTest {

    @Autowired ObjectMapper json;

    private String richiesta(String username, String... roles) throws Exception {
        return json.writeValueAsString(Map.of("username", username, "roles", List.of(roles)));
    }

    @Test
    void emette_un_token_che_funziona_su_me() throws Exception {
        String risposta = mvc.perform(post("/dev/token").contentType(MediaType.APPLICATION_JSON)
                        .content(richiesta("mattia", "ADMIN")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tokenType").value("Bearer"))
                .andReturn().getResponse().getContentAsString();
        String token = json.readTree(risposta).get("accessToken").asText();

        mvc.perform(get("/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.username").value("mattia"));
    }

    @Test
    void rifiuta_un_ruolo_inesistente() throws Exception {
        mvc.perform(post("/dev/token").contentType(MediaType.APPLICATION_JSON)
                        .content(richiesta("mattia", "SUPERUSER")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_REQUEST"));
    }

    @Test
    void rifiuta_un_corpo_malformato() throws Exception {
        mvc.perform(post("/dev/token").contentType(MediaType.APPLICATION_JSON).content("{non json"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_REQUEST"));
    }
}
