package it.arcade.backend.commercial;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import it.arcade.backend.db.ScopedDb;
import it.arcade.backend.error.ApiException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.function.Function;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

/**
 * Stessa chiave = stessa risposta per 24 ore. La chiave si inserisce nella stessa transazione
 * dell'operazione: se l'operazione fallisce, annulla anche la chiave (si salvano solo i successi).
 * Due richieste con la stessa chiave in parallelo: la seconda attende l'indice univoco e poi
 * riceve la risposta salvata.
 */
@Service
public class IdempotencyService {

    public record Created(int status, Object body) {}

    public record Result(int status, String body, boolean replayed) {}

    private record Row(long id, String hash, Integer status, String body, boolean expired) {}

    private final ScopedDb db;
    private final ObjectMapper mapper;

    public IdempotencyService(ScopedDb db, ObjectMapper mapper) {
        this.db = db;
        this.mapper = mapper;
    }

    /** `hashInput` identifica la richiesta (operazione, risorsa e contenuto): deve avere ordine stabile (List, record). */
    public Result run(String principal, String operation, String key, Object hashInput,
                      Function<JdbcClient, Created> work) {
        if (key == null || key.length() < 8 || key.length() > 64) {
            throw ApiException.badRequest("VALIDATION_ERROR", "Idempotency-Key obbligatoria (da 8 a 64 caratteri)");
        }
        String hash = hash(hashInput);
        return db.write(jdbc -> {
            Long id = jdbc.sql("""
                            INSERT INTO core.idempotency_key (principal, operation, idem_key, request_hash)
                            VALUES (:p, :o, :k, :h)
                            ON CONFLICT (principal, operation, idem_key) DO NOTHING
                            RETURNING idempotency_key_id""")
                    .param("p", principal).param("o", operation).param("k", key).param("h", hash)
                    .query(Long.class).optional().orElse(null);
            if (id == null) {
                Row row = jdbc.sql("""
                                SELECT idempotency_key_id, request_hash, response_status, response_body,
                                       (created_at < now() - interval '24 hours') AS expired
                                  FROM core.idempotency_key
                                 WHERE principal = :p AND operation = :o AND idem_key = :k FOR UPDATE""")
                        .param("p", principal).param("o", operation).param("k", key)
                        .query((rs, n) -> new Row(rs.getLong(1), rs.getString(2), rs.getObject(3, Integer.class),
                                rs.getString(4), rs.getBoolean(5)))
                        .single();
                if (row.expired()) {
                    jdbc.sql("""
                                    UPDATE core.idempotency_key
                                       SET request_hash = :h, response_status = NULL, response_body = NULL,
                                           created_at = now()
                                     WHERE idempotency_key_id = :id""")
                            .param("h", hash).param("id", row.id()).update();
                    id = row.id();
                } else if (!row.hash().equals(hash)) {
                    throw new ApiException(HttpStatus.CONFLICT, "DUPLICATE_REQUEST",
                            "Stessa Idempotency-Key con contenuto diverso", null);
                } else if (row.status() == null) {
                    throw new ApiException(HttpStatus.CONFLICT, "DUPLICATE_REQUEST",
                            "Richiesta con questa chiave ancora in corso", null);
                } else {
                    return new Result(row.status(), row.body(), true);
                }
            }
            Created created = work.apply(jdbc);
            String body = json(created.body());
            jdbc.sql("""
                            UPDATE core.idempotency_key SET response_status = :s, response_body = :b
                             WHERE idempotency_key_id = :id""")
                    .param("s", created.status()).param("b", body).param("id", id).update();
            return new Result(created.status(), body, false);
        });
    }

    private String json(Object value) {
        try {
            return mapper.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Risposta non serializzabile", e);
        }
    }

    private String hash(Object input) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(json(input).getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
