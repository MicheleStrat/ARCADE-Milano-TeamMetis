package it.arcade.backend.api;

import static org.hamcrest.Matchers.emptyOrNullString;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.nullValue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import it.arcade.backend.security.JwtProperties;
import it.arcade.backend.security.JwtService;
import it.arcade.backend.security.Role;
import it.arcade.backend.support.ApiTest;
import java.time.Duration;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;

class MeApiTest extends ApiTest {

    @Test
    void senzaTokenRisponde401ConProblemJson() throws Exception {
        mvc.perform(get("/me"))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"))
                .andExpect(jsonPath("$.status").value(401))
                .andExpect(jsonPath("$.traceId").value(not(emptyOrNullString())));
    }

    @Test
    void tokenStaffMostraUtenteERuoli() throws Exception {
        mvc.perform(get("/me").header(HttpHeaders.AUTHORIZATION, bearer(null, Role.ADMIN)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.username").value("utente.prova"))
                .andExpect(jsonPath("$.roles", hasItem("ADMIN")))
                .andExpect(jsonPath("$.exhibitorId").value(nullValue()));
    }

    @Test
    void tokenEspositoreMostraLoStessoExhibitorIdDelToken() throws Exception {
        mvc.perform(get("/me").header(HttpHeaders.AUTHORIZATION, bearer(42, Role.EXHIBITOR)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.exhibitorId").value(42));
    }

    @Test
    void tokenFirmatoConUnaChiaveDiversaRisponde401() throws Exception {
        JwtService altro = new JwtService(new JwtProperties("un-altro-segreto-un-altro-segreto-0123", 60));
        String falso = altro.issue("intruso", Set.of(Role.ADMIN), null);

        mvc.perform(get("/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + falso))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void tokenScadutoRisponde401() throws Exception {
        String scaduto = jwt.issueClaims("utente.prova", List.of("ADMIN"), null, Duration.ofMinutes(-5));

        mvc.perform(get("/me").header(HttpHeaders.AUTHORIZATION, "Bearer " + scaduto))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void percorsoSconosciutoSenzaTokenRisponde401() throws Exception {
        mvc.perform(get("/non-esiste"))
                .andExpect(status().isUnauthorized());
    }
}
