package it.arcade.backend.support;

import java.math.BigDecimal;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.jdbc.core.JdbcTemplate;

/** Aiuti per i test: lavorano come superutente sul database di prova. */
public final class Fixtures {

    private static final AtomicInteger SEQ = new AtomicInteger();

    private Fixtures() {}

    public static JdbcTemplate owner() {
        return PostgresSupport.owner();
    }

    public static int edition(int year) {
        return owner().queryForObject("SELECT edition_id FROM core.edition WHERE year = ?", Integer.class, year);
    }

    public static int priceItem(int year, String code) {
        return owner().queryForObject("""
                SELECT pi.price_item_id FROM core.price_item pi
                  JOIN core.price_list pl ON pl.price_list_id = pi.price_list_id
                  JOIN core.edition e ON e.edition_id = pl.edition_id
                 WHERE e.year = ? AND pi.code = ?""", Integer.class, year, code);
    }

    /** Crea uno stand nuovo e la sua occupazione nell'edizione (AVAILABLE). Restituisce stand_edition_id. */
    public static int newStand(int year, String pavilionCode, String sqm, String position) {
        int n = SEQ.getAndIncrement();
        String code = String.format("%s-%c%02d", pavilionCode, (char) ('A' + (n / 100) % 26), n % 100);
        owner().update("""
                INSERT INTO core.stand (stand_code, pavilion_id, sqm, position_type, first_edition_id)
                VALUES (?, (SELECT pavilion_id FROM core.pavilion WHERE code = ?), ?, ?,
                        (SELECT min(edition_id) FROM core.edition))""",
                code, pavilionCode, new BigDecimal(sqm), position);
        return owner().queryForObject("""
                INSERT INTO core.stand_edition (stand_id, edition_id)
                SELECT s.stand_id, ? FROM core.stand s WHERE s.stand_code = ?
                RETURNING stand_edition_id""", Integer.class, edition(year), code);
    }
}
