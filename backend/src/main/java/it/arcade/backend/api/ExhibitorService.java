package it.arcade.backend.api;

import it.arcade.backend.api.ExhibitorController.ContactRef;
import it.arcade.backend.api.ExhibitorController.Exhibitor;
import it.arcade.backend.api.ExhibitorController.ExhibitorInput;
import it.arcade.backend.api.ExhibitorController.Page;
import it.arcade.backend.db.DbRole;
import it.arcade.backend.db.ScopedDb;
import it.arcade.backend.error.ApiException;
import it.arcade.backend.error.ValidationErrors;
import java.text.Normalizer;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

@Service
public class ExhibitorService {

    private static final Map<String, String> SORTS = Map.of(
            "legalName", "e.legal_name", "exhibitorCode", "e.exhibitor_code", "city", "e.city",
            "categoryName", "cat.name");
    private final ScopedDb db;

    public ExhibitorService(ScopedDb db) {
        this.db = db;
    }

    public Page list(String q, Integer categoryId, Integer editionId, int page, int size, String sort,
                     boolean includeContact) {
        validatePage(page, size);
        if (categoryId != null && categoryId < 1) {
            throw ApiException.badRequest("VALIDATION_ERROR", "categoryId deve essere positivo");
        }
        if (editionId != null && editionId < 1) {
            throw ApiException.badRequest("VALIDATION_ERROR", "editionId deve essere positivo");
        }
        String order = orderBy(sort);
        String search = q == null || q.isBlank() ? null : q.trim();
        return db.read(DbRole.STAFF, null, jdbc -> {
            long total = jdbc.sql("""
                            SELECT count(*) FROM core.exhibitor e
                              JOIN core.exhibitor_category cat ON cat.category_id = e.category_id
                             WHERE (CAST(:q AS text) IS NULL OR e.legal_name ILIKE '%' || :q || '%'
                                    OR e.exhibitor_code ILIKE '%' || :q || '%')
                               AND (:categoryId IS NULL OR e.category_id = :categoryId)
                               AND (:editionId IS NULL OR EXISTS (
                                   SELECT 1 FROM core.contract c WHERE c.exhibitor_id = e.exhibitor_id
                                     AND c.edition_id = :editionId AND c.status = 'SIGNED'))
                            """)
                    .param("q", search).param("categoryId", categoryId).param("editionId", editionId)
                    .query(Long.class).single();
            List<Exhibitor> content = jdbc.sql("""
                            SELECT e.exhibitor_id, e.exhibitor_code, e.legal_name, e.vat_number,
                                   e.category_id, cat.name AS category_name, e.city,
                                   contact.full_name, contact.email
                              FROM core.exhibitor e
                              JOIN core.exhibitor_category cat ON cat.category_id = e.category_id
                              LEFT JOIN LATERAL (
                                  SELECT full_name, email FROM core.exhibitor_contact
                                   WHERE exhibitor_id = e.exhibitor_id AND is_primary
                                   ORDER BY contact_id LIMIT 1
                              ) contact ON :includeContact
                             WHERE (CAST(:q AS text) IS NULL OR e.legal_name ILIKE '%' || :q || '%'
                                    OR e.exhibitor_code ILIKE '%' || :q || '%')
                               AND (:categoryId IS NULL OR e.category_id = :categoryId)
                               AND (:editionId IS NULL OR EXISTS (
                                   SELECT 1 FROM core.contract c WHERE c.exhibitor_id = e.exhibitor_id
                                     AND c.edition_id = :editionId AND c.status = 'SIGNED'))
                             ORDER BY """ + order + " LIMIT :limit OFFSET :offset")
                    .param("q", search).param("categoryId", categoryId).param("editionId", editionId)
                    .param("includeContact", includeContact)
                    .param("limit", size).param("offset", (long) page * size)
                    .query(ExhibitorService::map).list();
            return new Page(page, size, total, total == 0 ? 0 : (int) ((total + size - 1) / size), content);
        });
    }

    public Exhibitor get(int exhibitorId, boolean includeContact) {
        if (exhibitorId < 1) throw ApiException.badRequest("VALIDATION_ERROR", "exhibitorId deve essere positivo");
        return db.read(DbRole.STAFF, null, jdbc -> find(jdbc, exhibitorId, includeContact)
                .orElseThrow(() -> ApiException.notFound("NOT_FOUND", "Espositore non trovato")));
    }

    public Exhibitor create(ExhibitorInput input) {
        Validated value = validate(input);
        try {
            return db.write(jdbc -> {
                requireCategory(jdbc, value.categoryId());
                jdbc.sql("SELECT 1 FROM (SELECT pg_advisory_xact_lock(hashtext('core.exhibitor:code'))) locked")
                        .query(Integer.class).single();
                int next = jdbc.sql("""
                                SELECT coalesce(max(substring(exhibitor_code from 4)::integer), 0) + 1
                                  FROM core.exhibitor
                                """).query(Integer.class).single();
                String code = String.format(Locale.ROOT, "ESP%03d", next);
                int id = jdbc.sql("""
                                INSERT INTO core.exhibitor (exhibitor_code, legal_name, legal_name_norm, vat_number,
                                                           category_id, city)
                                VALUES (:code, :name, :norm, :vat, :categoryId, :city)
                                RETURNING exhibitor_id
                                """)
                        .param("code", code).param("name", value.legalName()).param("norm", normalize(value.legalName()))
                        .param("vat", value.vatNumber()).param("categoryId", value.categoryId())
                        .param("city", value.city()).query(Integer.class).single();
                saveContact(jdbc, id, value.contactName(), value.contactEmail());
                audit(jdbc, "EXHIBITOR_CREATED", id);
                return find(jdbc, id, true).orElseThrow();
            });
        } catch (DuplicateKeyException duplicate) {
            throw ApiException.conflict("EXHIBITOR_ALREADY_EXISTS", "Partita IVA gia' associata a un espositore");
        }
    }

    public Exhibitor update(int exhibitorId, ExhibitorInput input) {
        if (exhibitorId < 1) throw ApiException.badRequest("VALIDATION_ERROR", "exhibitorId deve essere positivo");
        Validated value = validate(input);
        try {
            return db.write(jdbc -> {
                Integer lockedId = jdbc.sql("SELECT exhibitor_id FROM core.exhibitor WHERE exhibitor_id = :id FOR UPDATE")
                        .param("id", exhibitorId).query(Integer.class).optional().orElse(null);
                if (lockedId == null) throw ApiException.notFound("NOT_FOUND", "Espositore non trovato");
                requireCategory(jdbc, value.categoryId());
                jdbc.sql("""
                                UPDATE core.exhibitor SET legal_name = :name, legal_name_norm = :norm,
                                    vat_number = :vat, category_id = :categoryId, city = :city
                                 WHERE exhibitor_id = :id
                                """)
                        .param("name", value.legalName()).param("norm", normalize(value.legalName()))
                        .param("vat", value.vatNumber()).param("categoryId", value.categoryId())
                        .param("city", value.city()).param("id", exhibitorId).update();
                saveContact(jdbc, exhibitorId, value.contactName(), value.contactEmail());
                audit(jdbc, "EXHIBITOR_UPDATED", exhibitorId);
                return find(jdbc, exhibitorId, true).orElseThrow();
            });
        } catch (DuplicateKeyException duplicate) {
            throw ApiException.conflict("EXHIBITOR_ALREADY_EXISTS", "Partita IVA gia' associata a un espositore");
        }
    }

    private static void saveContact(JdbcClient jdbc, int exhibitorId, String name, String email) {
        Integer contactId = jdbc.sql("""
                        SELECT contact_id FROM core.exhibitor_contact
                         WHERE exhibitor_id = :id AND is_primary FOR UPDATE
                        """)
                .param("id", exhibitorId).query(Integer.class).optional().orElse(null);
        if (name == null) {
            if (contactId != null) jdbc.sql("DELETE FROM core.exhibitor_contact WHERE contact_id = :id")
                    .param("id", contactId).update();
        } else if (contactId == null) {
            jdbc.sql("""
                            INSERT INTO core.exhibitor_contact (exhibitor_id, full_name, email, is_primary)
                            VALUES (:id, :name, :email, true)
                            """)
                    .param("id", exhibitorId).param("name", name).param("email", email).update();
        } else {
            jdbc.sql("UPDATE core.exhibitor_contact SET full_name = :name, email = :email WHERE contact_id = :id")
                    .param("name", name).param("email", email).param("id", contactId).update();
        }
    }

    private static java.util.Optional<Exhibitor> find(JdbcClient jdbc, int id, boolean includeContact) {
        return jdbc.sql("""
                        SELECT e.exhibitor_id, e.exhibitor_code, e.legal_name, e.vat_number,
                               e.category_id, cat.name AS category_name, e.city,
                               contact.full_name, contact.email
                          FROM core.exhibitor e
                          JOIN core.exhibitor_category cat ON cat.category_id = e.category_id
                          LEFT JOIN LATERAL (
                              SELECT full_name, email FROM core.exhibitor_contact
                               WHERE exhibitor_id = e.exhibitor_id AND is_primary
                               ORDER BY contact_id LIMIT 1
                          ) contact ON :includeContact
                         WHERE e.exhibitor_id = :id
                        """)
                .param("id", id).param("includeContact", includeContact)
                .query(ExhibitorService::map).optional();
    }

    private static Exhibitor map(java.sql.ResultSet rs, int row) throws java.sql.SQLException {
        String fullName = rs.getString("full_name");
        ContactRef contact = fullName == null ? null : new ContactRef(fullName, rs.getString("email"));
        return new Exhibitor(rs.getInt("exhibitor_id"), rs.getString("exhibitor_code"),
                rs.getString("legal_name"), rs.getString("vat_number"), rs.getInt("category_id"),
                rs.getString("category_name"), rs.getString("city"), contact);
    }

    private static void requireCategory(JdbcClient jdbc, int categoryId) {
        boolean exists = jdbc.sql("SELECT EXISTS (SELECT 1 FROM core.exhibitor_category WHERE category_id = :id)")
                .param("id", categoryId).query(Boolean.class).single();
        if (!exists) throw ApiException.validation(List.of(new it.arcade.backend.error.FieldError(
                "categoryId", "categoria inesistente")));
    }

    private static void audit(JdbcClient jdbc, String action, int id) {
        jdbc.sql("""
                        INSERT INTO core.audit_log (action, entity, entity_id)
                        VALUES (:action, 'exhibitor', :id)
                        """).param("action", action).param("id", String.valueOf(id)).update();
    }

    private static Validated validate(ExhibitorInput input) {
        ValidationErrors errors = new ValidationErrors();
        if (input == null) {
            errors.add("body", "obbligatorio");
            errors.throwIfAny();
        }
        String name = input.legalName() == null ? null : input.legalName().trim();
        String vat = input.vatNumber() == null ? null : input.vatNumber().trim().toUpperCase(Locale.ROOT);
        String city = blankToNull(input.city());
        String contactName = blankToNull(input.contactName());
        String email = blankToNull(input.contactEmail());
        if (name == null || name.length() < 2 || name.length() > 200) errors.add("legalName", "da 2 a 200 caratteri");
        if (vat == null || !vat.matches("[0-9A-Z]{8,14}")) errors.add("vatNumber", "formato non valido (8-14 lettere o cifre maiuscole)");
        if (input.categoryId() == null || input.categoryId() < 1) errors.add("categoryId", "obbligatorio e positivo");
        if ((contactName == null) != (email == null)) errors.add("contactEmail", "nome ed email del contatto vanno forniti insieme");
        if (email != null && !email.matches("^[^@\\s]+@[^@\\s]+$")) errors.add("contactEmail", "indirizzo email non valido");
        errors.throwIfAny();
        return new Validated(name, vat, input.categoryId(), city, contactName, email);
    }

    private record Validated(String legalName, String vatNumber, int categoryId, String city,
                             String contactName, String contactEmail) {}

    private static String normalize(String value) {
        String ascii = Normalizer.normalize(value, Normalizer.Form.NFKD).replaceAll("\\p{M}+", "");
        String normalized = ascii.toUpperCase(Locale.ROOT).replaceAll("[^A-Z0-9]+", " ").trim();
        return normalized.replaceFirst("\\s+(S R L|S R L S|S P A|S A S|S N C|S A P A)$", "").trim();
    }

    private static String blankToNull(String value) {
        if (value == null || value.isBlank()) return null;
        return value.trim();
    }

    private static void validatePage(int page, int size) {
        ValidationErrors errors = new ValidationErrors();
        if (page < 0) errors.add("page", "deve essere maggiore o uguale a zero");
        if (size < 1 || size > 200) errors.add("size", "deve essere compreso tra 1 e 200");
        errors.throwIfAny();
    }

    private static String orderBy(String sort) {
        if (sort == null || sort.isBlank()) return "e.legal_name ASC";
        String[] pieces = sort.split(",", -1);
        String column = pieces[0].trim();
        String direction = pieces.length == 2 ? pieces[1].trim().toLowerCase(Locale.ROOT) : "asc";
        String sql = SORTS.get(column);
        if (pieces.length > 2 || sql == null || !(direction.equals("asc") || direction.equals("desc"))) {
            throw ApiException.badRequest("VALIDATION_ERROR", "sort deve indicare un campo consentito e asc/desc");
        }
        return sql + " " + direction.toUpperCase(Locale.ROOT) + ", e.exhibitor_id ASC";
    }
}
