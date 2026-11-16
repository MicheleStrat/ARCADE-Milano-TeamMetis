package it.arcade.backend.commercial;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/** Assunzione da confermare coi product owner (domanda D34): giorni tra la firma e la scadenza dell'acconto. */
@ConfigurationProperties(prefix = "arcade.contract")
public record ContractProperties(@DefaultValue("15") int depositDueDays) {}
