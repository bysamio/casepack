#!/bin/bash
# Creates the Keycloak database and user in PostgreSQL.
# Mounted at /docker-entrypoint-initdb.d/ and executed on first DB init.
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE DATABASE ${KC_DB_NAME:-keycloak}' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${KC_DB_NAME:-keycloak}')\gexec
    DO \$\$ BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${KC_DB_USER:-keycloak}') THEN
        CREATE USER ${KC_DB_USER:-keycloak} WITH PASSWORD '${KC_DB_PASS}';
      END IF;
    END \$\$;
    GRANT ALL PRIVILEGES ON DATABASE ${KC_DB_NAME:-keycloak} TO ${KC_DB_USER:-keycloak};
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "${KC_DB_NAME:-keycloak}" <<-EOSQL
    GRANT ALL ON SCHEMA public TO ${KC_DB_USER:-keycloak};
EOSQL
