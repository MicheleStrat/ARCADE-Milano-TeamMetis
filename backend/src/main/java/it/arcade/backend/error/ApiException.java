package it.arcade.backend.error;

import java.util.List;
import org.springframework.http.HttpStatus;

/** Errore previsto dell'API: diventa una risposta problem+json con questo codice stabile. */
public class ApiException extends RuntimeException {

    private final HttpStatus status;
    private final String code;
    private final String title;
    private final String detail;
    private final List<FieldError> errors;

    public ApiException(HttpStatus status, String code, String title, String detail) {
        this(status, code, title, detail, null);
    }

    public ApiException(HttpStatus status, String code, String title, String detail, List<FieldError> errors) {
        super(detail != null ? detail : title);
        this.status = status;
        this.code = code;
        this.title = title;
        this.detail = detail;
        this.errors = errors;
    }

    public static ApiException notFound(String code, String title) {
        return new ApiException(HttpStatus.NOT_FOUND, code, title, null);
    }

    public static ApiException forbidden() {
        return new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Ruolo non autorizzato", null);
    }

    public static ApiException conflict(String code, String title) {
        return new ApiException(HttpStatus.CONFLICT, code, title, null);
    }

    public static ApiException unprocessable(String code, String title) {
        return new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, code, title, null);
    }

    public static ApiException badRequest(String code, String title) {
        return new ApiException(HttpStatus.BAD_REQUEST, code, title, null);
    }

    public static ApiException validation(List<FieldError> errors) {
        return new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "VALIDATION_ERROR", "Dati non validi", null, errors);
    }

    public HttpStatus status() { return status; }
    public String code() { return code; }
    public String title() { return title; }
    public String detail() { return detail; }
    public List<FieldError> errors() { return errors; }
}
