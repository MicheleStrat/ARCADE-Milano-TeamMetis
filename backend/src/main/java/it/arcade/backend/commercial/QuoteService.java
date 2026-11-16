package it.arcade.backend.commercial;

import it.arcade.backend.commercial.IdempotencyService.Created;
import it.arcade.backend.commercial.IdempotencyService.Result;
import it.arcade.backend.commercial.PriceListRepository.PriceListData;
import it.arcade.backend.commercial.PricingCalculator.PricedQuote;
import it.arcade.backend.commercial.PricingCalculator.StandInfo;
import it.arcade.backend.commercial.StandReservation.LockedStand;
import it.arcade.backend.commercial.dto.Quote;
import it.arcade.backend.commercial.dto.QuoteCreate;
import it.arcade.backend.commercial.dto.QuoteLineInput;
import it.arcade.backend.db.DbRole;
import it.arcade.backend.db.ScopedDb;
import it.arcade.backend.error.ApiException;
import it.arcade.backend.error.ValidationErrors;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.TreeSet;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

@Service
public class QuoteService {

    private static final int MAX_LINES = 200;

    private final ScopedDb db;
    private final IdempotencyService idempotency;
    private final NumberGenerator numbers;
    private final PriceListRepository priceLists;
    private final QuoteRepository quotes;
    private final StandReservation stands;
    private final QuoteProperties properties;

    public QuoteService(ScopedDb db, IdempotencyService idempotency, NumberGenerator numbers,
                        PriceListRepository priceLists, QuoteRepository quotes, StandReservation stands,
                        QuoteProperties properties) {
        this.db = db;
        this.idempotency = idempotency;
        this.numbers = numbers;
        this.priceLists = priceLists;
        this.quotes = quotes;
        this.stands = stands;
        this.properties = properties;
    }

    public Result create(String principal, String key, QuoteCreate req) {
        validateShape(req);
        return idempotency.run(principal, "createQuote", key, List.of("createQuote", req),
                jdbc -> new Created(201, doCreate(jdbc, req)));
    }

    public Quote get(int quoteId, DbRole role) {
        return db.read(role, null, jdbc -> quotes.find(jdbc, quoteId))
                .orElseThrow(() -> ApiException.notFound("NOT_FOUND", "Preventivo non trovato"));
    }

    private record QuoteState(String status, int rowVersion, boolean expired) {}

    /** DRAFT -> SENT (send) e SENT -> CONFIRMED (confirm), con controllo della versione (If-Match). */
    public Quote transition(int quoteId, String ifMatch, String from, String to) {
        int expected = parseIfMatch(ifMatch);
        return db.write(jdbc -> {
            QuoteState s = jdbc.sql("""
                            SELECT status, row_version, (valid_until IS NOT NULL AND valid_until < CURRENT_DATE) AS expired
                              FROM core.quote WHERE quote_id = :id FOR UPDATE""")
                    .param("id", quoteId)
                    .query((rs, n) -> new QuoteState(rs.getString(1), rs.getInt(2), rs.getBoolean(3)))
                    .optional()
                    .orElseThrow(() -> ApiException.notFound("NOT_FOUND", "Preventivo non trovato"));
            if (s.rowVersion() != expected) {
                throw ApiException.conflict("OPTIMISTIC_LOCK_CONFLICT", "Il preventivo e' stato modificato nel frattempo");
            }
            if (!from.equals(s.status())) {
                throw ApiException.conflict("INVALID_STATE_TRANSITION",
                        "Passaggio non permesso dallo stato " + s.status());
            }
            if ("CONFIRMED".equals(to) && s.expired()) {
                throw ApiException.conflict("QUOTE_EXPIRED", "Preventivo scaduto");
            }
            jdbc.sql("UPDATE core.quote SET status = :to, row_version = row_version + 1 WHERE quote_id = :id")
                    .param("to", to).param("id", quoteId).update();
            return quotes.find(jdbc, quoteId).orElseThrow();
        });
    }

    private static int parseIfMatch(String value) {
        if (value == null || value.isBlank()) {
            throw ApiException.badRequest("VALIDATION_ERROR", "Intestazione If-Match obbligatoria (rowVersion)");
        }
        try {
            return Integer.parseInt(value.trim().replace("\"", ""));
        } catch (NumberFormatException e) {
            throw ApiException.badRequest("VALIDATION_ERROR", "If-Match deve essere un numero (rowVersion)");
        }
    }

    private void validateShape(QuoteCreate req) {
        if (req == null) {
            throw ApiException.badRequest("VALIDATION_ERROR", "Corpo della richiesta mancante");
        }
        ValidationErrors v = new ValidationErrors();
        if (req.editionId() == null) v.add("editionId", "obbligatorio");
        if (req.exhibitorId() == null) v.add("exhibitorId", "obbligatorio");
        if (req.discountPct() != null
                && (req.discountPct().signum() < 0 || req.discountPct().compareTo(BigDecimal.ONE) > 0)) {
            v.add("discountPct", "deve essere tra 0 e 1");
        }
        if (req.validUntil() != null && req.validUntil().isBefore(LocalDate.now())) {
            v.add("validUntil", "non puo' essere nel passato");
        }
        if (req.lines() == null || req.lines().isEmpty()) {
            v.add("lines", "almeno una riga");
        } else if (req.lines().size() > MAX_LINES) {
            throw new ApiException(HttpStatus.PAYLOAD_TOO_LARGE, "PAYLOAD_TOO_LARGE",
                    "Troppe righe (massimo " + MAX_LINES + ")", null);
        }
        v.throwIfAny();
    }

    private Quote doCreate(JdbcClient jdbc, QuoteCreate req) {
        ValidationErrors v = new ValidationErrors();
        Map<String, Object> edition = jdbc.sql("SELECT year, status FROM core.edition WHERE edition_id = :id")
                .param("id", req.editionId())
                .query((rs, n) -> Map.<String, Object>of("year", rs.getInt("year"), "status", rs.getString("status")))
                .optional().orElse(null);
        if (edition == null) {
            v.add("editionId", "edizione inesistente");
        } else if (!"SALES_OPEN".equals(edition.get("status"))) {
            v.add("editionId", "l'edizione non e' in vendita");
        }
        Integer exhibitors = jdbc.sql("SELECT count(*) FROM core.exhibitor WHERE exhibitor_id = :id")
                .param("id", req.exhibitorId()).query(Integer.class).single();
        if (exhibitors == 0) {
            v.add("exhibitorId", "espositore inesistente");
        }
        v.throwIfAny();

        PriceListData priceList = priceLists.load(jdbc, req.editionId()).orElse(null);
        if (priceList == null || !"PUBLISHED".equals(priceList.status())) {
            v.add("editionId", "listino non pubblicato per l'edizione");
            v.throwIfAny();
        }

        List<Integer> standIds = req.lines().stream().map(QuoteLineInput::standEditionId)
                .filter(Objects::nonNull).distinct().sorted().toList();
        Map<Integer, StandInfo> standInfo = loadStandInfo(jdbc, standIds, req.editionId());

        PricedQuote priced = PricingCalculator.calculate(req.lines(), priceList.items(), standInfo, req.discountPct());

        // Blocco degli stand in ordine di id, poi il preventivo: stesso ordine in ogni richiesta.
        List<LockedStand> locked = stands.lock(jdbc, new TreeSet<>(standInfo.keySet()));
        int year = (Integer) edition.get("year");
        String number = numbers.next(jdbc, "Q", year, "core.quote", "quote_number");
        BigDecimal discount = req.discountPct() == null ? BigDecimal.ZERO : req.discountPct();
        int quoteId = quotes.insert(jdbc, number, req.editionId(), req.exhibitorId(), discount,
                priced.listAmount(), priced.netAmount(), req.validUntil(), properties.reservationDays());
        int lineNo = 1;
        for (var line : priced.lines()) {
            quotes.insertLine(jdbc, quoteId, lineNo++, line);
        }
        stands.reserve(jdbc, locked, quoteId);
        return quotes.find(jdbc, quoteId).orElseThrow();
    }

    private Map<Integer, StandInfo> loadStandInfo(JdbcClient jdbc, List<Integer> ids, int editionId) {
        Map<Integer, StandInfo> map = new HashMap<>();
        if (ids.isEmpty()) {
            return map;
        }
        jdbc.sql("""
                        SELECT se.stand_edition_id, s.stand_code, s.pavilion_id, s.sqm, s.position_type
                          FROM core.stand_edition se JOIN core.stand s ON s.stand_id = se.stand_id
                         WHERE se.stand_edition_id IN (:ids) AND se.edition_id = :ed""")
                .param("ids", ids).param("ed", editionId)
                .query(rs -> {
                    map.put(rs.getInt("stand_edition_id"), new StandInfo(rs.getInt("stand_edition_id"),
                            rs.getString("stand_code"), rs.getInt("pavilion_id"), rs.getBigDecimal("sqm"),
                            rs.getString("position_type")));
                });
        return map;
    }
}
