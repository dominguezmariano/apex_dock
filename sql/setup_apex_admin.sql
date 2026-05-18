SET SERVEROUTPUT ON
ALTER SESSION SET CONTAINER = FREEPDB1;

DECLARE
  l_user_id NUMBER;
BEGIN
  APEX_UTIL.set_workspace(p_workspace => 'INTERNAL');

  BEGIN
    l_user_id := APEX_UTIL.get_user_id('ADMIN');
  EXCEPTION
    WHEN OTHERS THEN l_user_id := NULL;
  END;

  IF l_user_id IS NULL THEN
    APEX_UTIL.create_user(
      p_user_name                    => 'ADMIN',
      p_email_address                => 'mariano.dominguez@despegar.com',
      p_web_password                 => 'Welcome_2026',
      p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
      p_change_password_on_first_use => 'N');
    DBMS_OUTPUT.PUT_LINE('Created ADMIN user.');
  ELSE
    APEX_UTIL.edit_user(
      p_user_id                      => l_user_id,
      p_user_name                    => 'ADMIN',
      p_web_password                 => 'Welcome_2026',
      p_new_password                 => 'Welcome_2026',
      p_change_password_on_first_use => 'N');
    DBMS_OUTPUT.PUT_LINE('Updated ADMIN password.');
  END IF;

  COMMIT;
END;
/

ALTER USER APEX_PUBLIC_USER IDENTIFIED BY "OracleApex_2026" ACCOUNT UNLOCK;

EXIT;
