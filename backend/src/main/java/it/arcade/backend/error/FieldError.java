package it.arcade.backend.error;

/** Errore su un campo (schema `FieldError` di docs/api/openapi.yaml). */
public record FieldError(String field, String message) {}
