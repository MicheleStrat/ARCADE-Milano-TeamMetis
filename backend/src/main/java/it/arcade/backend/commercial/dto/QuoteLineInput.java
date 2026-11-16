package it.arcade.backend.commercial.dto;

import java.math.BigDecimal;

public record QuoteLineInput(Integer priceItemId, Integer standEditionId, BigDecimal quantity, String description) {}
