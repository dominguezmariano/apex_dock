SET SERVEROUTPUT ON
ALTER SESSION SET CONTAINER = FREEPDB1;

-- Drop public synonyms that point to dropped ORDS schemas
DECLARE
  v_cnt PLS_INTEGER := 0;
BEGIN
  FOR r IN (
    SELECT s.synonym_name
    FROM dba_synonyms s
    WHERE s.owner = 'PUBLIC'
      AND s.table_owner IN ('ORDS_METADATA','ORDS_PUBLIC_USER','ORDS_PLSQL_GATEWAY')
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP PUBLIC SYNONYM "' || r.synonym_name || '"';
      v_cnt := v_cnt + 1;
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Could not drop synonym ' || r.synonym_name || ': ' || SQLERRM);
    END;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('Dropped ' || v_cnt || ' public synonyms.');
END;
/

-- Also drop any leftover roles created by ORDS install
DECLARE
  v_cnt PLS_INTEGER := 0;
BEGIN
  FOR r IN (
    SELECT role
    FROM dba_roles
    WHERE role IN ('ORDS_ADMINISTRATOR_ROLE','ORDS_RUNTIME_ROLE','ORDS_PLSQL_GATEWAY_ROLE')
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP ROLE "' || r.role || '"';
      v_cnt := v_cnt + 1;
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Could not drop role ' || r.role || ': ' || SQLERRM);
    END;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('Dropped ' || v_cnt || ' roles.');
END;
/

EXIT;
