package it.arcade.backend.commercial;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import it.arcade.backend.commercial.IdempotencyService.Created;
import it.arcade.backend.commercial.IdempotencyService.Result;
import it.arcade.backend.db.ScopedDb;
import it.arcade.backend.error.ApiException;
import it.arcade.backend.support.Fixtures;
import it.arcade.backend.support.PostgresSupport;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

@SpringBootTest
class IdempotencyServiceTest {

    @Autowired IdempotencyService idem;
    @Autowired ScopedDb db;
    @Autowired NumberGenerator numbers;

    @DynamicPropertySource
    static void database(DynamicPropertyRegistry registry) {
        PostgresSupport.register(registry);
    }

    private static String key() { return UUID.randomUUID().toString(); }

    @Test
    void la_prima_volta_esegue_e_la_seconda_restituisce_la_risposta_salvata() {
        String k = key();
        AtomicInteger eseguite = new AtomicInteger();

        Result a = idem.run("u", "op", k, List.of("x"), j -> { eseguite.incrementAndGet(); return new Created(201, List.of("ok")); });
        Result b = idem.run("u", "op", k, List.of("x"), j -> { eseguite.incrementAndGet(); return new Created(201, List.of("altro")); });

        assertThat(eseguite.get()).isEqualTo(1);
        assertThat(a.replayed()).isFalse();
        assertThat(b.replayed()).isTrue();
        assertThat(b.status()).isEqualTo(201);
        assertThat(b.body()).isEqualTo(a.body());
    }

    @Test
    void stessa_chiave_con_contenuto_diverso_da_409_duplicate_request() {
        String k = key();
        idem.run("u", "op", k, List.of("x"), j -> new Created(201, "ok"));

        assertThatThrownBy(() -> idem.run("u", "op", k, List.of("diverso"), j -> new Created(201, "ok")))
                .isInstanceOf(ApiException.class)
                .satisfies(e -> assertThat(((ApiException) e).code()).isEqualTo("DUPLICATE_REQUEST"));
    }

    @Test
    void una_richiesta_fallita_non_consuma_la_chiave() {
        String k = key();
        assertThatThrownBy(() -> idem.run("u", "op", k, List.of("x"), j -> { throw ApiException.conflict("X", "x"); }))
                .isInstanceOf(ApiException.class);

        Result r = idem.run("u", "op", k, List.of("x"), j -> new Created(201, "ok"));
        assertThat(r.replayed()).isFalse();
    }

    @Test
    void una_chiave_di_piu_di_24_ore_riparte_anche_con_contenuto_diverso() {
        String k = key();
        idem.run("u", "op", k, List.of("x"), j -> new Created(201, "prima"));
        Fixtures.owner().update("UPDATE core.idempotency_key SET created_at = now() - interval '25 hours' "
                + "WHERE idem_key = ?", k);

        Result r = idem.run("u", "op", k, List.of("diverso"), j -> new Created(201, "seconda"));
        assertThat(r.replayed()).isFalse();
        assertThat(r.body()).contains("seconda");
    }

    @Test
    void chiavi_di_utenti_o_operazioni_diverse_non_si_scontrano() {
        String k = key();
        idem.run("u1", "op", k, List.of("x"), j -> new Created(201, "1"));
        Result r = idem.run("u2", "op", k, List.of("x"), j -> new Created(201, "2"));
        assertThat(r.replayed()).isFalse();
    }

    @Test
    void la_chiave_deve_avere_da_8_a_64_caratteri() {
        assertThatThrownBy(() -> idem.run("u", "op", "corta", List.of("x"), j -> new Created(201, "ok")))
                .isInstanceOf(ApiException.class)
                .satisfies(e -> assertThat(((ApiException) e).status().value()).isEqualTo(400));
        assertThatThrownBy(() -> idem.run("u", "op", null, List.of("x"), j -> new Created(201, "ok")))
                .isInstanceOf(ApiException.class);
    }

    @Test
    void i_numeri_sono_progressivi_per_anno() {
        String a = db.write(j -> numbers.next(j, "Q", 2090, "core.quote", "quote_number"));
        assertThat(a).isEqualTo("Q2090-0001");
        db.write(j -> {
            j.sql("INSERT INTO core.quote (quote_number, edition_id, exhibitor_id) VALUES ('Q2090-0007', ?, ?)")
                    .param(Fixtures.edition(2098))
                    .param(Fixtures.owner().queryForObject("SELECT min(exhibitor_id) FROM core.exhibitor", Integer.class))
                    .update();
            return null;
        });
        String b = db.write(j -> numbers.next(j, "Q", 2090, "core.quote", "quote_number"));
        assertThat(b).isEqualTo("Q2090-0008");
    }
}
