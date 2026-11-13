package it.arcade.backend.security;

import com.nimbusds.jose.jwk.source.ImmutableSecret;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Set;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;
import org.springframework.stereotype.Service;

/**
 * Firma e verifica i token con una chiave HMAC locale (solo sviluppo). Per passare a Entra ID
 * si sostituisce il decoder con uno basato sull'indirizzo dell'emittente: i controller non cambiano.
 */
@Service
public class JwtService {

    private final SecretKey key;
    private final JwtEncoder encoder;
    private final Duration defaultTtl;

    public JwtService(JwtProperties properties) {
        String secret = properties.secret() == null ? "" : properties.secret();
        byte[] bytes = secret.getBytes(StandardCharsets.UTF_8);
        if (bytes.length < 32) {
            throw new IllegalStateException(
                    "La chiave dei token e' mancante o troppo corta: imposta JWT_DEV_SECRET con almeno 32 caratteri.");
        }
        this.key = new SecretKeySpec(bytes, "HmacSHA256");
        this.encoder = new NimbusJwtEncoder(new ImmutableSecret<>(key));
        this.defaultTtl = Duration.ofMinutes(properties.ttlMinutes());
    }

    public JwtDecoder decoder() {
        return NimbusJwtDecoder.withSecretKey(key).macAlgorithm(MacAlgorithm.HS256).build();
    }

    public String issue(String username, Set<Role> roles, Integer exhibitorId) {
        List<String> names = roles.stream().map(Role::name).sorted().toList();
        return issueClaims(username, names, exhibitorId, defaultTtl);
    }

    /** Accetta anche nomi di ruolo qualsiasi: serve ai test per provare i ruoli sconosciuti. */
    public String issueClaims(String username, Collection<String> roles, Integer exhibitorId, Duration ttl) {
        Instant now = Instant.now();
        Instant expiresAt = now.plus(ttl);
        // Con una durata negativa (token gia' scaduto, per i test) l'emissione deve restare prima della scadenza.
        Instant issuedAt = expiresAt.isAfter(now) ? now : expiresAt.minusSeconds(1);
        JwtClaimsSet.Builder claims = JwtClaimsSet.builder()
                .subject(username)
                .issuedAt(issuedAt)
                .expiresAt(expiresAt)
                .claim("roles", List.copyOf(roles));
        if (exhibitorId != null) {
            claims.claim("exhibitor_id", exhibitorId);
        }
        JwsHeader header = JwsHeader.with(MacAlgorithm.HS256).build();
        return encoder.encode(JwtEncoderParameters.from(header, claims.build())).getTokenValue();
    }
}
