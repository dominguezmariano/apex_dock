#!/bin/bash
# Habilita el PL/SQL Gateway en ORDS. En ORDS 24+ esta deshabilitado por
# default, lo que hace que las URLs de APEX (/ords/apex, /ords/apex_admin,
# /ords/f?p=...) devuelvan 404. La imagen oficial de ORDS solo setea esta
# config si encuentra apxsilentins.sql montado (que indica que APEX install
# files estan disponibles en el container de ORDS), pero en nuestro setup
# APEX se instala desde el container de DB y el de ORDS no ve esos scripts.
# Por eso lo seteamos explicitamente aca.

set -euo pipefail

log() { echo "==> [ords-init] $*"; }

CURRENT_MODE=$(ords --config /etc/ords/config config list 2>/dev/null | awk '/plsql.gateway.mode/ {print $2}')

if [ "$CURRENT_MODE" = "proxied" ]; then
  log "plsql.gateway.mode ya esta en 'proxied'. Skipping."
else
  log "Seteando plsql.gateway.mode = proxied (estado anterior: '${CURRENT_MODE:-unset}')"
  ords --config /etc/ords/config config set plsql.gateway.mode proxied
fi
