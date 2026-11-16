package it.arcade.backend.commercial;

import it.arcade.backend.commercial.dto.Contract;
import it.arcade.backend.commercial.dto.ContractStandRef;
import it.arcade.backend.commercial.dto.DocumentLine;
import it.arcade.backend.commercial.dto.Payment;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

@Component
public class ContractRepository {

    public Optional<Contract> find(JdbcClient jdbc, int contractId) {
        return jdbc.sql("""
                        SELECT contract_id, contract_number, edition_id, exhibitor_id, quote_id, status, signed_on,
                               list_amount, discount_pct, net_amount, is_renewal, row_version
                          FROM core.contract WHERE contract_id = :id""")
                .param("id", contractId)
                .query((rs, n) -> new Contract(rs.getInt("contract_id"), rs.getString("contract_number"),
                        rs.getInt("edition_id"), rs.getInt("exhibitor_id"), rs.getObject("quote_id", Integer.class),
                        rs.getString("status"), rs.getObject("signed_on", LocalDate.class),
                        rs.getBigDecimal("list_amount"), rs.getBigDecimal("discount_pct"),
                        rs.getBigDecimal("net_amount"), rs.getBoolean("is_renewal"), rs.getInt("row_version"),
                        stands(jdbc, contractId), lines(jdbc, contractId), payments(jdbc, contractId)))
                .optional();
    }

    private List<ContractStandRef> stands(JdbcClient jdbc, int contractId) {
        return jdbc.sql("""
                        SELECT cs.stand_edition_id, s.stand_code, s.sqm
                          FROM core.contract_stand cs
                          JOIN core.stand_edition se ON se.stand_edition_id = cs.stand_edition_id
                          JOIN core.stand s ON s.stand_id = se.stand_id
                         WHERE cs.contract_id = :id AND cs.released_at IS NULL ORDER BY s.stand_code""")
                .param("id", contractId)
                .query((rs, n) -> new ContractStandRef(rs.getInt(1), rs.getString(2), rs.getBigDecimal(3)))
                .list();
    }

    private List<DocumentLine> lines(JdbcClient jdbc, int contractId) {
        return jdbc.sql("""
                        SELECT l.line_no, l.line_type, l.price_item_id, cs.stand_edition_id, s.stand_code,
                               l.description, l.quantity, l.unit_price, l.amount
                          FROM core.contract_line l
                          LEFT JOIN core.contract_stand cs ON cs.contract_stand_id = l.contract_stand_id
                          LEFT JOIN core.stand_edition se ON se.stand_edition_id = cs.stand_edition_id
                          LEFT JOIN core.stand s ON s.stand_id = se.stand_id
                         WHERE l.contract_id = :id ORDER BY l.line_no""")
                .param("id", contractId)
                .query((rs, n) -> new DocumentLine(rs.getInt("line_no"), rs.getString("line_type"),
                        rs.getInt("price_item_id"), rs.getObject("stand_edition_id", Integer.class),
                        rs.getString("stand_code"), rs.getString("description"), rs.getBigDecimal("quantity"),
                        rs.getBigDecimal("unit_price"), rs.getBigDecimal("amount")))
                .list();
    }

    private List<Payment> payments(JdbcClient jdbc, int contractId) {
        return jdbc.sql("""
                        SELECT payment_id, contract_id, kind, due_on, due_amount, due_amount_basis, paid_on,
                               paid_amount, paid_amount_is_assumed
                          FROM core.payment WHERE contract_id = :id ORDER BY due_on, payment_id""")
                .param("id", contractId)
                .query((rs, n) -> {
                    LocalDate dueOn = rs.getObject("due_on", LocalDate.class);
                    LocalDate paidOn = rs.getObject("paid_on", LocalDate.class);
                    String state = paidOn != null ? (paidOn.isAfter(dueOn) ? "PAID_LATE" : "PAID")
                            : (LocalDate.now().isAfter(dueOn) ? "OVERDUE" : "DUE");
                    return new Payment(rs.getInt("payment_id"), rs.getInt("contract_id"), rs.getString("kind"),
                            dueOn, rs.getBigDecimal("due_amount"), rs.getString("due_amount_basis"), paidOn,
                            rs.getBigDecimal("paid_amount"), rs.getBoolean("paid_amount_is_assumed"), state);
                })
                .list();
    }
}
