package it.arcade.backend.commercial;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import it.arcade.backend.support.CommercialApiTest;
import it.arcade.backend.support.Fixtures;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.function.IntFunction;
import org.junit.jupiter.api.Test;

/** Richieste in parallelo sul pool di connessioni predefinito (piu' di una): provano i blocchi veri del database. */
class ConcurrencyApiTest extends CommercialApiTest {

    private record Reply(int status, JsonNode body) {}

    private List<Reply> inParallelo(int n, IntFunction<Callable<Reply>> factory) throws Exception {
        ExecutorService pool = Executors.newFixedThreadPool(n);
        CountDownLatch via = new CountDownLatch(1);
        List<Future<Reply>> futures = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            Callable<Reply> task = factory.apply(i);
            futures.add(pool.submit(() -> { via.await(); return task.call(); }));
        }
        via.countDown();
        List<Reply> out = new ArrayList<>();
        for (Future<Reply> f : futures) {
            out.add(f.get());
        }
        pool.shutdown();
        return out;
    }

    private Reply creaPreventivo(String key, Map<String, Object> body) throws Exception {
        var res = postQuote(key, body).andReturn().getResponse();
        return new Reply(res.getStatus(), json.readTree(res.getContentAsString()));
    }

    private long conStato(List<Reply> replies, int status) {
        return replies.stream().filter(r -> r.status() == status).count();
    }

    @Test
    void molti_preventivi_sullo_stesso_stand_ne_hanno_uno_solo_che_vince() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        Map<String, Object> body = quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand)));

        List<Reply> r = inParallelo(8, i -> () -> creaPreventivo(key(), body));

        assertThat(conStato(r, 201)).isEqualTo(1);
        assertThat(conStato(r, 409)).isEqualTo(7);
        assertThat(Fixtures.owner().queryForObject(
                "SELECT count(*) FROM core.quote_line WHERE stand_edition_id = ?", Integer.class, stand)).isEqualTo(1);
    }

    @Test
    void stand_in_ordine_opposto_non_vanno_in_stallo() throws Exception {
        int s1 = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int s2 = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        Map<String, Object> ab = quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, s1), spaceLine(YEAR, s2)));
        Map<String, Object> ba = quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, s2), spaceLine(YEAR, s1)));

        List<Reply> r = inParallelo(8, i -> () -> creaPreventivo(key(), i % 2 == 0 ? ab : ba));

        assertThat(conStato(r, 201)).isEqualTo(1);
        assertThat(conStato(r, 409)).isEqualTo(7); // nessun 500: nessuno stallo
    }

    @Test
    void la_stessa_chiave_in_parallelo_ha_un_solo_effetto() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        Map<String, Object> body = quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand)));
        String k = key();

        List<Reply> r = inParallelo(6, i -> () -> creaPreventivo(k, body));

        assertThat(conStato(r, 201)).isEqualTo(6);
        assertThat(r.stream().map(x -> x.body().get("quoteId").asInt()).distinct()).hasSize(1);
        assertThat(Fixtures.owner().queryForObject(
                "SELECT count(*) FROM core.quote_line WHERE stand_edition_id = ?", Integer.class, stand)).isEqualTo(1);
    }

    @Test
    void i_numeri_dei_preventivi_creati_in_parallelo_sono_distinti() throws Exception {
        List<Integer> stand = new ArrayList<>();
        for (int i = 0; i < 6; i++) {
            stand.add(Fixtures.newStand(YEAR, "P1", "10.00", "LINEA"));
        }

        List<Reply> r = inParallelo(6, i -> () -> creaPreventivo(key(),
                quoteBody(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand.get(i))))));

        assertThat(conStato(r, 201)).isEqualTo(6);
        assertThat(r.stream().map(x -> x.body().get("quoteNumber").asText()).distinct()).hasSize(6);
    }

    @Test
    void conversioni_concorrenti_con_chiavi_diverse_creano_un_solo_contratto() throws Exception {
        int stand = Fixtures.newStand(YEAR, "P1", "10.00", "LINEA");
        int quoteId = confirmedQuote(YEAR, espositore(), 0, List.of(spaceLine(YEAR, stand))).get("quoteId").asInt();

        List<Reply> r = inParallelo(6, i -> () -> {
            var res = convert(quoteId, key(), "2098-06-01").andReturn().getResponse();
            return new Reply(res.getStatus(), json.readTree(res.getContentAsString()));
        });

        assertThat(conStato(r, 201)).isEqualTo(1);
        assertThat(conStato(r, 409)).isEqualTo(5);
        assertThat(Fixtures.owner().queryForObject("SELECT count(*) FROM core.contract WHERE quote_id = ?", Integer.class, quoteId))
                .isEqualTo(1);
    }
}
