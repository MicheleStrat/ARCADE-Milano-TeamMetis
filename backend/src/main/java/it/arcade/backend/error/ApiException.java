package it.arcade.backend.error;

import org.springframework.http.HttpStatus;

/** Errore previsto dell'API: diventa una risposta problem+json con questo codice stabile. */
public class ApiException extends RuntimeException {

    private final HttpStatus status;
    private final String code;
    private final String title;
    private final String detail;

    public ApiException(HttpStatus status, String code, String title, String detail) {
        super(detail != null ? detail : title);
        this.status = status;
        this.code = code;
        this.title = title;
        this.detail = detail;
    }

    public static ApiException notFound(String code, String title) {
        return new ApiException(HttpStatus.NOT_FOUND, code, title, null);
    }

    public static ApiException forbidden() {
        return new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Ruolo non autorizzato", null);
    }

    public HttpStatus status() { return status; }
    public String code() { return code; }
    public String title() { return title; }
    public String detail() { return detail; }
}
