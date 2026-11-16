package it.arcade.backend.commercial;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/** Assunzione da confermare coi product owner: durata della riserva degli stand. */
@ConfigurationProperties(prefix = "arcade.quote")
public record QuoteProperties(@DefaultValue("14") int reservationDays) {}
