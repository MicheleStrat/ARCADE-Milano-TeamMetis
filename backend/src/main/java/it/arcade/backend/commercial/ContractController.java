package it.arcade.backend.commercial;

import it.arcade.backend.commercial.dto.Contract;
import it.arcade.backend.commercial.dto.ContractFromQuote;
import it.arcade.backend.db.DbRole;
import it.arcade.backend.security.CurrentUser;
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
public class ContractController {

    private final ContractService contracts;

    public ContractController(ContractService contracts) {
        this.contracts = contracts;
    }

    @PostMapping("/quotes/{quoteId}/contract")
    public ResponseEntity<String> convert(@AuthenticationPrincipal Jwt jwt, @PathVariable int quoteId,
                                          @RequestHeader(name = "Idempotency-Key", required = false) String key,
                                          @RequestBody ContractFromQuote body) {
        return QuoteController.toResponse(contracts.convert(jwt.getSubject(), key, quoteId, body));
    }

    @GetMapping("/contracts/{contractId}")
    public Contract get(@AuthenticationPrincipal Jwt jwt, @PathVariable int contractId) {
        return contracts.get(contractId, DbRole.forUser(CurrentUser.from(jwt)));
    }
}
