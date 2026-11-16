package it.arcade.backend.commercial;

import it.arcade.backend.commercial.PricingCalculator.PricedLine;
import it.arcade.backend.commercial.dto.DocumentLine;
import it.arcade.backend.commercial.dto.Quote;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

@Component
public class QuoteRepository {

    public Optional<Quote> find(JdbcClient jdbc, int quoteId) {
        return jdbc.sql("""
                        SELECT quote_id, quote_number, edition_id, exhibitor_id, status, discount_pct, list_amount,
                               net_amount, valid_until, created_at, row_version
                          FROM core.quote WHERE quote_id = :id""")
                .param("id", quoteId)
                .query((rs, n) -> new Quote(rs.getInt("quote_id"), rs.getString("quote_number"),
                        rs.getInt("edition_id"), rs.getInt("exhibitor_id"), rs.getString("status"),
                        rs.getBigDecimal("discount_pct"), rs.getBigDecimal("list_amount"),
                        rs.getBigDecimal("net_amount"), rs.getObject("valid_until", LocalDate.class),
                        rs.getObject("created_at", OffsetDateTime.class), rs.getInt("row_version"), List.of()))
                .optional()
                .map(q -> q.withLines(lines(jdbc, quoteId)));
    }

    private List<DocumentLine> lines(JdbcClient jdbc, int quoteId) {
        return jdbc.sql("""
                        SELECT l.line_no, i.item_type AS line_type, l.price_item_id, l.stand_edition_id, s.stand_code,
                               l.description, l.quantity, l.unit_price, l.amount
                          FROM core.quote_line l
                          JOIN core.price_item i ON i.price_item_id = l.price_item_id
                          LEFT JOIN core.stand_edition se ON se.stand_edition_id = l.stand_edition_id
                          LEFT JOIN core.stand s ON s.stand_id = se.stand_id
                         WHERE l.quote_id = :id ORDER BY l.line_no""")
                .param("id", quoteId)
                .query((rs, n) -> new DocumentLine(rs.getInt("line_no"), rs.getString("line_type"),
                        rs.getInt("price_item_id"), rs.getObject("stand_edition_id", Integer.class),
                        rs.getString("stand_code"), rs.getString("description"), rs.getBigDecimal("quantity"),
                        rs.getBigDecimal("unit_price"), rs.getBigDecimal("amount")))
                .list();
    }

    public int insert(JdbcClient jdbc, String number, int editionId, int exhibitorId, BigDecimal discountPct,
                      BigDecimal listAmount, BigDecimal netAmount, LocalDate validUntil, int defaultDays) {
        return jdbc.sql("""
                        INSERT INTO core.quote (quote_number, edition_id, exhibitor_id, status, discount_pct,
                                                list_amount, net_amount, valid_until)
                        VALUES (:num, :ed, :ex, 'DRAFT', :d, :l, :n,
                                COALESCE(CAST(:vu AS date), CURRENT_DATE + CAST(:days AS integer)))
                        RETURNING quote_id""")
                .param("num", number).param("ed", editionId).param("ex", exhibitorId).param("d", discountPct)
                .param("l", listAmount).param("n", netAmount).param("vu", validUntil).param("days", defaultDays)
                .query(Integer.class).single();
    }

    public void insertLine(JdbcClient jdbc, int quoteId, int lineNo, PricedLine l) {
        jdbc.sql("""
                        INSERT INTO core.quote_line (quote_id, line_no, price_item_id, stand_edition_id, description,
                                                     quantity, unit_price, amount)
                        VALUES (:q, :n, :pi, :se, :desc, :qty, :up, :amt)""")
                .param("q", quoteId).param("n", lineNo).param("pi", l.priceItemId())
                .param("se", l.standEditionId()).param("desc", l.description()).param("qty", l.quantity())
                .param("up", l.unitPrice()).param("amt", l.amount()).update();
    }
}
