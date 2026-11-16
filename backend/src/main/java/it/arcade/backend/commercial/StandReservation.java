package it.arcade.backend.commercial;

import it.arcade.backend.error.ApiException;
import java.util.Collection;
import java.util.List;
import java.util.Objects;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/** Blocco e cambio di stato degli stand. Gli stand si bloccano SEMPRE in ordine di id: niente stalli. */
@Component
public class StandReservation {

    public record LockedStand(int standEditionId, String commercialStatus, boolean reservationActive,
                              Integer reservedByQuoteId) {}

    private final QuoteProperties properties;

    public StandReservation(QuoteProperties properties) {
        this.properties = properties;
    }

    public List<LockedStand> lock(JdbcClient jdbc, Collection<Integer> ids) {
        if (ids.isEmpty()) {
            return List.of();
        }
        return jdbc.sql("""
                        SELECT stand_edition_id, commercial_status,
                               (reserved_until IS NOT NULL AND reserved_until > now()) AS reservation_active,
                               reserved_by_quote_id
                          FROM core.stand_edition WHERE stand_edition_id IN (:ids)
                         ORDER BY stand_edition_id FOR UPDATE""")
                .param("ids", ids)
                .query((rs, n) -> new LockedStand(rs.getInt("stand_edition_id"), rs.getString("commercial_status"),
                        rs.getBoolean("reservation_active"), rs.getObject("reserved_by_quote_id", Integer.class)))
                .list();
    }

    /** Riserva gli stand per il preventivo: SOLD/RESERVED attiva -> 409, FREE/NOT_SELLABLE -> 422. */
    public void reserve(JdbcClient jdbc, List<LockedStand> stands, int quoteId) {
        for (LockedStand s : stands) {
            switch (s.commercialStatus()) {
                case "SOLD" -> throw ApiException.conflict("STAND_ALREADY_SOLD", "Stand gia' assegnato a un contratto");
                case "FREE", "NOT_SELLABLE" ->
                        throw ApiException.unprocessable("STAND_NOT_SELLABLE", "Stand non commercializzabile");
                case "RESERVED" -> {
                    if (s.reservationActive()) {
                        throw ApiException.conflict("STAND_ALREADY_RESERVED", "Stand riservato da un altro preventivo");
                    }
                }
                default -> { }
            }
        }
        for (LockedStand s : stands) {
            jdbc.sql("""
                            UPDATE core.stand_edition
                               SET commercial_status = 'RESERVED',
                                   reserved_until = now() + make_interval(days => :days),
                                   reserved_by_quote_id = :q,
                                   row_version = row_version + 1
                             WHERE stand_edition_id = :id""")
                    .param("days", properties.reservationDays()).param("q", quoteId)
                    .param("id", s.standEditionId()).update();
        }
    }

    /** In conversione ogni stand deve essere ancora riservato da QUESTO preventivo. */
    public void assertOwnedBy(List<LockedStand> stands, int quoteId) {
        for (LockedStand s : stands) {
            if ("SOLD".equals(s.commercialStatus())) {
                throw ApiException.conflict("STAND_ALREADY_SOLD", "Stand gia' assegnato a un contratto");
            }
            if (!"RESERVED".equals(s.commercialStatus()) || !Objects.equals(s.reservedByQuoteId(), quoteId)) {
                if ("RESERVED".equals(s.commercialStatus())) {
                    throw ApiException.conflict("STAND_ALREADY_RESERVED", "Stand riservato da un altro preventivo");
                }
                throw ApiException.conflict("INVALID_STATE_TRANSITION", "La riserva dello stand non e' piu' valida");
            }
        }
    }
}
