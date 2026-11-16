package it.arcade.backend.api;

import it.arcade.backend.api.CatalogController.Edition;
import it.arcade.backend.api.CatalogController.EditionDay;
import it.arcade.backend.api.CatalogController.ExhibitorCategory;
import it.arcade.backend.api.CatalogController.ExhibitorRef;
import it.arcade.backend.api.CatalogController.Floorplan;
import it.arcade.backend.api.CatalogController.Geometry;
import it.arcade.backend.api.CatalogController.Page;
import it.arcade.backend.api.CatalogController.Pavilion;
import it.arcade.backend.api.CatalogController.PavilionPlan;
import it.arcade.backend.api.CatalogController.PriceItem;
import it.arcade.backend.api.CatalogController.PriceList;
import it.arcade.backend.api.CatalogController.StandEdition;
import it.arcade.backend.db.DbRole;
import it.arcade.backend.db.ScopedDb;
import it.arcade.backend.error.ApiException;
import it.arcade.backend.error.ValidationErrors;
import it.arcade.backend.security.Role;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.math.RoundingMode;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

@Service
public class CatalogService {

    private static final DateTimeFormatter HHMM = DateTimeFormatter.ofPattern("HH:mm");
    private static final Set<String> STAND_STATUSES = Set.of("AVAILABLE", "RESERVED", "SOLD", "FREE", "NOT_SELLABLE");
    private static final Map<String, String> STAND_SORTS = Map.of(
            "standCode", "s.stand_code", "sqm", "s.sqm", "commercialStatus", "se.commercial_status",
            "pavilionCode", "p.code", "positionType", "s.position_type");

    private final ScopedDb db;

    public CatalogService(ScopedDb db) {
        this.db = db;
    }

    public Edition getEdition(int editionId, DbRole role) {
        return db.read(role, null, jdbc -> findEdition(jdbc, editionId)
                .orElseThrow(() -> ApiException.notFound("NOT_FOUND", "Edizione non trovata")));
    }

    public List<Pavilion> pavilions(DbRole role) {
        return db.read(role, null, jdbc -> jdbc.sql(
                        "SELECT pavilion_id, code, name FROM core.pavilion ORDER BY code")
                .query((rs, n) -> new Pavilion(rs.getInt(1), rs.getString(2), rs.getString(3))).list());
    }

    public List<ExhibitorCategory> categories(DbRole role) {
        return db.read(role, null, jdbc -> jdbc.sql(
                        "SELECT category_id, name FROM core.exhibitor_category ORDER BY name")
                .query((rs, n) -> new ExhibitorCategory(rs.getInt(1), rs.getString(2))).list());
    }

    public Floorplan floorplan(int editionId, DbRole role, Set<Role> roles) {
        boolean showExhibitor = roles.contains(Role.ADMIN) || roles.contains(Role.COMMERCIAL);
        return db.read(role, null, jdbc -> {
            requireEdition(jdbc, editionId);
            Map<String, PavilionPlan> plans = new LinkedHashMap<>();
            jdbc.sql("SELECT code, name FROM core.pavilion ORDER BY code")
                    .query((rs, n) -> plans.put(rs.getString(1),
                            new PavilionPlan(rs.getString(1), rs.getString(2), new ArrayList<>())));
            for (StandEdition stand : queryStands(jdbc, editionId, null, null,
                    "s.stand_code ASC", null, null, showExhibitor)) {
                PavilionPlan plan = plans.get(stand.pavilionCode());
                if (plan != null) plan.stands().add(stand);
            }
            return new Floorplan(editionId, new ArrayList<>(plans.values()));
        });
    }

    public Page<StandEdition> stands(int editionId, DbRole role, Set<Role> roles,
                                     String pavilionCode, String status, int page, int size, String sort) {
        validatePage(page, size);
        if (status != null && !STAND_STATUSES.contains(status)) {
            throw ApiException.badRequest("VALIDATION_ERROR", "commercialStatus non valido");
        }
        String order = orderBy(sort, STAND_SORTS, "s.stand_code");
        return db.read(role, null, jdbc -> {
            requireEdition(jdbc, editionId);
            long total = jdbc.sql("""
                            SELECT count(*) FROM core.stand_edition se
                              JOIN core.stand s ON s.stand_id = se.stand_id
                              JOIN core.pavilion p ON p.pavilion_id = s.pavilion_id
                             WHERE se.edition_id = :editionId
                               AND (:pavilion IS NULL OR p.code = :pavilion)
                               AND (:status IS NULL OR se.commercial_status = :status)
                            """)
                    .param("editionId", editionId).param("pavilion", pavilionCode).param("status", status)
                    .query(Long.class).single();
            List<StandEdition> content = queryStands(jdbc, editionId, pavilionCode, status, order,
                    page, size, roles.contains(Role.ADMIN) || roles.contains(Role.COMMERCIAL));
            return page(page, size, total, content);
        });
    }

    public PriceList priceList(int editionId, DbRole role) {
        return db.read(role, null, jdbc -> {
            requireEdition(jdbc, editionId);
            PriceList header = jdbc.sql("""
                            SELECT price_list_id, edition_id, origin, status, deposit_pct,
                                   balance_days_before, preemption_deadline
                              FROM core.price_list WHERE edition_id = :editionId
                            """)
                    .param("editionId", editionId)
                    .query((rs, n) -> new PriceList(rs.getInt("price_list_id"), rs.getInt("edition_id"),
                            rs.getString("origin"), rs.getString("status"), rs.getBigDecimal("deposit_pct"),
                            rs.getObject("balance_days_before", Integer.class),
                            rs.getObject("preemption_deadline", LocalDate.class), List.of()))
                    .optional().orElseThrow(() -> ApiException.notFound("NOT_FOUND", "Listino non trovato"));
            List<PriceItem> items = priceItems(jdbc, header.priceListId());
            return new PriceList(header.priceListId(), header.editionId(), header.origin(), header.status(),
                    header.depositPct(), header.balanceDaysBefore(), header.preemptionDeadline(), items);
        });
    }

    public PriceItem updatePriceItem(int priceItemId, CatalogController.PriceItemUpdate input) {
        if (priceItemId < 1) throw ApiException.badRequest("VALIDATION_ERROR", "priceItemId deve essere positivo");
        ValidationErrors errors = new ValidationErrors();
        if (input == null) {
            errors.add("body", "obbligatorio");
            errors.throwIfAny();
        }
        if (input.unitPrice() == null && input.pct() == null && input.maxQuantity() == null) {
            errors.add("body", "indicare almeno un campo da aggiornare");
        }
        if (input.unitPrice() != null && input.unitPrice().signum() < 0) errors.add("unitPrice", "non puo' essere negativo");
        if (input.pct() != null && (input.pct().signum() < 0 || input.pct().compareTo(BigDecimal.ONE) > 0)) {
            errors.add("pct", "deve essere compreso tra 0 e 1");
        }
        if (input.pct() != null && input.pct().stripTrailingZeros().scale() > 4) errors.add("pct", "massimo quattro decimali");
        if (input.maxQuantity() != null && (input.maxQuantity() < 1 || input.maxQuantity() > 32767)) {
            errors.add("maxQuantity", "deve essere compreso tra 1 e 32767");
        }
        errors.throwIfAny();

        return db.write(jdbc -> {
            var item = jdbc.sql("""
                            SELECT i.price_list_id, i.unit, i.unit_price, i.pct, i.max_quantity,
                                   pl.edition_id
                              FROM core.price_item i JOIN core.price_list pl ON pl.price_list_id = i.price_list_id
                             WHERE i.price_item_id = :id FOR UPDATE OF i
                            """)
                    .param("id", priceItemId)
                    .query((rs, n) -> new Object[] {rs.getInt("price_list_id"), rs.getString("unit"),
                            rs.getBigDecimal("unit_price"), rs.getBigDecimal("pct"),
                            rs.getObject("max_quantity", Integer.class), rs.getInt("edition_id")})
                    .optional().orElseThrow(() -> ApiException.notFound("NOT_FOUND", "Voce di listino non trovata"));
            String unit = (String) item[1];
            if (input.unitPrice() != null && "PCT_OF_SPACE".equals(unit)) {
                throw ApiException.validation(List.of(new it.arcade.backend.error.FieldError(
                        "unitPrice", "la voce usa una percentuale; aggiornare pct")));
            }
            if (input.pct() != null && !"PCT_OF_SPACE".equals(unit)) {
                throw ApiException.validation(List.of(new it.arcade.backend.error.FieldError(
                        "pct", "la voce non e' percentuale; aggiornare unitPrice")));
            }
            boolean signedContracts = jdbc.sql("""
                            SELECT EXISTS (
                                SELECT 1 FROM core.contract c WHERE c.edition_id = :editionId AND c.status = 'SIGNED')
                            """)
                    .param("editionId", item[5]).query(Boolean.class).single();
            if (signedContracts) {
                throw ApiException.conflict("PRICE_LIST_IN_USE", "Il listino e' gia' utilizzato da contratti firmati");
            }
            BigDecimal unitPrice = input.unitPrice() == null ? (BigDecimal) item[2]
                    : input.unitPrice().setScale(2, RoundingMode.HALF_UP);
            BigDecimal pct = input.pct() == null ? (BigDecimal) item[3] : input.pct();
            Integer maxQuantity = input.maxQuantity() == null ? (Integer) item[4] : input.maxQuantity();
            jdbc.sql("""
                            UPDATE core.price_item SET unit_price = :unitPrice, pct = :pct, max_quantity = :maxQuantity
                             WHERE price_item_id = :id
                            """)
                    .param("unitPrice", unitPrice).param("pct", pct).param("maxQuantity", maxQuantity)
                    .param("id", priceItemId).update();
            List<String> changedFields = new ArrayList<>();
            if (input.unitPrice() != null) changedFields.add("unitPrice");
            if (input.pct() != null) changedFields.add("pct");
            if (input.maxQuantity() != null) changedFields.add("maxQuantity");
            String changed = String.join(",", changedFields);
            jdbc.sql("""
                            INSERT INTO core.audit_log (action, entity, entity_id, detail)
                            VALUES ('PRICE_ITEM_UPDATED', 'price_item', :id, CAST(:detail AS jsonb))
                            """)
                    .param("id", String.valueOf(priceItemId))
                    .param("detail", "{\"fields\":\"" + changed + "\"}").update();
            return priceItems(jdbc, (Integer) item[0]).stream()
                    .filter(updated -> updated.priceItemId() == priceItemId).findFirst().orElseThrow();
        });
    }

    private java.util.Optional<Edition> findEdition(JdbcClient jdbc, int editionId) {
        var edition = jdbc.sql("""
                        SELECT edition_id, year, name, status, timezone FROM core.edition WHERE edition_id = :id
                        """)
                .param("id", editionId)
                .query((rs, n) -> new Edition(rs.getInt("edition_id"), rs.getInt("year"), rs.getString("name"),
                        rs.getString("status"), rs.getString("timezone"), new ArrayList<>()))
                .optional();
        edition.ifPresent(value -> jdbc.sql("""
                        SELECT day_date, day_number, opens_at, closes_at FROM core.edition_day
                         WHERE edition_id = :id ORDER BY day_date
                        """)
                .param("id", editionId)
                .query((rs, n) -> value.days().add(new EditionDay(rs.getObject("day_date", LocalDate.class),
                        rs.getInt("day_number"), rs.getObject("opens_at", LocalTime.class).format(HHMM),
                        rs.getObject("closes_at", LocalTime.class).format(HHMM)))));
        return edition;
    }

    private static void requireEdition(JdbcClient jdbc, int editionId) {
        boolean exists = jdbc.sql("SELECT EXISTS (SELECT 1 FROM core.edition WHERE edition_id = :id)")
                .param("id", editionId).query(Boolean.class).single();
        if (!exists) throw ApiException.notFound("NOT_FOUND", "Edizione non trovata");
    }

    private static List<StandEdition> queryStands(JdbcClient jdbc, int editionId, String pavilion,
                                                   String status, String orderBy, Integer page, Integer size,
                                                   boolean showExhibitor) {
        String pagination = page == null ? "" : " LIMIT :limit OFFSET :offset";
        var query = jdbc.sql("""
                        SELECT se.stand_edition_id, s.stand_id, s.stand_code, p.code AS pavilion_code,
                               s.sqm, s.position_type, se.commercial_status, se.reserved_until, se.row_version,
                               s.floor_x, s.floor_y, s.floor_w, s.floor_h,
                               CASE WHEN space.unit_price IS NULL THEN NULL ELSE
                                   round(s.sqm * space.unit_price * (1 + coalesce(surcharge.pct, 0)), 2)
                               END AS list_price,
                               ex.exhibitor_id, ex.legal_name
                          FROM core.stand_edition se
                          JOIN core.stand s ON s.stand_id = se.stand_id
                          JOIN core.pavilion p ON p.pavilion_id = s.pavilion_id
                          LEFT JOIN core.price_list pl ON pl.edition_id = se.edition_id
                          LEFT JOIN core.price_item space ON space.price_list_id = pl.price_list_id
                               AND space.item_type = 'SPACE' AND space.pavilion_id = s.pavilion_id
                          LEFT JOIN core.price_item surcharge ON surcharge.price_list_id = pl.price_list_id
                               AND surcharge.item_type = 'SURCHARGE' AND surcharge.position_type = s.position_type
                          LEFT JOIN LATERAL (
                               SELECT e.exhibitor_id, e.legal_name
                                 FROM core.contract_stand cs
                                 JOIN core.contract c ON c.contract_id = cs.contract_id AND c.status = 'SIGNED'
                                 JOIN core.exhibitor e ON e.exhibitor_id = c.exhibitor_id
                                WHERE cs.stand_edition_id = se.stand_edition_id AND cs.released_at IS NULL
                                ORDER BY cs.assigned_at DESC LIMIT 1
                          ) ex ON :showExhibitor
                         WHERE se.edition_id = :editionId
                           AND (:pavilion IS NULL OR p.code = :pavilion)
                           AND (:status IS NULL OR se.commercial_status = :status)
                        """ + " ORDER BY " + orderBy + pagination)
                .param("editionId", editionId).param("pavilion", pavilion).param("status", status)
                .param("showExhibitor", showExhibitor);
        if (page != null) query.param("limit", size).param("offset", (long) page * size);
        return query.query((rs, n) -> {
            BigDecimal x = rs.getBigDecimal("floor_x");
            BigDecimal y = rs.getBigDecimal("floor_y");
            BigDecimal width = rs.getBigDecimal("floor_w");
            BigDecimal height = rs.getBigDecimal("floor_h");
            Geometry geometry = x == null && y == null && width == null && height == null
                    ? null : new Geometry(x, y, width, height);
            Integer exhibitorId = rs.getObject("exhibitor_id", Integer.class);
            ExhibitorRef exhibitor = exhibitorId == null ? null
                    : new ExhibitorRef(exhibitorId, rs.getString("legal_name"));
            return new StandEdition(rs.getInt("stand_edition_id"), rs.getInt("stand_id"),
                    rs.getString("stand_code"), rs.getString("pavilion_code"), rs.getBigDecimal("sqm"),
                    rs.getString("position_type"), rs.getString("commercial_status"),
                    rs.getObject("reserved_until", OffsetDateTime.class), rs.getBigDecimal("list_price"),
                    geometry, exhibitor, rs.getInt("row_version"));
        }).list();
    }

    private static List<PriceItem> priceItems(JdbcClient jdbc, int priceListId) {
        return jdbc.sql("""
                        SELECT i.price_item_id, i.code, i.name, i.item_type, i.unit, i.unit_price, i.pct,
                               p.code AS pavilion_code, i.position_type, i.max_quantity
                          FROM core.price_item i LEFT JOIN core.pavilion p ON p.pavilion_id = i.pavilion_id
                         WHERE i.price_list_id = :priceListId ORDER BY i.price_item_id
                        """)
                .param("priceListId", priceListId)
                .query((rs, n) -> new PriceItem(rs.getInt("price_item_id"), rs.getString("code"),
                        rs.getString("name"), rs.getString("item_type"), rs.getString("unit"),
                        rs.getBigDecimal("unit_price"), rs.getBigDecimal("pct"), rs.getString("pavilion_code"),
                        rs.getString("position_type"), rs.getObject("max_quantity", Integer.class))).list();
    }

    private static void validatePage(int page, int size) {
        ValidationErrors errors = new ValidationErrors();
        if (page < 0) errors.add("page", "deve essere maggiore o uguale a zero");
        if (size < 1 || size > 200) errors.add("size", "deve essere compreso tra 1 e 200");
        errors.throwIfAny();
    }

    private static String orderBy(String sort, Map<String, String> allowed, String fallback) {
        if (sort == null || sort.isBlank()) return fallback + " ASC";
        String[] pieces = sort.split(",", -1);
        String column = pieces[0].trim();
        String direction = pieces.length == 2 ? pieces[1].trim().toLowerCase() : "asc";
        String sqlColumn = allowed.get(column);
        if (pieces.length > 2 || sqlColumn == null || !(direction.equals("asc") || direction.equals("desc"))) {
            throw ApiException.badRequest("VALIDATION_ERROR", "sort deve indicare un campo consentito e asc/desc");
        }
        return sqlColumn + " " + direction.toUpperCase() + ", se.stand_edition_id ASC";
    }

    private static <T> Page<T> page(int page, int size, long total, List<T> content) {
        int totalPages = total == 0 ? 0 : (int) ((total + size - 1) / size);
        return new Page<>(page, size, total, totalPages, content);
    }
}
