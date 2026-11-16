package it.arcade.backend.api;

import it.arcade.backend.db.DbRole;
import it.arcade.backend.security.CurrentUser;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Read-only anagrafiche e cataloghi del contratto API v1. */
@RestController
public class CatalogController {

    public record EditionDay(LocalDate dayDate, int dayNumber, String opensAt, String closesAt) {}
    public record Edition(int editionId, int year, String name, String status, String timezone,
                          List<EditionDay> days) {}
    public record Pavilion(int pavilionId, String code, String name) {}
    public record ExhibitorCategory(int categoryId, String name) {}
    public record Geometry(BigDecimal x, BigDecimal y, BigDecimal width, BigDecimal height) {}
    public record ExhibitorRef(int exhibitorId, String legalName) {}
    public record StandEdition(int standEditionId, int standId, String standCode, String pavilionCode,
                               BigDecimal sqm, String positionType, String commercialStatus,
                               java.time.OffsetDateTime reservedUntil, BigDecimal listPrice,
                               Geometry geometry, ExhibitorRef exhibitor, int rowVersion) {}
    public record PavilionPlan(String pavilionCode, String name, List<StandEdition> stands) {}
    public record Floorplan(int editionId, List<PavilionPlan> pavilions) {}
    public record Page<T>(int page, int size, long totalElements, int totalPages, List<T> content) {}
    public record PriceItem(int priceItemId, String code, String name, String itemType, String unit,
                            BigDecimal unitPrice, BigDecimal pct, String pavilionCode,
                            String positionType, Integer maxQuantity) {}
    public record PriceList(int priceListId, int editionId, String origin, String status,
                            BigDecimal depositPct, Integer balanceDaysBefore, LocalDate preemptionDeadline,
                            List<PriceItem> items) {}
    public record PriceItemUpdate(BigDecimal unitPrice, BigDecimal pct, Integer maxQuantity) {}

    private final CatalogService catalog;

    public CatalogController(CatalogService catalog) {
        this.catalog = catalog;
    }

    @GetMapping("/editions/{editionId}")
    public Edition getEdition(@AuthenticationPrincipal Jwt jwt, @PathVariable int editionId) {
        return catalog.getEdition(editionId, role(jwt));
    }

    @GetMapping("/pavilions")
    public List<Pavilion> pavilions(@AuthenticationPrincipal Jwt jwt) {
        return catalog.pavilions(role(jwt));
    }

    @GetMapping("/exhibitor-categories")
    public List<ExhibitorCategory> categories(@AuthenticationPrincipal Jwt jwt) {
        return catalog.categories(role(jwt));
    }

    @GetMapping("/editions/{editionId}/floorplan")
    public Floorplan floorplan(@AuthenticationPrincipal Jwt jwt, @PathVariable int editionId) {
        CurrentUser user = CurrentUser.from(jwt);
        return catalog.floorplan(editionId, DbRole.forUser(user), user.roles());
    }

    @GetMapping("/editions/{editionId}/stands")
    public Page<StandEdition> stands(@AuthenticationPrincipal Jwt jwt, @PathVariable int editionId,
                                     @RequestParam(required = false) String pavilionCode,
                                     @RequestParam(required = false) String commercialStatus,
                                     @RequestParam(defaultValue = "0") int page,
                                     @RequestParam(defaultValue = "20") int size,
                                     @RequestParam(defaultValue = "standCode,asc") String sort) {
        CurrentUser user = CurrentUser.from(jwt);
        return catalog.stands(editionId, DbRole.forUser(user), user.roles(), pavilionCode,
                commercialStatus, page, size, sort);
    }

    @GetMapping("/editions/{editionId}/price-list")
    public PriceList priceList(@AuthenticationPrincipal Jwt jwt, @PathVariable int editionId) {
        return catalog.priceList(editionId, role(jwt));
    }

    @PatchMapping("/price-items/{priceItemId}")
    public PriceItem updatePriceItem(@PathVariable int priceItemId, @RequestBody PriceItemUpdate body) {
        return catalog.updatePriceItem(priceItemId, body);
    }

    private static DbRole role(Jwt jwt) {
        return DbRole.forUser(CurrentUser.from(jwt));
    }
}
