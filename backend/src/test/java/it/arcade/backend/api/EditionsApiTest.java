package it.arcade.backend.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import it.arcade.backend.security.Role;
import it.arcade.backend.support.ApiTest;
import java.time.Duration;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;

class EditionsApiTest extends ApiTest {

    @Test
    void lo_staff_legge_le_edizioni_con_i_giorni() throws Exception {
        mvc.perform(get("/editions").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.COMMERCIAL)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(3))
                .andExpect(jsonPath("$[0].year").value(2024))
                .andExpect(jsonPath("$[0].status").value("CLOSED"))
                .andExpect(jsonPath("$[0].days.length()").value(3))
                .andExpect(jsonPath("$[0].days[0].dayDate").value("2024-12-20"))
                .andExpect(jsonPath("$[0].days[0].opensAt").value("09:00"))
                .andExpect(jsonPath("$[0].days[0].closesAt").value("17:30"))
                .andExpect(jsonPath("$[2].days.length()").value(0));
    }

    @Test
    void l_espositore_puo_leggere_le_edizioni() throws Exception {
        mvc.perform(get("/editions").header(HttpHeaders.AUTHORIZATION, bearer(exhibitorId("ESP901"), Role.EXHIBITOR)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(3));
    }

    @Test
    void il_ruolo_scanner_non_e_autorizzato() throws Exception {
        mvc.perform(get("/editions").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.SCANNER)))
                .andExpect(status().isForbidden())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(jsonPath("$.code").value("FORBIDDEN"));
    }

    @Test
    void un_token_con_soli_ruoli_sconosciuti_non_e_autorizzato() throws Exception {
        String token = jwt.issueClaims("utente.prova", List.of("SUPERUSER", "root"), null, Duration.ofMinutes(5));

        mvc.perform(get("/editions").header(HttpHeaders.AUTHORIZATION, "Bearer " + token))
                .andExpect(status().isForbidden());
    }

    @Test
    void senza_token_risponde_401() throws Exception {
        mvc.perform(get("/editions")).andExpect(status().isUnauthorized());
    }
}
