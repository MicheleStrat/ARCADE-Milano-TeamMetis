package it.arcade.backend.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import it.arcade.backend.security.Role;
import it.arcade.backend.support.ApiTest;
import it.arcade.backend.support.PostgresSupport;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;

class PortalApiTest extends ApiTest {

    @Test
    void l_espositore_vede_solo_il_proprio_profilo() throws Exception {
        int alfa = exhibitorId("ESP901");

        mvc.perform(get("/portal/me").header(HttpHeaders.AUTHORIZATION, bearer(alfa, Role.EXHIBITOR)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.exhibitorId").value(alfa))
                .andExpect(jsonPath("$.exhibitorCode").value("ESP901"))
                .andExpect(jsonPath("$.legalName").value("Alfa Srl"))
                .andExpect(jsonPath("$.categoryName").value("Categoria di prova"));
    }

    @Test
    void un_altro_espositore_non_vede_i_dati_del_primo() throws Exception {
        int beta = exhibitorId("ESP902");

        mvc.perform(get("/portal/me").header(HttpHeaders.AUTHORIZATION, bearer(beta, Role.EXHIBITOR)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.exhibitorCode").value("ESP902"));
    }

    @Test
    void senza_exhibitor_id_nel_token_non_si_vede_nulla() throws Exception {
        mvc.perform(get("/portal/me").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.EXHIBITOR)))
                .andExpect(status().isNotFound())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(jsonPath("$.code").value("PORTAL_PROFILE_NOT_FOUND"));
    }

    @Test
    void un_exhibitor_id_inesistente_risponde_404() throws Exception {
        mvc.perform(get("/portal/me").header(HttpHeaders.AUTHORIZATION, bearer(999999, Role.EXHIBITOR)))
                .andExpect(status().isNotFound());
    }

    @Test
    void il_filtro_sull_id_vale_anche_se_la_rls_fosse_permissiva() throws Exception {
        int alfa = exhibitorId("ESP901");
        var owner = PostgresSupport.owner();
        owner.execute("CREATE POLICY test_permissiva ON core.exhibitor FOR SELECT TO arcade_portal USING (true)");
        try {
            mvc.perform(get("/portal/me").header(HttpHeaders.AUTHORIZATION, bearer(alfa, Role.EXHIBITOR)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.exhibitorCode").value("ESP901"));
        } finally {
            owner.execute("DROP POLICY test_permissiva ON core.exhibitor");
        }
    }

    @Test
    void lo_staff_non_puo_usare_il_portale() throws Exception {
        mvc.perform(get("/portal/me").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.ADMIN)))
                .andExpect(status().isForbidden());
    }

    @Test
    void un_token_con_ruolo_staff_ed_espositore_vede_solo_il_proprio_profilo() throws Exception {
        int alfa = exhibitorId("ESP901");

        mvc.perform(get("/portal/me").header(HttpHeaders.AUTHORIZATION, bearer(alfa, Role.ADMIN, Role.EXHIBITOR)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.exhibitorCode").value("ESP901"));
    }
}
