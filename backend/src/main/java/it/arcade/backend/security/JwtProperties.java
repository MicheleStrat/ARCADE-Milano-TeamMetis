package it.arcade.backend.security;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

@ConfigurationProperties(prefix = "arcade.jwt")
public record JwtProperties(String secret, @DefaultValue("60") long ttlMinutes) {}
