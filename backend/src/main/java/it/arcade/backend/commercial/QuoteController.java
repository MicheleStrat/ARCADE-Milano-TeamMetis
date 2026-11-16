package it.arcade.backend.commercial;

import it.arcade.backend.commercial.IdempotencyService.Result;
import it.arcade.backend.commercial.dto.Quote;
import it.arcade.backend.commercial.dto.QuoteCreate;
import it.arcade.backend.db.DbRole;
import it.arcade.backend.security.CurrentUser;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class QuoteController {

    private final QuoteService quotes;

    public QuoteController(QuoteService quotes) {
        this.quotes = quotes;
    }

    static ResponseEntity<String> toResponse(Result r) {
        ResponseEntity.BodyBuilder b = ResponseEntity.status(r.status()).contentType(MediaType.APPLICATION_JSON);
        if (r.replayed()) {
            b.header("Idempotent-Replayed", "true");
        }
        return b.body(r.body());
    }

    @PostMapping("/quotes")
    public ResponseEntity<String> create(@AuthenticationPrincipal Jwt jwt,
                                         @RequestHeader(name = "Idempotency-Key", required = false) String key,
                                         @RequestBody QuoteCreate body) {
        return toResponse(quotes.create(jwt.getSubject(), key, body));
    }

    @PostMapping("/quotes/{quoteId}/send")
    public Quote send(@PathVariable int quoteId,
                      @RequestHeader(name = "If-Match", required = false) String ifMatch) {
        return quotes.transition(quoteId, ifMatch, "DRAFT", "SENT");
    }

    @PostMapping("/quotes/{quoteId}/confirm")
    public Quote confirm(@PathVariable int quoteId,
                         @RequestHeader(name = "If-Match", required = false) String ifMatch) {
        return quotes.transition(quoteId, ifMatch, "SENT", "CONFIRMED");
    }

    @GetMapping("/quotes/{quoteId}")
    public Quote get(@AuthenticationPrincipal Jwt jwt, @PathVariable int quoteId) {
        return quotes.get(quoteId, DbRole.forUser(CurrentUser.from(jwt)));
    }
}
