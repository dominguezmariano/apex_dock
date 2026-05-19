# apex-app

Contiene el workspace, la app APEX y todos los objetos de DB del schema parsing.
Al primer boot del container, [`init-scripts/02_install_app.sh`](../init-scripts/02_install_app.sh) instala todo automaticamente.

Si la carpeta esta vacia (o falta alguno de los archivos principales), el init script skipea silenciosamente — el stack funciona igual sin app precargada.

## Estructura

```
apex-app/
├── 01_workspace.sql         Export del workspace (apex_admin -> Manage Workspaces -> Export)
├── 02_app.sql               Export de la app (App Builder -> tu app -> Export -> SQL)
└── 03_schema/               Objetos DB del parsing schema (orden de instalacion: alfabetico)
    ├── 01_tables/           CREATE TABLE
    ├── 02_sequences/        CREATE SEQUENCE
    ├── 03_indexes/          CREATE INDEX
    ├── 04_triggers/         CREATE TRIGGER (terminar con / en linea sola)
    ├── 05_packages/         spec (.pks renombrado a .sql) antes que body (.pkb renombrado a .sql)
    ├── 06_functions/        CREATE FUNCTION (terminar con / en linea sola)
    └── 07_data/             INSERTs + COMMIT al final
```

## Orden de instalacion

El init script ejecuta en este orden:

1. **Crea parsing schema** (`XX_APEX_DOCKER`) si no existe, con los grants minimos
2. **Importa `01_workspace.sql`** — crea el workspace en APEX y asocia el parsing schema
3. **Importa `02_app.sql`** — instala la app dentro del workspace recien creado
4. **Ejecuta los .sql de `03_schema/`** en orden alfabetico de subcarpeta y nombre de archivo
5. **Otorga ACLs de red** para que la app pueda hacer REST calls

Por que el workspace y la app van antes que los objetos DB: APEX no valida la existencia de los objetos al importar la app (las referencias se resuelven en runtime). Asi evitamos chicken-and-egg con dependencias.

## Conventions para los archivos SQL

- **Extension uniforme:** todo `.sql` (renombrar `.tbl`, `.seq`, `.trg`, `.pks`, `.pkb`, `.fnc` a `.sql`).
- **Terminator de PL/SQL:** los objetos que contienen bloques PL/SQL (triggers, packages, functions) deben terminar con `/` en linea sola para que sqlplus los compile.
- **Numero al inicio del nombre:** mantiene el orden de instalacion. El init script los ejecuta alfabeticamente, asi que `01_*`, `02_*`, etc.
- **Idempotencia opcional:** si queres que un re-run no rompa, usar `CREATE OR REPLACE` donde aplique (packages, triggers, functions). Las tablas en cambio fallaran con ORA-00955 si ya existen — el init script skipea esos errores con `WHENEVER SQLERROR CONTINUE`.

## Como regenerar los exports

Cuando hagas cambios en la app o en el schema:

1. **Workspace export:** `/ords/apex_admin` → Manage Workspaces → Export Workspace → Download → reemplazar `01_workspace.sql`.
2. **App export:** App Builder → tu app → Export → SQL → Download → reemplazar `02_app.sql`.
3. **Schema objects:** generar DDL con `DBMS_METADATA.GET_DDL` o con SQL Developer "Cart" / "Database Export", reemplazar los archivos correspondientes en `03_schema/`.

Para que los cambios se apliquen en un container existente, hay que rehacer el primer boot:

```powershell
docker compose down -v        # cuidado: borra los datos de la DB tambien
docker compose up -d
```
