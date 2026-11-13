package it.arcade.backend.api;

import it.arcade.backend.db.DbRole;
import it.arcade.backend.db.ScopedDb;
import it.arcade.backend.security.CurrentUser;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class EditionController {

    private static final DateTimeFormatter HHMM = DateTimeFormatter.ofPattern("HH:mm");

    public record EditionDay(LocalDate dayDate, int dayNumber, String opensAt, String closesAt) {}

    public record Edition(int editionId, int year, String name, String status, String timezone,
                          List<EditionDay> days) {}

    private final ScopedDb db;

    public EditionController(ScopedDb db) {
        this.db = db;
    }

    @GetMapping("/editions")
    public List<Edition> list(@AuthenticationPrincipal Jwt jwt) {
        CurrentUser user = CurrentUser.from(jwt);
        return db.read(DbRole.forUser(user), user.exhibitorId(), jdbc -> {
            Map<Integer, Edition> byId = new LinkedHashMap<>();
            jdbc.sql("SELECT edition_id, year, name, status, timezone FROM core.edition ORDER BY year")
                    .query((rs, n) -> new Edition(rs.getInt("edition_id"), rs.getInt("year"), rs.getString("name"),
                            rs.getString("status"), rs.getString("timezone"), new ArrayList<>()))
                    .list()
                    .forEach(e -> byId.put(e.editionId(), e));
            jdbc.sql("SELECT edition_id, day_date, day_number, opens_at, closes_at "
                            + "FROM core.edition_day ORDER BY edition_id, day_date")
                    .query(rs -> {
                        byId.get(rs.getInt("edition_id")).days().add(new EditionDay(
                                rs.getObject("day_date", LocalDate.class),
                                rs.getInt("day_number"),
                                rs.getObject("opens_at", LocalTime.class).format(HHMM),
                                rs.getObject("closes_at", LocalTime.class).format(HHMM)));
                    });
            return new ArrayList<>(byId.values());
        });
    }
}
