package it.arcade.backend.error;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component
public class ProblemWriter {

    private final ObjectMapper mapper;

    public ProblemWriter(ObjectMapper mapper) {
        this.mapper = mapper;
    }

    public Problem problem(HttpStatus status, String code, String title, String detail) {
        return new Problem("about:blank", title, status.value(), code, detail, MDC.get(RequestIdFilter.MDC_KEY));
    }

    /** Per i filtri di sicurezza, che rispondono fuori dai controller. */
    public void write(HttpServletResponse response, HttpStatus status, String code, String title, String detail)
            throws IOException {
        response.setStatus(status.value());
        response.setContentType("application/problem+json");
        response.setCharacterEncoding("UTF-8");
        mapper.writeValue(response.getOutputStream(), problem(status, code, title, detail));
    }
}
