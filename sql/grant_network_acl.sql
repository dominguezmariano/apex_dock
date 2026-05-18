-- Otorga permisos de red (ACL) para que APEX pueda hacer llamadas HTTP/HTTPS
-- desde PL/SQL (UTL_HTTP, APEX_WEB_SERVICE.MAKE_REST_REQUEST, etc).
--
-- Fix para: ORA-24247 network access denied by access control list (ACL)
--
-- IMPORTANTE: APEX necesita el ACL sobre TRES usuarios distintos, no solo
-- sobre el parsing schema. La call chain APEX_WEB_SERVICE.MAKE_REST_REQUEST
-- -> WWV_FLOW_WEB_SERVICES_INVOKER -> UTL_HTTP puede terminar ejecutandose
-- como cualquiera de ellos dependiendo de los AUTHID de los wrappers:
--   1. El parsing schema de la app          (parametrizable: DEFINE schema_name)
--   2. APEX_PUBLIC_USER                     (user con que ORDS conecta)
--   3. El schema interno de APEX            (APEX_XXXXXX, se detecta solo)
--
-- Notas adicionales:
-- - APEX crea durante la instalacion un ACL wildcard (host = '*') por lo que
--   tratar de crear un ACL para un host especifico choca con ese wildcard y
--   devuelve ORA-24244. Por eso por default este script otorga el ACE sobre
--   el wildcard '*', que es lo que APEX ya tiene armado.
-- - Ports en NULL = aplica a cualquier puerto.
--
-- Editar el DEFINE schema_name de abajo y correr (PowerShell):
--   docker cp sql/grant_network_acl.sql apex-db:/tmp/
--   docker exec apex-db sqlplus -S "sys/$env:ORACLE_PWD@localhost:1521/FREEPDB1 as sysdba" "@/tmp/grant_network_acl.sql"
-- (Notar las comillas alrededor de "@/tmp/..."; PowerShell parsea @ como splatting si va sin comillar.)

SET SERVEROUTPUT ON
ALTER SESSION SET CONTAINER = FREEPDB1;

-- ============================================================
-- Parametros: cambiar schema_name por el parsing schema de tu workspace APEX
-- ============================================================
DEFINE host        = '*'
DEFINE lower_port  = NULL
DEFINE upper_port  = NULL
DEFINE schema_name = 'XX_APEX_DOCKER'
-- ============================================================

DECLARE
  l_apex_schema   VARCHAR2(30);
  TYPE t_principals IS TABLE OF VARCHAR2(30);
  l_principals    t_principals;
BEGIN
  -- Detectar el schema interno de APEX (formato APEX_NNNNNN, el mas alto si hay varios)
  SELECT MAX(username) INTO l_apex_schema
  FROM   dba_users
  WHERE  REGEXP_LIKE(username, '^APEX_[0-9]{6}$');

  IF l_apex_schema IS NULL THEN
    RAISE_APPLICATION_ERROR(-20001, 'No se encontro schema interno de APEX (APEX_NNNNNN). Verificar que APEX este instalado.');
  END IF;

  l_principals := t_principals('&schema_name', 'APEX_PUBLIC_USER', l_apex_schema);

  FOR i IN 1..l_principals.COUNT LOOP
    BEGIN
      DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
        host       => '&host',
        lower_port => &lower_port,
        upper_port => &upper_port,
        ace        => xs$ace_type(
                        privilege_list => xs$name_list('connect', 'resolve'),
                        principal_name => l_principals(i),
                        principal_type => xs_acl.ptype_db
                      )
      );
      DBMS_OUTPUT.PUT_LINE('ACE otorgada a ' || l_principals(i));
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error al otorgar a ' || l_principals(i) || ': ' || SQLERRM);
    END;
  END LOOP;
  COMMIT;
END;
/

-- Verificacion: ACEs asignadas a los tres principals
PROMPT
PROMPT ACEs actuales:
SET LINESIZE 200
COLUMN host FORMAT a45
COLUMN principal FORMAT a25
COLUMN privilege FORMAT a15
SELECT host, lower_port, upper_port, principal, privilege, grant_type
FROM   dba_host_aces
WHERE  principal = '&schema_name'
   OR  principal = 'APEX_PUBLIC_USER'
   OR  REGEXP_LIKE(principal, '^APEX_[0-9]{6}$')
ORDER  BY principal, privilege;

EXIT;
