package it.arcade.backend.error;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.web.ErrorResponse;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.resource.NoResourceFoundException;

@RestControllerAdvice
public class RestExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(RestExceptionHandler.class);
    private static final MediaType PROBLEM = MediaType.valueOf("application/problem+json");

    private final ProblemWriter problems;

    public RestExceptionHandler(ProblemWriter problems) {
        this.problems = problems;
    }

    @ExceptionHandler(ApiException.class)
    ResponseEntity<Problem> api(ApiException e) {
        return reply(e.status(), e.code(), e.title(), e.detail());
    }

    @ExceptionHandler(NoResourceFoundException.class)
    ResponseEntity<Problem> notFound(NoResourceFoundException e) {
        return reply(HttpStatus.NOT_FOUND, "NOT_FOUND", "Risorsa non trovata", null);
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    ResponseEntity<Problem> method(HttpRequestMethodNotSupportedException e) {
        return reply(HttpStatus.METHOD_NOT_ALLOWED, "METHOD_NOT_ALLOWED", "Metodo non consentito", null);
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    ResponseEntity<Problem> unreadable(HttpMessageNotReadableException e) {
        return reply(HttpStatus.BAD_REQUEST, "INVALID_REQUEST", "Corpo della richiesta non valido", null);
    }

    /** Questi li gestisce la catena di sicurezza (401/403): qui non vanno trasformati in 500. */
    @ExceptionHandler({AccessDeniedException.class, AuthenticationException.class})
    void security(Exception e) throws Exception {
        throw e;
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<Problem> unexpected(Exception e) {
        // Le eccezioni standard di Spring MVC (415, 406, parametri mancanti...) portano gia' il loro stato HTTP.
        if (e instanceof ErrorResponse er && er.getStatusCode().is4xxClientError()) {
            HttpStatus status = HttpStatus.valueOf(er.getStatusCode().value());
            return reply(status, codeFor(status), status.getReasonPhrase(), null);
        }
        log.error("Errore non previsto", e);
        return reply(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR", "Errore interno", null);
    }

    private static String codeFor(HttpStatus status) {
        return switch (status) {
            case BAD_REQUEST -> "INVALID_REQUEST";
            case NOT_ACCEPTABLE -> "NOT_ACCEPTABLE";
            case UNSUPPORTED_MEDIA_TYPE -> "UNSUPPORTED_MEDIA_TYPE";
            default -> "HTTP_" + status.value();
        };
    }

    private ResponseEntity<Problem> reply(HttpStatus status, String code, String title, String detail) {
        return ResponseEntity.status(status).contentType(PROBLEM).body(problems.problem(status, code, title, detail));
    }
}
