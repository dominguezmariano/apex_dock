create or replace FUNCTION xx_apx_get_current_environment
RETURN VARCHAR2
IS
    v_environment VARCHAR2(200);
BEGIN
    -- Determinar ambiente basado en diferentes criterios
    IF UPPER(SYS_CONTEXT('USERENV', 'DB_NAME')) = 'FREEPDB1' THEN
        v_environment := '';
    ELSIF UPPER(SYS_CONTEXT('USERENV', 'DB_NAME')) = 'EBSUAT' THEN
        v_environment := '';
    ELSIF UPPER(SYS_CONTEXT('USERENV', 'DB_NAME'))  = 'EBST' THEN
        v_environment := 'Ejecutando aplicacion de TEST';
    ELSIF UPPER(SYS_CONTEXT('USERENV', 'DB_NAME')) = 'EBSD' THEN
        v_environment := 'Ejecutando aplicacion de DESARROLLO';
    ELSIF UPPER(SYS_CONTEXT('USERENV', 'DB_NAME')) = 'EBSTPF' THEN
        v_environment := 'Ejecutando aplicacion de TESTFIX';
    ELSE
        --v_environment := 'DESCONOCIDO';
        v_environment := 'Ejecutando aplicacion en '||UPPER(SYS_CONTEXT('USERENV', 'DB_NAME'));
    END IF;

    RETURN v_environment;
END xx_apx_get_current_environment;
/