package it.arcade.backend.error;

import java.util.ArrayList;
import java.util.List;

/** Raccoglie gli errori sui campi e li lancia insieme come 422 VALIDATION_ERROR. */
public final class ValidationErrors {

    private final List<FieldError> errors = new ArrayList<>();

    public void add(String field, String message) {
        errors.add(new FieldError(field, message));
    }

    public boolean isEmpty() {
        return errors.isEmpty();
    }

    public void throwIfAny() {
        if (!errors.isEmpty()) {
            throw ApiException.validation(errors);
        }
    }
}
