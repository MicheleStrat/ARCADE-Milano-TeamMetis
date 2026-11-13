package it.arcade.backend.security;

import it.arcade.backend.error.ApiException;
import java.util.EnumSet;
import java.util.List;
import java.util.Set;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/** SOLO SVILUPPO: emette token per provare ruoli e isolamento. Esiste solo con il profilo `dev`. */
@Profile("dev")
@RestController
public class DevTokenController {

    public record TokenRequest(String username, List<String> roles, Integer exhibitorId) {}

    public record TokenResponse(String accessToken, String tokenType, long expiresInSeconds) {}

    private final JwtService jwt;
    private final JwtProperties properties;

    public DevTokenController(JwtService jwt, JwtProperties properties) {
        this.jwt = jwt;
        this.properties = properties;
    }

    @PostMapping("/dev/token")
    public TokenResponse token(@RequestBody TokenRequest request) {
        if (request.username() == null || request.username().isBlank()) {
            throw invalid("username obbligatorio");
        }
        if (request.roles() == null || request.roles().isEmpty()) {
            throw invalid("indica almeno un ruolo");
        }
        Set<Role> roles = EnumSet.noneOf(Role.class);
        for (String name : request.roles()) {
            try {
                roles.add(Role.valueOf(name));
            } catch (IllegalArgumentException e) {
                throw invalid("ruolo sconosciuto: " + name);
            }
        }
        String token = jwt.issue(request.username(), roles, request.exhibitorId());
        return new TokenResponse(token, "Bearer", properties.ttlMinutes() * 60);
    }

    private static ApiException invalid(String detail) {
        return new ApiException(HttpStatus.BAD_REQUEST, "INVALID_REQUEST", "Richiesta non valida", detail);
    }
}
