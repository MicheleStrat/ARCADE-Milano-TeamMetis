package it.arcade.backend.commercial.dto;

import java.time.LocalDate;

public record ContractFromQuote(LocalDate signedOn, Boolean isRenewal) {}
