package it.arcade.backend.commercial;

import it.arcade.backend.commercial.IdempotencyService.Created;
import it.arcade.backend.commercial.IdempotencyService.Result;
import it.arcade.backend.commercial.StandReservation.LockedStand;
import it.arcade.backend.commercial.dto.Contract;
import it.arcade.backend.commercial.dto.ContractFromQuote;
import it.arcade.backend.db.DbRole;
import it.arcade.backend.db.ScopedDb;
import it.arcade.backend.error.ApiException;
import it.arcade.backend.error.ValidationErrors;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

@Service
public class ContractService {

    private record QuoteHead(int editionId, int exhibitorId, String status, BigDecimal discountPct,
                             BigDecimal listAmount, BigDecimal netAmount, boolean expired) {}

    private record QuoteLineRow(int lineNo, String lineType, int priceItemId, String itemCode,
                                Integer standEditionId, String description, BigDecimal quantity,
                                BigDecimal unitPrice, BigDecimal amount) {}

    private final ScopedDb db;
    private final IdempotencyService idempotency;
    private final NumberGenerator numbers;
    private final StandReservation stands;
    private final ContractRepository contracts;
    private final ContractProperties properties;

    public ContractService(ScopedDb db, IdempotencyService idempotency, NumberGenerator numbers,
                           StandReservation stands, ContractRepository contracts, ContractProperties properties) {
        this.db = db;
        this.idempotency = idempotency;
        this.numbers = numbers;
        this.stands = stands;
        this.contracts = contracts;
        this.properties = properties;
    }

    public Contract get(int contractId, DbRole role) {
        return db.read(role, null, jdbc -> contracts.find(jdbc, contractId))
                .orElseThrow(() -> ApiException.notFound("NOT_FOUND", "Contratto non trovato"));
    }

    public Result convert(String principal, String key, int quoteId, ContractFromQuote req) {
        ValidationErrors v = new ValidationErrors();
        if (req == null || req.signedOn() == null) {
            v.add("signedOn", "obbligatorio");
        }
        v.throwIfAny();
        return idempotency.run(principal, "convertQuoteToContract", key, List.of("convertQuote", quoteId, req),
                jdbc -> new Created(201, doConvert(jdbc, quoteId, req)));
    }

    private Contract doConvert(JdbcClient jdbc, int quoteId, ContractFromQuote req) {
        QuoteHead q = jdbc.sql("""
                        SELECT edition_id, exhibitor_id, status, discount_pct, list_amount, net_amount,
                               (valid_until IS NOT NULL AND valid_until < CURRENT_DATE) AS expired
                          FROM core.quote WHERE quote_id = :id FOR UPDATE""")
                .param("id", quoteId)
                .query((rs, n) -> new QuoteHead(rs.getInt(1), rs.getInt(2), rs.getString(3), rs.getBigDecimal(4),
                        rs.getBigDecimal(5), rs.getBigDecimal(6), rs.getBoolean(7)))
                .optional()
                .orElseThrow(() -> ApiException.notFound("NOT_FOUND", "Preventivo non trovato"));
        if (!"CONFIRMED".equals(q.status())) {
            throw ApiException.conflict("QUOTE_NOT_CONFIRMED", "Il preventivo non e' confermato");
        }
        if (q.expired()) {
            throw ApiException.conflict("QUOTE_EXPIRED", "Preventivo scaduto");
        }

        List<Integer> standIds = jdbc.sql("""
                        SELECT DISTINCT stand_edition_id FROM core.quote_line
                         WHERE quote_id = :id AND stand_edition_id IS NOT NULL ORDER BY 1""")
                .param("id", quoteId).query(Integer.class).list();
        List<LockedStand> locked = stands.lock(jdbc, standIds);
        stands.assertOwnedBy(locked, quoteId);

        // Piano di pagamento: tutte le condizioni si controllano PRIMA di scrivere qualsiasi cosa.
        Object[] cond = jdbc.sql("SELECT deposit_pct, balance_days_before FROM core.price_list WHERE edition_id = :e")
                .param("e", q.editionId())
                .query((rs, n) -> new Object[] {rs.getBigDecimal(1), rs.getObject(2, Integer.class)})
                .optional().orElse(null);
        if (cond == null || cond[0] == null || cond[1] == null) {
            throw ApiException.unprocessable("PRICE_LIST_CONDITIONS_MISSING",
                    "Il listino non indica la percentuale d'acconto o i giorni del saldo");
        }
        LocalDate firstDay = jdbc.sql("SELECT min(day_date) FROM core.edition_day WHERE edition_id = :e")
                .param("e", q.editionId()).query(LocalDate.class).optional().orElse(null);
        if (firstDay == null) {
            throw ApiException.unprocessable("EDITION_DATES_MISSING",
                    "L'edizione non ha giorni di apertura: la scadenza del saldo non si puo' calcolare");
        }
        LocalDate balanceDue = firstDay.minusDays((Integer) cond[1]);
        LocalDate depositDue = req.signedOn().plusDays(properties.depositDueDays());
        if (depositDue.isAfter(balanceDue)) {
            depositDue = balanceDue; // l'acconto non scade dopo il saldo
        }
        BigDecimal deposit = q.netAmount().multiply((BigDecimal) cond[0]).setScale(2, RoundingMode.HALF_UP);
        BigDecimal balance = q.netAmount().subtract(deposit);

        int year = jdbc.sql("SELECT year FROM core.edition WHERE edition_id = :e").param("e", q.editionId())
                .query(Integer.class).single();
        String number = numbers.next(jdbc, "C", year, "core.contract", "contract_number");
        boolean renewal = Boolean.TRUE.equals(req.isRenewal());
        int contractId = jdbc.sql("""
                        INSERT INTO core.contract (contract_number, edition_id, exhibitor_id, quote_id, status, signed_on,
                                                   list_amount, discount_pct, net_amount, is_renewal)
                        VALUES (:num, :ed, :ex, :q, 'SIGNED', :signed, :l, :d, :n, :ren) RETURNING contract_id""")
                .param("num", number).param("ed", q.editionId()).param("ex", q.exhibitorId()).param("q", quoteId)
                .param("signed", req.signedOn()).param("l", q.listAmount()).param("d", q.discountPct())
                .param("n", q.netAmount()).param("ren", renewal).query(Integer.class).single();

        Map<Integer, Integer> contractStandByStandEdition = new HashMap<>();
        for (int standEditionId : standIds) {
            try {
                int csId = jdbc.sql("""
                                INSERT INTO core.contract_stand (contract_id, stand_edition_id, edition_id)
                                VALUES (:c, :se, :ed) RETURNING contract_stand_id""")
                        .param("c", contractId).param("se", standEditionId).param("ed", q.editionId())
                        .query(Integer.class).single();
                contractStandByStandEdition.put(standEditionId, csId);
            } catch (DuplicateKeyException e) {
                // Ultima difesa: l'indice univoco impedisce due contratti attivi sullo stesso stand.
                throw ApiException.conflict("STAND_ALREADY_SOLD", "Stand gia' assegnato a un contratto");
            }
        }

        List<QuoteLineRow> lines = jdbc.sql("""
                        SELECT l.line_no, i.item_type, l.price_item_id, i.code, l.stand_edition_id, l.description,
                               l.quantity, l.unit_price, l.amount
                          FROM core.quote_line l JOIN core.price_item i ON i.price_item_id = l.price_item_id
                         WHERE l.quote_id = :id ORDER BY l.line_no""")
                .param("id", quoteId)
                .query((rs, n) -> new QuoteLineRow(rs.getInt(1), rs.getString(2), rs.getInt(3), rs.getString(4),
                        rs.getObject(5, Integer.class), rs.getString(6), rs.getBigDecimal(7), rs.getBigDecimal(8),
                        rs.getBigDecimal(9)))
                .list();
        for (QuoteLineRow l : lines) {
            Integer csId = l.standEditionId() == null ? null : contractStandByStandEdition.get(l.standEditionId());
            jdbc.sql("""
                            INSERT INTO core.contract_line (contract_id, line_no, line_type, price_item_id,
                                   source_item_code, description, quantity, unit_price, amount, contract_stand_id)
                            VALUES (:c, :n, :t, :pi, :code, :desc, :qty, :up, :amt, :cs)""")
                    .param("c", contractId).param("n", l.lineNo()).param("t", l.lineType())
                    .param("pi", l.priceItemId()).param("code", l.itemCode()).param("desc", l.description())
                    .param("qty", l.quantity()).param("up", l.unitPrice()).param("amt", l.amount())
                    .param("cs", csId).update();
        }
        jdbc.sql("""
                        INSERT INTO core.sponsorship (contract_line_id)
                        SELECT contract_line_id FROM core.contract_line
                         WHERE contract_id = :c AND line_type = 'SPONSORSHIP'""")
                .param("c", contractId).update();

        insertPayment(jdbc, contractId, "DEPOSIT", depositDue, deposit);
        insertPayment(jdbc, contractId, "BALANCE", balanceDue, balance);

        if (!standIds.isEmpty()) {
            jdbc.sql("""
                            UPDATE core.stand_edition
                               SET commercial_status = 'SOLD', reserved_until = NULL, reserved_by_quote_id = NULL,
                                   row_version = row_version + 1
                             WHERE stand_edition_id IN (:ids)""")
                    .param("ids", standIds).update();
        }
        jdbc.sql("UPDATE core.quote SET status = 'CONVERTED', row_version = row_version + 1 WHERE quote_id = :id")
                .param("id", quoteId).update();
        return contracts.find(jdbc, contractId).orElseThrow();
    }

    private void insertPayment(JdbcClient jdbc, int contractId, String kind, LocalDate dueOn, BigDecimal amount) {
        jdbc.sql("""
                        INSERT INTO core.payment (contract_id, kind, due_on, due_amount, due_amount_basis)
                        VALUES (:c, :k, :d, :a, 'RULE_DERIVED')""")
                .param("c", contractId).param("k", kind).param("d", dueOn).param("a", amount).update();
    }
}
