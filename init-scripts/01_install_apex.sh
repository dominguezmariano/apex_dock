#!/bin/bash
# Runs once on the first boot of the DB container (Oracle Free auto-executes
# files in /opt/oracle/scripts/setup/ in alpha order). Installs APEX into
# FREEPDB1, creates the INTERNAL ADMIN user and unlocks APEX_PUBLIC_USER.

set -euo pipefail

APEX_ZIP="/opt/oracle/apex-installer/apex-latest.zip"
APEX_WORK="/home/oracle/apex-install"
APEX_IMAGES_DEST="/opt/oracle/apex-images"

log() { echo "==> [apex-init] $*"; }

# Forzar el password de SYS/SYSTEM al valor de ORACLE_PWD del .env. Es defensivo:
# en algunas combinaciones de version + entrypoint custom, dbca prompted
# interactivamente durante el primer init y el SYS quedo con un password
# distinto del que estamos pasando, desincronizando ORDS. Como nos conectamos
# por OS auth (/ as sysdba), no necesitamos saber el password actual.
log "Sincronizando password de SYS/SYSTEM con ORACLE_PWD del .env"
sqlplus -S / as sysdba <<SQL
WHENEVER SQLERROR CONTINUE
ALTER USER SYS IDENTIFIED BY "${ORACLE_PWD}";
ALTER USER SYSTEM IDENTIFIED BY "${ORACLE_PWD}";
EXIT;
SQL

if [ ! -f "$APEX_ZIP" ]; then
  log "$APEX_ZIP not found. Mount apex-latest.zip into the container to auto-install APEX. Skipping."
  exit 0
fi

log "Unzipping APEX from $APEX_ZIP"
mkdir -p "$APEX_WORK"
cd "$APEX_WORK"
unzip -q -o "$APEX_ZIP"

log "Running apexins.sql against FREEPDB1 (15-20 min)"
cd "$APEX_WORK/apex"
sqlplus -S / as sysdba <<SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = FREEPDB1;
@apexins.sql SYSAUX SYSAUX TEMP /i/
EXIT;
SQL

log "Creating INTERNAL ADMIN user and unlocking APEX_PUBLIC_USER"
sqlplus -S / as sysdba <<SQL
WHENEVER SQLERROR EXIT SQL.SQLCODE
ALTER SESSION SET CONTAINER = FREEPDB1;
DECLARE
  l_user_id NUMBER;
BEGIN
  APEX_UTIL.set_workspace(p_workspace => 'INTERNAL');
  BEGIN
    l_user_id := APEX_UTIL.get_user_id('ADMIN');
  EXCEPTION WHEN OTHERS THEN l_user_id := NULL;
  END;
  IF l_user_id IS NULL THEN
    APEX_UTIL.create_user(
      p_user_name                    => 'ADMIN',
      p_email_address                => '${APEX_ADMIN_EMAIL:-admin@example.com}',
      p_web_password                 => '${APEX_ADMIN_PWD:-Welcome_2026}',
      p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
      p_change_password_on_first_use => 'N');
  ELSE
    APEX_UTIL.edit_user(
      p_user_id                      => l_user_id,
      p_user_name                    => 'ADMIN',
      p_web_password                 => '${APEX_ADMIN_PWD:-Welcome_2026}',
      p_new_password                 => '${APEX_ADMIN_PWD:-Welcome_2026}',
      p_change_password_on_first_use => 'N');
  END IF;
  COMMIT;
END;
/
ALTER USER APEX_PUBLIC_USER IDENTIFIED BY "${ORACLE_PWD}" ACCOUNT UNLOCK;
EXIT;
SQL

if [ -d "$APEX_IMAGES_DEST" ]; then
  log "Copying static images to $APEX_IMAGES_DEST (for ORDS to serve at /i/)"
  cp -r "$APEX_WORK/apex/images/." "$APEX_IMAGES_DEST/"
fi

log "Cleaning up $APEX_WORK"
rm -rf "$APEX_WORK"

log "APEX install completed"
