package it.arcade.backend.commercial;

import it.arcade.backend.commercial.PricingCalculator.PriceItem;
import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

@Component
public class PriceListRepository {

    public record PriceListData(int priceListId, String status, BigDecimal depositPct, Integer balanceDaysBefore,
                                Map<Integer, PriceItem> items) {}

    public Optional<PriceListData> load(JdbcClient jdbc, int editionId) {
        return jdbc.sql("SELECT price_list_id, status, deposit_pct, balance_days_before "
                        + "FROM core.price_list WHERE edition_id = :e")
                .param("e", editionId)
                .query((rs, n) -> new Object[] {rs.getInt(1), rs.getString(2), rs.getBigDecimal(3),
                        rs.getObject(4, Integer.class)})
                .optional()
                .map(h -> new PriceListData((Integer) h[0], (String) h[1], (BigDecimal) h[2], (Integer) h[3],
                        items(jdbc, (Integer) h[0])));
    }

    private Map<Integer, PriceItem> items(JdbcClient jdbc, int priceListId) {
        Map<Integer, PriceItem> items = new LinkedHashMap<>();
        jdbc.sql("""
                        SELECT price_item_id, code, name, item_type, unit, unit_price, pct, pavilion_id,
                               position_type, max_quantity
                          FROM core.price_item WHERE price_list_id = :pl ORDER BY price_item_id""")
                .param("pl", priceListId)
                .query(rs -> {
                    items.put(rs.getInt("price_item_id"), new PriceItem(rs.getInt("price_item_id"),
                            rs.getString("code"), rs.getString("name"), rs.getString("item_type"),
                            rs.getString("unit"), rs.getBigDecimal("unit_price"), rs.getBigDecimal("pct"),
                            rs.getObject("pavilion_id", Integer.class), rs.getString("position_type"),
                            rs.getObject("max_quantity", Integer.class)));
                });
        return items;
    }
}
