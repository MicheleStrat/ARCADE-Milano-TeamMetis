package it.arcade.backend.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import it.arcade.backend.support.ApiTest;
import org.junit.jupiter.api.Test;

class HealthApiTest extends ApiTest {

    @Test
    void rispondeSenzaTokenEIndicaCheIlDatabaseRisponde() throws Exception {
        mvc.perform(get("/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }
}
