package it.arcade.backend.commercial.dto;

import java.math.BigDecimal;

public record DocumentLine(int lineNo, String lineType, int priceItemId, Integer standEditionId, String standCode,
                           String description, BigDecimal quantity, BigDecimal unitPrice, BigDecimal amount) {}
