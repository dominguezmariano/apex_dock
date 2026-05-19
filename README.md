# Oracle APEX + DB + ORDS en Docker

(ver datos.txt para resumen)

Stack dockerizado para desarrollo APEX local:

- **Oracle Database 23ai Free** (imagen oficial `container-registry.oracle.com/database/free:latest`)
- **Oracle APEX 26.1** (instalado automáticamente en el primer boot vía init script)
- **ORDS** (imagen oficial `container-registry.oracle.com/database/ords:latest`)

Las imágenes son las oficiales de Oracle y **no requieren login**.

## Estructura

```
ApexDocker/
├── docker-compose.yml          Define los servicios db y ords
├── .env                        Passwords (NO commitear)
├── .env.example                Plantilla de .env
├── downloads/
│   └── apex-latest.zip         Instalador de APEX (lo bajás vos, ~300 MB)
├── init-scripts/
│   ├── 01_install_apex.sh      Auto-instalación de APEX en el primer boot
│   └── 02_install_app.sh       Auto-instala workspace + app + schema objects (ver apex-app/)
├── apex-app/                   Exports del workspace, app y objetos DB para auto-install
│   ├── 01_workspace.sql        Export del workspace APEX
│   ├── 02_app.sql              Export de la app APEX
│   └── 03_schema/              Objetos DB del parsing schema (tables, packages, etc.)
├── apex-images/                Estáticos de APEX que ORDS sirve en /i/
├── scripts/
│   └── download-apex.ps1       Helper para bajar el zip
└── sql/                        SQL helpers (manuales, no se ejecutan solos)
    ├── setup_apex_admin.sql    Crear/resetear admin de APEX
    ├── uninstall_ords.sql      Drop de schemas ORDS
    ├── cleanup_ords_synonyms.sql  Limpiar synonyms huérfanos
    └── grant_network_acl.sql   Otorgar ACL de red a un schema (fix ORA-24247)
```

## Primer arranque (desde cero)

1. **Editar `.env`** y poner tus passwords. Reglas: mín. 8 chars, mayúscula + minúscula + número + carácter especial (`_ # $`).

2. **Descargar APEX**:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\download-apex.ps1
   ```

   (o manualmente: bajar https://download.oracle.com/otn_software/apex/apex-latest.zip a `downloads/apex-latest.zip`)

3. **Levantar el stack**:

   ```powershell
   docker compose up -d
   ```

4. **Esperar el primer boot** — tarda ~25-30 minutos porque la DB se crea, APEX se instala (~15-20 min) y después ORDS se instala (~3-5 min). Seguí el progreso:

   ```powershell
   docker compose logs -f db
   docker compose logs -f ords
   ```

   Marcadores clave:
   - DB: `==> [apex-init] APEX install completed` → APEX OK
   - DB: `DATABASE IS READY TO USE!` → DB healthy
   - ORDS: `Oracle REST Data Services initialized` → ORDS OK

5. **Login** en http://localhost:8181/ords/apex_admin con:
   - Workspace: `INTERNAL`
   - Username: `ADMIN`
   - Password: el de `APEX_ADMIN_PWD` en `.env`

6. **Crear tu workspace** desde el admin (Manage Workspaces → Create Workspace), después loguearte en http://localhost:8181/ords/apex con esas credenciales nuevas.

## Accesos

| Servicio | URL / Conexión | Credenciales |
|---|---|---|
| APEX Internal Admin | http://localhost:8181/ords/apex_admin | `INTERNAL` / `ADMIN` / `${APEX_ADMIN_PWD}` |
| APEX (workspaces de dev) | http://localhost:8181/ords/apex | el workspace que crees |
| ORDS landing | http://localhost:8181/ords/ | — |
| Oracle DB (SQL*Net) | `localhost:1521/FREEPDB1` | `SYS as SYSDBA` / `SYSTEM` con `${ORACLE_PWD}` |
| EM Express | https://localhost:5500/em | `SYS` con `${ORACLE_PWD}` |

CDB se llama `FREE`; PDB se llama `FREEPDB1`. Para desarrollo APEX siempre conectate al PDB.

## Comandos útiles

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

# Apagar y BORRAR datos (cuidado — vuelve a cero, reinstala APEX)
docker compose down -v
Remove-Item -Recurse -Force apex-images
```

## Volúmenes

| Volumen | Contenido | Sobrevive a `down`? | Sobrevive a `down -v`? |
|---|---|---|---|
| `apex-oradata` (Docker named) | Datafiles de Oracle | sí | no |
| `apex-ords-config` (Docker named) | Config de ORDS | sí | no |
| `./apex-images` (bind mount) | Estáticos APEX (~600 MB) | sí | sí (es del host) |
| `./downloads` (bind) | apex-latest.zip | sí | sí |

## Troubleshooting

- **"the Oracle APEX files have not been loaded"** en el login → el dir `./apex-images` está vacío o ORDS no lo lee. Verificá `docker exec apex-ords ls /opt/oracle/apex/images | wc -l` (debería dar ~856). Si está vacío, copialo de la DB: `docker cp apex-db:/home/oracle/apex-install/apex/images ./apex-images` (solo si la DB se está instalando) o re-extraé el zip al host.

- **ORDS en restart loop con "synonym translation no longer valid"** → tenés synonyms huérfanos de una instalación previa de ORDS. Correr [sql/cleanup_ords_synonyms.sql](sql/cleanup_ords_synonyms.sql) y después recrear el container de ORDS.

- **ORDS en restart loop con "config directory empty"** → ORDS ya está instalado en la DB pero el volumen `apex-ords-config` está vacío. Correr [sql/uninstall_ords.sql](sql/uninstall_ords.sql) para hacer drop de los schemas y dejar que reinstale limpio.

- **Cambiar password del ADMIN de APEX** → editar `.env`, correr [sql/setup_apex_admin.sql](sql/setup_apex_admin.sql) con: `docker cp sql/setup_apex_admin.sql apex-db:/tmp/ && docker exec apex-db sqlplus -S sys/$env:ORACLE_PWD@localhost:1521/FREEPDB1 as sysdba @/tmp/setup_apex_admin.sql`

- **`ORA-24247: network access denied by access control list (ACL)`** al hacer un REST desde APEX o PL/SQL → falta otorgar ACL de red al schema. Editar el `DEFINE schema_name` en [sql/grant_network_acl.sql](sql/grant_network_acl.sql) y correr (en PowerShell, notar las comillas alrededor de `"@/tmp/..."`): `docker cp sql/grant_network_acl.sql apex-db:/tmp/ ; docker exec apex-db sqlplus -S "sys/$env:ORACLE_PWD@localhost:1521/FREEPDB1 as sysdba" "@/tmp/grant_network_acl.sql"`

## Notas

- APEX **no viene preinstalado** en la imagen `container-registry.oracle.com/database/free:latest`. El init script lo instala en el primer boot.
- ORDS se auto-instala contra la DB al primer arranque y persiste su config en el volumen `apex-ords-config`.
- Los archivos en `init-scripts/` se ejecutan **una sola vez**, en el primer boot de la DB. Si querés re-correrlos, hacé `docker compose down -v` (cuidado: borra todo).
