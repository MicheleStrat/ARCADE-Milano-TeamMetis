package it.arcade.backend.db;

import it.arcade.backend.error.ApiException;
import it.arcade.backend.security.CurrentUser;
import it.arcade.backend.security.Role;

/** Ruoli del database usati per le richieste. Il nome e' una costante: mai testo preso dal client. */
public enum DbRole {
    STAFF("arcade_app"),
    PORTAL("arcade_portal");

    private final String sqlName;

    DbRole(String sqlName) {
        this.sqlName = sqlName;
    }

    public String sqlName() {
        return sqlName;
    }

    /** Staff se ha un ruolo staff, altrimenti portale se e' un espositore, altrimenti 403. */
    public static DbRole forUser(CurrentUser user) {
        if (user.roles().stream().anyMatch(Role::isStaff)) {
            return STAFF;
        }
        if (user.roles().contains(Role.EXHIBITOR)) {
            return PORTAL;
        }
        throw ApiException.forbidden();
    }
}
