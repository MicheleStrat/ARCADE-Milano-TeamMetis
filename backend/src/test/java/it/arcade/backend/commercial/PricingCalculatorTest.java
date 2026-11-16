package it.arcade.backend.commercial;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import it.arcade.backend.commercial.PricingCalculator.PriceItem;
import it.arcade.backend.commercial.PricingCalculator.PricedQuote;
import it.arcade.backend.commercial.PricingCalculator.StandInfo;
import it.arcade.backend.commercial.dto.QuoteLineInput;
import it.arcade.backend.error.ApiException;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class PricingCalculatorTest {

    private static BigDecimal d(String v) { return new BigDecimal(v); }

    private static final PriceItem SP1 = new PriceItem(1, "SP-P1", "Spazio P1", "SPACE", "SQM", d("100.00"), null, 1, null, null);
    private static final PriceItem MAG_ANG = new PriceItem(2, "MAG-ANGOLO", "Maggiorazione angolo", "SURCHARGE", "PCT_OF_SPACE", null, d("0.1000"), null, "ANGOLO", null);
    private static final PriceItem EXTRA = new PriceItem(3, "EX-EL6", "Allaccio", "EXTRA", "EACH", d("50.00"), null, null, null, null);
    private static final PriceItem SPN = new PriceItem(4, "SPN-GOLD", "Sponsor", "SPONSORSHIP", "PACKAGE", d("5000.00"), null, null, null, 1);
    private static final Map<Integer, PriceItem> ITEMS = Map.of(1, SP1, 2, MAG_ANG, 3, EXTRA, 4, SPN);

    private static final StandInfo ANGOLO = new StandInfo(10, "P1-A01", 1, d("10.00"), "ANGOLO");
    private static final StandInfo LINEA = new StandInfo(11, "P1-A02", 1, d("12.50"), "LINEA");
    private static final StandInfo P2 = new StandInfo(12, "P2-B01", 2, d("10.00"), "LINEA");
    private static final Map<Integer, StandInfo> STANDS = Map.of(10, ANGOLO, 11, LINEA, 12, P2);

    private static QuoteLineInput space(int standEditionId) { return new QuoteLineInput(1, standEditionId, null, null); }
    private static QuoteLineInput extra(String qty) { return new QuoteLineInput(3, null, d(qty), null); }

    @Test
    void spazio_con_maggiorazione_extra_e_sconto() {
        PricedQuote q = PricingCalculator.calculate(List.of(space(10), extra("2")), ITEMS, STANDS, d("0.1"));

        assertThat(q.lines()).hasSize(3);
        assertThat(q.lines().get(0).lineType()).isEqualTo("SPACE");
        assertThat(q.lines().get(0).amount()).isEqualByComparingTo("1000.00");
        assertThat(q.lines().get(1).lineType()).isEqualTo("SURCHARGE");
        assertThat(q.lines().get(1).amount()).isEqualByComparingTo("100.00");
        assertThat(q.lines().get(1).standEditionId()).isEqualTo(10);
        assertThat(q.lines().get(2).amount()).isEqualByComparingTo("100.00");
        assertThat(q.listAmount()).isEqualByComparingTo("1200.00");
        assertThat(q.netAmount()).isEqualByComparingTo("1080.00");
    }

    @Test
    void stand_in_linea_non_ha_maggiorazione_e_la_metratura_decide_la_quantita() {
        PricedQuote q = PricingCalculator.calculate(List.of(space(11)), ITEMS, STANDS, null);

        assertThat(q.lines()).hasSize(1);
        assertThat(q.lines().get(0).quantity()).isEqualByComparingTo("12.50");
        assertThat(q.lines().get(0).amount()).isEqualByComparingTo("1250.00");
        assertThat(q.netAmount()).isEqualByComparingTo("1250.00");
    }

    @Test
    void il_netto_si_arrotonda_a_due_decimali() {
        PricedQuote q = PricingCalculator.calculate(List.of(extra("1")), ITEMS, STANDS, d("0.3333"));

        assertThat(q.netAmount()).isEqualByComparingTo("33.34"); // 50 x 0.6667 = 33.335 -> 33.34
    }

    @Test
    void voce_di_un_altro_padiglione_e_rifiutata() {
        assertThatThrownBy(() -> PricingCalculator.calculate(List.of(space(12)), ITEMS, STANDS, null))
                .isInstanceOf(ApiException.class)
                .satisfies(e -> assertThat(((ApiException) e).errors().get(0).field()).isEqualTo("lines[0].priceItemId"));
    }

    @Test
    void le_maggiorazioni_non_si_inviano_dal_client() {
        assertThatThrownBy(() -> PricingCalculator.calculate(
                List.of(new QuoteLineInput(2, null, d("1"), null)), ITEMS, STANDS, null))
                .isInstanceOf(ApiException.class);
    }

    @Test
    void stand_ripetuto_stand_mancante_e_voce_sconosciuta_sono_errori() {
        assertThatThrownBy(() -> PricingCalculator.calculate(List.of(space(10), space(10)), ITEMS, STANDS, null))
                .isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> PricingCalculator.calculate(List.of(space(99)), ITEMS, STANDS, null))
                .isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> PricingCalculator.calculate(
                List.of(new QuoteLineInput(77, null, d("1"), null)), ITEMS, STANDS, null))
                .isInstanceOf(ApiException.class);
    }

    @Test
    void la_quantita_oltre_il_massimo_della_sponsorizzazione_e_rifiutata() {
        assertThatThrownBy(() -> PricingCalculator.calculate(
                List.of(new QuoteLineInput(4, null, d("2"), null)), ITEMS, STANDS, null))
                .isInstanceOf(ApiException.class);
    }

    @Test
    void maggiorazione_mancante_nel_listino_e_un_errore() {
        Map<Integer, PriceItem> senza = Map.of(1, SP1);
        assertThatThrownBy(() -> PricingCalculator.calculate(List.of(space(10)), senza, STANDS, null))
                .isInstanceOf(ApiException.class);
    }
}
