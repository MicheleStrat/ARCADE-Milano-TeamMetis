package it.arcade.backend.security;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import it.arcade.backend.support.ApiTest;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

/** Senza il profilo dev l'endpoint che emette token non deve esistere. */
class DevTokenDisabledApiTest extends ApiTest {

    @Test
    void senza_profilo_dev_l_endpoint_non_esiste() throws Exception {
        mvc.perform(post("/dev/token").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"username\":\"x\",\"roles\":[\"ADMIN\"]}"))
                .andExpect(status().isNotFound());
    }
}
