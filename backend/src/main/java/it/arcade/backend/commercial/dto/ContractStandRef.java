package it.arcade.backend.commercial.dto;

import java.math.BigDecimal;

public record ContractStandRef(int standEditionId, String standCode, BigDecimal sqm) {}
