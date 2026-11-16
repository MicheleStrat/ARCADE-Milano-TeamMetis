package it.arcade.backend.commercial.dto;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

public record Quote(int quoteId, String quoteNumber, int editionId, int exhibitorId, String status,
                    BigDecimal discountPct, BigDecimal listAmount, BigDecimal netAmount, LocalDate validUntil,
                    OffsetDateTime createdAt, int rowVersion, List<DocumentLine> lines) {
    public Quote withLines(List<DocumentLine> newLines) {
        return new Quote(quoteId, quoteNumber, editionId, exhibitorId, status, discountPct, listAmount, netAmount,
                validUntil, createdAt, rowVersion, newLines);
    }
}
