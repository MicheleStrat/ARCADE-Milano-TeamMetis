package it.arcade.backend.commercial.dto;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

public record QuoteCreate(Integer editionId, Integer exhibitorId, BigDecimal discountPct, LocalDate validUntil,
                          List<QuoteLineInput> lines) {}
