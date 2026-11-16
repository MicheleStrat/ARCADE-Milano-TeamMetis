package it.arcade.backend.commercial.dto;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

public record Contract(int contractId, String contractNumber, int editionId, int exhibitorId, Integer quoteId,
                       String status, LocalDate signedOn, BigDecimal listAmount, BigDecimal discountPct,
                       BigDecimal netAmount, boolean isRenewal, int rowVersion, List<ContractStandRef> stands,
                       List<DocumentLine> lines, List<Payment> payments) {}
