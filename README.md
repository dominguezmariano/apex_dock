# Oracle APEX + DB + ORDS en Docker

Stack dockerizado para desarrollo APEX local:

- **Oracle Database 23ai Free** (imagen oficial `container-registry.oracle.com/database/free:latest`)
- **Oracle APEX 26.1** (instalado automÃ¡ticamente en el primer boot vÃ­a init script)
- **ORDS** (imagen oficial `container-registry.oracle.com/database/ords:latest`)

Las imÃ¡genes son las oficiales de Oracle y **no requieren login**.

## Estructura

```
ApexDocker/
âââ docker-compose.yml          Define los servicios db y ords
âââ .env                        Passwords (NO commitear)
âââ .env.example                Plantilla de .env
âââ downloads/
â   âââ apex-latest.zip         Instalador de APEX (lo bajÃ¡s vos, ~300 MB)
âââ init-scripts/
â   âââ 01_install_apex.sh      Auto-instalaciÃ³n de APEX en el primer boot
âââ apex-images/                EstÃ¡ticos de APEX que ORDS sirve en /i/
âââ scripts/
â   âââ download-apex.ps1       Helper para bajar el zip
âââ sql/                        SQL helpers (manuales, no se ejecutan solos)
    âââ setup_apex_admin.sql    Crear/resetear admin de APEX
    âââ uninstall_ords.sql      Drop de schemas ORDS
    âââ cleanup_ords_synonyms.sql  Limpiar synonyms huÃ©rfanos
```

## Primer arranque (desde cero)

1. **Editar `.env`** y poner tus passwords. Reglas: mÃ­n. 8 chars, mayÃºscula + minÃºscula + nÃºmero + carÃ¡cter especial (`_ # $`).

2. **Descargar APEX**:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\download-apex.ps1
   ```

   (o manualmente: bajar https://download.oracle.com/otn_software/apex/apex-latest.zip a `downloads/apex-latest.zip`)

3. **Levantar el stack**:

   ```powershell
   docker compose up -d
   ```

4. **Esperar el primer boot** â tarda ~25-30 minutos porque la DB se crea, APEX se instala (~15-20 min) y despuÃ©s ORDS se instala (~3-5 min). SeguÃ­ el progreso:

   ```powershell
   docker compose logs -f db
   docker compose logs -f ords
   ```

   Marcadores clave:
   - DB: `==> [apex-init] APEX install completed` â APEX OK
   - DB: `DATABASE IS READY TO USE!` â DB healthy
   - ORDS: `Oracle REST Data Services initialized` â ORDS OK

5. **Login** en http://localhost:8181/ords/apex_admin con:
   - Workspace: `INTERNAL`
   - Username: `ADMIN`
   - Password: el de `APEX_ADMIN_PWD` en `.env`

6. **Crear tu workspace** desde el admin (Manage Workspaces â Create Workspace), despuÃ©s loguearte en http://localhost:8181/ords/apex con esas credenciales nuevas.

## Accesos

| Servicio | URL / ConexiÃ³n | Credenciales |
|---|---|---|
| APEX Internal Admin | http://localhost:8181/ords/apex_admin | `INTERNAL` / `ADMIN` / `${APEX_ADMIN_PWD}` |
| APEX (workspaces de dev) | http://localhost:8181/ords/apex | el workspace que crees |
| ORDS landing | http://localhost:8181/ords/ | â |
| Oracle DB (SQL*Net) | `localhost:1521/FREEPDB1` | `SYS as SYSDBA` / `SYSTEM` con `${ORACLE_PWD}` |
| EM Express | https://localhost:5500/em | `SYS` con `${ORACLE_PWD}` |

CDB se llama `FREE`; PDB se llama `FREEPDB1`. Para desarrollo APEX siempre conectate al PDB.

## Comandos Ãºtiles

```powershell
# Estado
docker compose ps

# Logs en vivo
docker compose logs -f db
docker compose logs -f ords

# SQL*Plus al PDB
docker exec -it apex-db sqlplus system/$env:ORACLE_PWD@localhost:1521/FREEPDB1

# Shell en ORDS
docker exec -it apex-ords bash

# Apagar (datos persisten)
docker compose down

# Apagar y BORRAR datos (cuidado â vuelve a cero, reinstala APEX)
docker compose down -v
Remove-Item -Recurse -Force apex-images
```

## VolÃºmenes

| Volumen | Contenido | Sobrevive a `down`? | Sobrevive a `down -v`? |
|---|---|---|---|
| `apex-oradata` (Docker named) | Datafiles de Oracle | sÃ­ | no |
| `apex-ords-config` (Docker named) | Config de ORDS | sÃ­ | no |
| `./apex-images` (bind mount) | EstÃ¡ticos APEX (~600 MB) | sÃ­ | sÃ­ (es del host) |
| `./downloads` (bind) | apex-latest.zip | sÃ­ | sÃ­ |

## Troubleshooting

- **"the Oracle APEX files have not been loaded"** en el login â el dir `./apex-images` estÃ¡ vacÃ­o o ORDS no lo lee. VerificÃ¡ `docker exec apex-ords ls /opt/oracle/apex/images | wc -l` (deberÃ­a dar ~856). Si estÃ¡ vacÃ­o, copialo de la DB: `docker cp apex-db:/home/oracle/apex-install/apex/images ./apex-images` (solo si la DB se estÃ¡ instalando) o re-extraÃ© el zip al host.

- **ORDS en restart loop con "synonym translation no longer valid"** â tenÃ©s synonyms huÃ©rfanos de una instalaciÃ³n previa de ORDS. Correr [sql/cleanup_ords_synonyms.sql](sql/cleanup_ords_synonyms.sql) y despuÃ©s recrear el container de ORDS.

- **ORDS en restart loop con "config directory empty"** â ORDS ya estÃ¡ instalado en la DB pero el volumen `apex-ords-config` estÃ¡ vacÃ­o. Correr [sql/uninstall_ords.sql](sql/uninstall_ords.sql) para hacer drop de los schemas y dejar que reinstale limpio.

- **Cambiar password del ADMIN de APEX** â editar `.env`, correr [sql/setup_apex_admin.sql](sql/setup_apex_admin.sql) con: `docker cp sql/setup_apex_admin.sql apex-db:/tmp/ && docker exec apex-db sqlplus -S sys/$env:ORACLE_PWD@localhost:1521/FREEPDB1 as sysdba @/tmp/setup_apex_admin.sql`

## Notas

- APEX **no viene preinstalado** en la imagen `container-registry.oracle.com/database/free:latest`. El init script lo instala en el primer boot.
- ORDS se auto-instala contra la DB al primer arranque y persiste su config en el volumen `apex-ords-config`.
- Los archivos en `init-scripts/` se ejecutan **una sola vez**, en el primer boot de la DB. Si querÃ©s re-correrlos, hacÃ© `docker compose down -v` (cuidado: borra todo).
