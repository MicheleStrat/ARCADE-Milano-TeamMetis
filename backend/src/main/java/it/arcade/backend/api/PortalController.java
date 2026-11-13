package it.arcade.backend.api;

import it.arcade.backend.db.DbRole;
import it.arcade.backend.db.ScopedDb;
import it.arcade.backend.error.ApiException;
import it.arcade.backend.security.CurrentUser;
import java.util.Optional;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class PortalController {

    public record PortalProfile(int exhibitorId, String exhibitorCode, String legalName, String categoryName) {}

    private final ScopedDb db;

    public PortalController(ScopedDb db) {
        this.db = db;
    }

    /**
     * Usa SEMPRE il ruolo PORTAL, anche se il token ha pure un ruolo staff: la query non ha un filtro
     * sull'id, e' la sicurezza per riga del database a limitare il risultato al proprio espositore.
     */
    @GetMapping("/portal/me")
    public PortalProfile me(@AuthenticationPrincipal Jwt jwt) {
        CurrentUser user = CurrentUser.from(jwt);
        Optional<PortalProfile> profile = db.read(DbRole.PORTAL, user.exhibitorId(), jdbc -> jdbc.sql("""
                        SELECT e.exhibitor_id, e.exhibitor_code, e.legal_name, c.name AS category_name
                          FROM core.exhibitor e
                          JOIN core.exhibitor_category c ON c.category_id = e.category_id
                        """)
                .query((rs, n) -> new PortalProfile(rs.getInt("exhibitor_id"), rs.getString("exhibitor_code"),
                        rs.getString("legal_name"), rs.getString("category_name")))
                .optional());
        return profile.orElseThrow(() ->
                ApiException.notFound("PORTAL_PROFILE_NOT_FOUND", "Profilo espositore non trovato"));
    }
}
