package it.arcade.backend.security;

/** Ruoli del contratto API (x-roles in docs/api/openapi.yaml). */
public enum Role {
    ADMIN, COMMERCIAL, OPS, EXHIBITOR, SCANNER, BI_READER;

    public boolean isStaff() {
        return this == ADMIN || this == COMMERCIAL || this == OPS;
    }
}
