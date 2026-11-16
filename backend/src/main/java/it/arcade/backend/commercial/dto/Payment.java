package it.arcade.backend.commercial.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

public record Payment(int paymentId, int contractId, String kind, LocalDate dueOn, BigDecimal dueAmount,
                      String dueAmountBasis, LocalDate paidOn, BigDecimal paidAmount, boolean paidAmountIsAssumed,
                      String state) {}
