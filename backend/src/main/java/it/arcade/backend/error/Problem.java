package it.arcade.backend.error;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.util.List;

/** Corpo degli errori (schema `Problem` di docs/api/openapi.yaml). */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record Problem(String type, String title, int status, String code, String detail, String traceId,
                      List<FieldError> errors) {}
