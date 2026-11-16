package it.arcade.backend.commercial;

import it.arcade.backend.commercial.dto.QuoteLineInput;
import it.arcade.backend.error.ValidationErrors;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/** Calcolo dei prezzi di un preventivo: funzione pura, senza accesso al database. */
public final class PricingCalculator {

    public record PriceItem(int priceItemId, String code, String name, String itemType, String unit,
                            BigDecimal unitPrice, BigDecimal pct, Integer pavilionId, String positionType,
                            Integer maxQuantity) {}

    public record StandInfo(int standEditionId, String standCode, int pavilionId, BigDecimal sqm,
                            String positionType) {}

    public record PricedLine(String lineType, int priceItemId, Integer standEditionId, String description,
                             BigDecimal quantity, BigDecimal unitPrice, BigDecimal amount) {}

    public record PricedQuote(List<PricedLine> lines, BigDecimal listAmount, BigDecimal netAmount) {}

    private static final BigDecimal MAX_QUANTITY = new BigDecimal("9999999999.99");   // numeric(12,2)
    private static final BigDecimal MAX_AMOUNT = new BigDecimal("9999999999.99");

    private PricingCalculator() {}

    private static BigDecimal money(BigDecimal v) {
        return v.setScale(2, RoundingMode.HALF_UP);
    }

    public static PricedQuote calculate(List<QuoteLineInput> inputs, Map<Integer, PriceItem> items,
                                        Map<Integer, StandInfo> stands, BigDecimal discountPct) {
        ValidationErrors errors = new ValidationErrors();
        Map<String, PriceItem> surcharges = new HashMap<>();
        items.values().stream().filter(i -> "SURCHARGE".equals(i.itemType()))
                .forEach(i -> surcharges.put(i.positionType(), i));

        List<PricedLine> lines = new ArrayList<>();
        Set<Integer> seenStands = new HashSet<>();

        for (int i = 0; i < inputs.size(); i++) {
            QuoteLineInput in = inputs.get(i);
            String f = "lines[" + i + "]";
            if (in == null || in.priceItemId() == null) {
                errors.add(f + ".priceItemId", "obbligatorio");
                continue;
            }
            PriceItem item = items.get(in.priceItemId());
            if (item == null) {
                errors.add(f + ".priceItemId", "voce non presente nel listino dell'edizione");
                continue;
            }
            switch (item.itemType()) {
                case "SPACE" -> addSpace(in, item, f, stands, surcharges, seenStands, lines, errors);
                case "SURCHARGE" -> errors.add(f + ".priceItemId", "le maggiorazioni sono calcolate dal server");
                default -> addOther(in, item, f, lines, errors);
            }
        }
        errors.throwIfAny();

        BigDecimal list = money(lines.stream().map(PricedLine::amount).reduce(BigDecimal.ZERO, BigDecimal::add));
        BigDecimal d = discountPct == null ? BigDecimal.ZERO : discountPct;
        BigDecimal net = money(list.multiply(BigDecimal.ONE.subtract(d)));
        return new PricedQuote(lines, list, net);
    }

    private static void addSpace(QuoteLineInput in, PriceItem item, String f, Map<Integer, StandInfo> stands,
                                 Map<String, PriceItem> surcharges, Set<Integer> seenStands,
                                 List<PricedLine> lines, ValidationErrors errors) {
        if (in.standEditionId() == null) {
            errors.add(f + ".standEditionId", "obbligatorio per le voci di tipo SPACE");
            return;
        }
        StandInfo stand = stands.get(in.standEditionId());
        if (stand == null) {
            errors.add(f + ".standEditionId", "stand non trovato nell'edizione");
            return;
        }
        if (!seenStands.add(in.standEditionId())) {
            errors.add(f + ".standEditionId", "stand ripetuto nel preventivo");
            return;
        }
        if (!Objects.equals(item.pavilionId(), stand.pavilionId())) {
            errors.add(f + ".priceItemId", "la voce non e' del padiglione dello stand");
            return;
        }
        BigDecimal spaceAmount = money(stand.sqm().multiply(item.unitPrice()));
        String description = in.description() != null ? in.description() : "Spazio " + stand.standCode();
        lines.add(new PricedLine("SPACE", item.priceItemId(), stand.standEditionId(), description,
                stand.sqm(), item.unitPrice(), spaceAmount));

        if (!"LINEA".equals(stand.positionType())) {
            PriceItem sur = surcharges.get(stand.positionType());
            if (sur == null) {
                errors.add(f + ".priceItemId", "manca la maggiorazione per la posizione " + stand.positionType());
                return;
            }
            BigDecimal surAmount = money(spaceAmount.multiply(sur.pct()));
            lines.add(new PricedLine("SURCHARGE", sur.priceItemId(), stand.standEditionId(),
                    sur.name() + " " + stand.standCode(), BigDecimal.ONE.setScale(2), surAmount, surAmount));
        }
    }

    private static void addOther(QuoteLineInput in, PriceItem item, String f, List<PricedLine> lines,
                                 ValidationErrors errors) {
        if (in.standEditionId() != null) {
            errors.add(f + ".standEditionId", "ammesso solo per le voci di tipo SPACE");
            return;
        }
        BigDecimal q = in.quantity();
        if (q == null || q.signum() <= 0) {
            errors.add(f + ".quantity", "deve essere maggiore di zero");
            return;
        }
        // La colonna e' numeric(12,2): niente decimali oltre il secondo, niente valori fuori scala.
        if (q.stripTrailingZeros().scale() > 2) {
            errors.add(f + ".quantity", "al massimo due decimali");
            return;
        }
        if (q.compareTo(MAX_QUANTITY) > 0) {
            errors.add(f + ".quantity", "valore troppo grande");
            return;
        }
        if (item.maxQuantity() != null && q.compareTo(BigDecimal.valueOf(item.maxQuantity())) > 0) {
            errors.add(f + ".quantity", "oltre la quantita' massima (" + item.maxQuantity() + ")");
            return;
        }
        BigDecimal amount = money(q.multiply(item.unitPrice()));
        if (amount.compareTo(MAX_AMOUNT) > 0) {
            errors.add(f + ".quantity", "importo troppo grande");
            return;
        }
        String description = in.description() != null ? in.description() : item.name();
        lines.add(new PricedLine(item.itemType(), item.priceItemId(), null, description, q, item.unitPrice(),
                amount));
    }
}
