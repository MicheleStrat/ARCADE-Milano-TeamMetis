package it.arcade.backend.api;

import com.fasterxml.jackson.annotation.JsonInclude;
import it.arcade.backend.security.CurrentUser;
import it.arcade.backend.security.Role;
import java.util.List;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class MeController {

    /** Schema `CurrentUser` del contratto: `exhibitorId` e' sempre presente (null per lo staff). */
    public record CurrentUserResponse(
            String username,
            @JsonInclude(JsonInclude.Include.NON_NULL) String displayName,
            List<Role> roles,
            Integer exhibitorId) {}

    @GetMapping("/me")
    public CurrentUserResponse me(@AuthenticationPrincipal Jwt jwt) {
        CurrentUser user = CurrentUser.from(jwt);
        return new CurrentUserResponse(
                user.username(), user.displayName(), user.roles().stream().sorted().toList(), user.exhibitorId());
    }
}
