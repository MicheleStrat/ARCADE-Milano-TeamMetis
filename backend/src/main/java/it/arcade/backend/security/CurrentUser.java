package it.arcade.backend.security;

import java.util.EnumSet;
import java.util.List;
import java.util.Set;
import org.springframework.security.oauth2.jwt.Jwt;

/** Utente che ha fatto la richiesta, ricavato dal token. I ruoli sconosciuti vengono ignorati. */
public record CurrentUser(String username, String displayName, Set<Role> roles, Integer exhibitorId) {

    public static CurrentUser from(Jwt jwt) {
        Set<Role> roles = EnumSet.noneOf(Role.class);
        List<String> raw = jwt.getClaimAsStringList("roles");
        if (raw != null) {
            for (String name : raw) {
                try {
                    roles.add(Role.valueOf(name));
                } catch (IllegalArgumentException ignored) {
                    // ruolo non previsto dal contratto: non concede nulla
                }
            }
        }
        Object id = jwt.getClaim("exhibitor_id");
        Integer exhibitorId = id instanceof Number n ? n.intValue() : null;
        return new CurrentUser(jwt.getSubject(), jwt.getClaimAsString("name"), roles, exhibitorId);
    }
}
