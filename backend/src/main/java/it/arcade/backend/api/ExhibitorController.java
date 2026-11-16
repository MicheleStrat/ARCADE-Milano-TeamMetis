package it.arcade.backend.api;

import it.arcade.backend.security.CurrentUser;
import it.arcade.backend.security.Role;
import java.util.Set;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ExhibitorController {

    public record ContactRef(String fullName, String email) {}
    public record Exhibitor(int exhibitorId, String exhibitorCode, String legalName, String vatNumber,
                            int categoryId, String categoryName, String city, ContactRef primaryContact) {}
    public record ExhibitorInput(String legalName, String vatNumber, Integer categoryId, String city,
                                 String contactName, String contactEmail) {}
    public record Page(int page, int size, long totalElements, int totalPages,
                       java.util.List<Exhibitor> content) {}

    private final ExhibitorService exhibitors;

    public ExhibitorController(ExhibitorService exhibitors) {
        this.exhibitors = exhibitors;
    }

    @GetMapping("/exhibitors")
    public Page list(@AuthenticationPrincipal Jwt jwt,
                     @RequestParam(required = false) String q,
                     @RequestParam(required = false) Integer categoryId,
                     @RequestParam(required = false) Integer editionId,
                     @RequestParam(defaultValue = "0") int page,
                     @RequestParam(defaultValue = "20") int size,
                     @RequestParam(defaultValue = "legalName,asc") String sort) {
        return exhibitors.list(q, categoryId, editionId, page, size, sort, showsContact(jwt));
    }

    @PostMapping("/exhibitors")
    @ResponseStatus(HttpStatus.CREATED)
    public Exhibitor create(@RequestBody ExhibitorInput body) {
        return exhibitors.create(body);
    }

    @GetMapping("/exhibitors/{exhibitorId}")
    public Exhibitor get(@AuthenticationPrincipal Jwt jwt, @PathVariable int exhibitorId) {
        return exhibitors.get(exhibitorId, showsContact(jwt));
    }

    @PutMapping("/exhibitors/{exhibitorId}")
    public Exhibitor update(@PathVariable int exhibitorId, @RequestBody ExhibitorInput body) {
        return exhibitors.update(exhibitorId, body);
    }

    private static boolean showsContact(Jwt jwt) {
        Set<Role> roles = CurrentUser.from(jwt).roles();
        return roles.contains(Role.ADMIN) || roles.contains(Role.COMMERCIAL);
    }
}
