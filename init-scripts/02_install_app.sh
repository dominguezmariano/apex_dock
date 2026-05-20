#!/bin/bash
# Auto-importa el workspace, la app APEX y los objetos del schema en el primer
# boot del DB container. Lee archivos de /opt/oracle/apex-app/ (montado desde
# ./apex-app/ del host).
#
# Layout esperado:
#   apex-app/
#     01_workspace.sql            Export del workspace APEX (apex_admin)
#     02_app.sql                  Export de la app APEX (App Builder)
#     03_schema/                  (opcional) objetos DB del parsing schema
#       01_tables/*.sql
#       02_sequences/*.sql
#       03_indexes/*.sql
#       04_triggers/*.sql
#       05_packages/*.sql         spec antes que body
#       06_functions/*.sql
#       07_data/*.sql
#
# Si faltan 01_workspace.sql o 02_app.sql, skipea silenciosamente (el stack
# funciona igual sin app precargada). 03_schema/ es opcional.

set -euo pipefail

APP_DIR="/opt/oracle/apex-app"
PARSING_SCHEMA="${APP_PARSING_SCHEMA:-XX_APEX_DOCKER}"
PARSING_PWD="${APP_PARSING_SCHEMA_PWD:-$ORACLE_PWD}"
WORKSPACE_NAME="${APP_WORKSPACE_NAME:-XX_APEX_DOCKER}"

log() { echo "==> [app-install] $*"; }

if [ ! -d "$APP_DIR" ]; then
  log "$APP_DIR no encontrado. Skipping app install."
  exit 0
fi

if [ ! -f "$APP_DIR/01_workspace.sql" ] || [ ! -f "$APP_DIR/02_app.sql" ]; then
  log "Falta 01_workspace.sql o 02_app.sql en $APP_DIR. Skipping (poner los exports en ./apex-app/ y hacer 'docker compose down -v && up' para reinstalar)."
  exit 0
fi

log "Creando parsing schema $PARSING_SCHEMA si no existe"
sqlplus -S / as sysdba <<SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = FREEPDB1;
DECLARE
  v_cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM dba_users WHERE username = UPPER('$PARSING_SCHEMA');
  IF v_cnt = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER "$PARSING_SCHEMA" IDENTIFIED BY "$PARSING_PWD"';
    EXECUTE IMMEDIATE 'GRANT CONNECT, RESOURCE, CREATE VIEW, CREATE PROCEDURE, CREATE TRIGGER, CREATE SEQUENCE, CREATE TYPE, CREATE SYNONYM TO "$PARSING_SCHEMA"';
    EXECUTE IMMEDIATE 'GRANT UNLIMITED TABLESPACE TO "$PARSING_SCHEMA"';
  END IF;
END;
/
EXIT;
SQL

log "Importando workspace (01_workspace.sql)"
sqlplus -S / as sysdba <<SQL
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER = FREEPDB1;
@$APP_DIR/01_workspace.sql
EXIT;
SQL

log "Importando app (02_app.sql)"
sqlplus -S / as sysdba <<SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = FREEPDB1;
DECLARE
  v_ws_id NUMBER;
BEGIN
  SELECT workspace_id INTO v_ws_id FROM apex_workspaces WHERE workspace = UPPER('$WORKSPACE_NAME');
  APEX_APPLICATION_INSTALL.SET_WORKSPACE_ID(v_ws_id);
  APEX_APPLICATION_INSTALL.SET_SCHEMA(UPPER('$PARSING_SCHEMA'));
END;
/
@$APP_DIR/02_app.sql
EXIT;
SQL

# Instalar objetos DB del parsing schema iterando subcarpetas en orden
if [ -d "$APP_DIR/03_schema" ]; then
  log "Instalando objetos DB del schema ($APP_DIR/03_schema)"
  for category in $(find "$APP_DIR/03_schema" -mindepth 1 -maxdepth 1 -type d | sort); do
    cat_name=$(basename "$category")
    log "  -> $cat_name"
    for f in $(find "$category" -maxdepth 1 -type f -name '*.sql' | sort); do
      f_name=$(basename "$f")
      log "     $f_name"
      sqlplus -S "$PARSING_SCHEMA/$PARSING_PWD@localhost:1521/FREEPDB1" <<SQL
WHENEVER SQLERROR CONTINUE
SET DEFINE OFF
@$f
EXIT;
SQL
    done
  done
else
  log "$APP_DIR/03_schema no existe. Skipping objetos DB."
fi

log "Otorgando ACLs de red (parsing schema + APEX_PUBLIC_USER + APEX_NNNNNN)"
sqlplus -S / as sysdba <<SQL
WHENEVER SQLERROR CONTINUE
ALTER SESSION SET CONTAINER = FREEPDB1;
DECLARE
  l_apex_schema VARCHAR2(30);
  TYPE t_list IS TABLE OF VARCHAR2(30);
  l_users t_list;
BEGIN
  SELECT MAX(username) INTO l_apex_schema FROM dba_users WHERE REGEXP_LIKE(username, '^APEX_[0-9]{6}\$');
  l_users := t_list(UPPER('$PARSING_SCHEMA'), 'APEX_PUBLIC_USER', l_apex_schema);
  FOR i IN 1..l_users.COUNT LOOP
    BEGIN
      DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
        host => '*',
        ace  => xs\$ace_type(
                  privilege_list => xs\$name_list('connect', 'resolve'),
                  principal_name => l_users(i),
                  principal_type => xs_acl.ptype_db
                )
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
  COMMIT;
END;
/
EXIT;
SQL

log "App install completed"

# Marcador para que el entrypoint en docker-compose.yml sepa que ya inicializamos
# todo (APEX + workspace + app + schema). Sin este archivo, el proximo boot
# borraria la DB pensando que es la prebuilt de la imagen.
touch /opt/oracle/oradata/.user_init_done
