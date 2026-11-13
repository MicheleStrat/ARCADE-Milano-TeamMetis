package it.arcade.backend.support;

import it.arcade.backend.security.JwtService;
import it.arcade.backend.security.Role;
import java.util.Set;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
public abstract class ApiTest {

    @Autowired protected MockMvc mvc;
    @Autowired protected JwtService jwt;

    @DynamicPropertySource
    static void database(DynamicPropertyRegistry registry) {
        PostgresSupport.register(registry);
    }

    protected String bearer(Integer exhibitorId, Role... roles) {
        return "Bearer " + jwt.issue("utente.prova", Set.of(roles), exhibitorId);
    }

    protected int exhibitorId(String code) {
        return PostgresSupport.owner().queryForObject(
                "SELECT exhibitor_id FROM core.exhibitor WHERE exhibitor_code = ?", Integer.class, code);
    }
}
