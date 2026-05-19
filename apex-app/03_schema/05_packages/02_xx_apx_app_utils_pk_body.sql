create or replace PACKAGE BODY xx_apx_app_utils_pk IS 
    g_user_id   NUMBER := APEX_UTIL.GET_CURRENT_USER_ID;
    g_user_name VARCHAR2(255) := APEX_UTIL.GET_USERNAME(g_user_id);
    /*============================================================================+ 
    |    Copyright (c) 2025 Despegar Argentina, Buenos Aires                      | 
    |                         All rights reserved.                                | 
    +=============================================================================+ 
    | FILENAME                                                                    | 
    |    xx_apx_olt_utils_pk.pkb                                                  | 
    |                                                                             | 
    | DESCRIPTION                                                                 | 
    |     paquete de utilidades internas de aplicacion Oracle Ldt Tool            | 
    |                                                                             | 
    | LANGUAGE                                                                    | 
    |    PL/SQL                                                                   | 
    |                                                                             | 
    | PRODUCT                                                                     | 
    |    Oracle Apex                                                              | 
    |                                                                             | 
    | HISTORY                                                                     | 
    |    JUN-25  mariano.dominguez          Created                               | 
    |                                                                             | 
    |                                                                             | 
    +============================================================================*/ 


    /*============================================================================+ 
    |                                                                             | 
    | Public Procedure                                                            | 
    |    insert_debug                                                             | 
    |                                                                             | 
    | Description                                                                 | 
    |    Inserta un registro log y depuracion                                      | 
    |                                                                             | 
    | Parameters                                                                  | 
    |    p_module   IN  VARCHAR2: Modulo de ejecucion                              | 
    |    p_message  IN  VARCHAR2: Mensaje de log                                  | 
    +============================================================================*/ 
    PROCEDURE insert_debug( p_module    IN VARCHAR2,
                            p_message   IN VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;

    BEGIN
        INSERT INTO XX_APX_DEBUG (  MODULO,
                                    MESSAGE,
                                    CREATED_BY,
                                    CREATION_DATE,
                                    USER_ID,
                                    USER_NAME)
                        VALUES (    p_module,
                                    p_message,
                                    'APEX',
                                    sysdate,
                                    g_user_id,
                                    g_user_name
                                    );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END insert_debug;
 
 
    /*============================================================================+ 
    |                                                                             | 
    | Public Procedure                                                            | 
    |    app_sets_prc                                                             | 
    |                                                                             | 
    | Description                                                                 | 
    |    setea la opcion no proxy para llamado a RestFull services y el Auth      | 
    |                                                                             | 
    | Parameters                                                                  | 
    |    p_ambiente   IN  VARCHAR2: Ambiente de ejecucion                         | 
    +============================================================================*/ 
    PROCEDURE app_sets_prc (p_ambiente    IN Varchar2) as 
        l_bearer    VARCHAR2(1000); 
    BEGIN 
        --global proxy setting 
        UTL_HTTP.SET_PROXY (proxy=>'', 
                            no_proxy_domains=>'despegar.com'); 

        --request headers para auth 
        IF p_ambiente IS NOT NULL THEN 
            SELECT  auth_ambient 
            INTO    l_bearer 
            FROM    xx_apx_ambients 
            WHERE   cod_ambient = p_ambiente; 

            apex_web_service.set_request_headers(   p_name_01 => 'Authorization', 
                                                    p_value_01 => l_bearer);      --ejemplo 'Basic TERUX0FQUF9SRVNUX0FVVEg6VWFdWmMqJjc1MkJo' ); 
        END IF; 

    END app_sets_prc; 
 
    /*============================================================================+ 
    |                                                                             | 
    | Public Function                                                             | 
    |    app_admin_prof_fn                                                        | 
    |                                                                             | 
    | Description                                                                 | 
    |    devuelve el nivel de acceso para el usuario interno y los menues visibles| 
    |                                                                             | 
    | Parameters                                                                  | 
    |    p_current_user_id   IN  NUMBER: ID del usuario actual                    | 
    +============================================================================*/ 

    FUNCTION app_admin_prof_fn(p_current_user_id IN NUMBER) RETURN BOOLEAN IS 
        l_exists number:=0; 
    BEGIN 
        --CAMBIOS AL 08/07/2025 
        -- YA NO UTILIZA CONFIGURACION CUSTOM DE USUARIOS, USA LA DEL WORKSPACE 
        -- VERIFICA EN apex_workspace_apex_users SI EL USUARIO ES ADMIN O DEV 
        -- Y SI LA CUENTA NO ESTA LOCKEADA 

        /*SELECT  1 
        INTO    l_exists 
        FROM    xx_apx_app_user_rol 
        WHERE   app_username = APEX_UTIL.GET_USERNAME(p_current_user_id)   --APEX_UTIL.GET_CURRENT_USER_ID) 
        AND     app_user_active = 'Y' 
        AND     app_user_role = 'ADMIN'; */ 

        SELECT  1 
        INTO    l_exists 
        FROM    apex_workspace_apex_users 
        where   user_name =APEX_UTIL.GET_USERNAME(p_current_user_id) 
        AND     (UPPER(is_admin) = 'YES' 
                OR UPPER(IS_APPLICATION_DEVELOPER) = 'YES') 
        AND     UPPER(account_locked) = 'NO'; 

        IF l_exists != 0 THEN 
            RETURN true; 
        ELSE 
            RETURN false; 
        END IF; 

    EXCEPTION 
        WHEN OTHERS THEN 
            RETURN false; 
    END app_admin_prof_fn; 
    
    /*============================================================================+ 
    |                                                                             | 
    | Public Function                                                             | 
    |    send_sentence_to_ebs                                                     | 
    |                                                                             | 
    | Description                                                                 | 
    |    envia una sentencia a EBS y maneja los errores                           | 
    |                                                                             | 
    | Parameters                                                                  | 
    |    p_id_pkg        IN  NUMBER: ID del paquete                               | 
    |    p_user_id       IN  NUMBER: ID del usuario                               | 
    |    p_req_ambient   IN  VARCHAR2: Ambiente de ejecucion                      | 
    |    x_error         OUT VARCHAR2: Mensaje de error                           | 
    +============================================================================*/ 
    ------------------------------------------------------------------------- 
    --Cambios abr2026
    PROCEDURE send_sentence_to_ebs (p_id_pkg        IN  NUMBER,
                                    p_user_id       IN  NUMBER,
                                    p_req_ambient   IN  VARCHAR2,
                                    x_error         OUT VARCHAR2) IS
        l_count_last_rec    NUMBER := 0;
        l_count             NUMBER := 0;
        l_last_flag         VARCHAR2(1) := 'N';
        l_amb_url	        VARCHAR2(1000) := NULL;
        l_bearer            VARCHAR2(1000);
        l_errors            VARCHAR2(32000):=NULL;
        l_sequence          VARCHAR2(20) := 'send_sentence_to_ebs';
        l_step              NUMBER:=0;
        l_modulo	        VARCHAR2(500) :=  'olt/rest/ebs/fnd/requestFiles/?pApxIdSentence=';
        l_url               VARCHAR2(2000) := NULL;
        l_data              CLOB;
        
        NO_AMBIENT          EXCEPTION;
        NO_MAKE_REST_REQ    EXCEPTION;
    BEGIN
        insert_debug(l_sequence,'Inicio');
                        
        BEGIN
            SELECT  COUNT(1)
            INTO    l_count_last_rec
            FROM    XX_APX_SENTENCES_BY_REQUEST
            WHERE   ID_PACKAGE  =   p_id_pkg
            AND     USER_ID     =   p_user_id;
        EXCEPTION
            WHEN OTHERS THEN
                l_count_last_rec := 0;
        END;

        insert_debug(l_sequence,'Buscando ambiente y bearer token para llamado a REST');
        --llamado a rest
        --datos del ambiente 
        BEGIN
            select  url_ambient, AUTH_AMBIENT
	        into    l_amb_url, l_bearer
	        from    xx_apx_ambients
	        where   cod_ambient = p_req_ambient;
        EXCEPTION
            WHEN OTHERS THEN
                l_errors:=l_sequence||' Error Buscando URL Ambiente para '||nvl(p_req_ambient,'NULL')||', '||sqlerrm;
                insert_debug(l_sequence,'Error Buscando ambiente y bearer token para llamado a REST'||l_errors);
                raise NO_AMBIENT;            
        END;
        --insert_debug(l_sequence,'l_amb_url '||l_amb_url||' l_bearer '||l_bearer);

        IF l_count_last_rec != 0 THEN
            FOR X IN (  SELECT  *
                        FROM    XX_APX_SENTENCES_BY_REQUEST
                        WHERE   ID_PACKAGE  =   p_id_pkg
                        AND     USER_ID     =   p_user_id
                        ORDER BY ID_SENTENCE, SEQUENCE ASC) LOOP
                
                l_count := l_count +1;
                
                if l_count= l_count_last_rec  then
                    l_last_flag := 'Y';
                end if;
                
                --insert_debug(l_sequence,'l_count '||l_count||' l_last_flag '||l_last_flag);
                
                BEGIN
                    xx_apx_app_utils_pk.app_sets_prc(p_ambiente => p_req_ambient );
                EXCEPTION
                    WHEN OTHERS THEN
                        l_errors:=l_sequence||'Error seteando Ambiente para '||nvl(p_req_ambient,'NULL')||', '||sqlerrm;
                        insert_debug(l_sequence,l_errors);
                        raise NO_AMBIENT;  
                END;
                --UPPER(replace(:P7_OBJECT_NAME,' ','%20'))
                --Armo URL Rest  
                l_url := l_amb_url||l_modulo||''||x.id_sentence
                                                ||'&pApxIdPackage='||x.ID_PACKAGE
                                                ||'&pApxUserId='||x.USER_ID
                                                ||'&pApxUserName='||x.USER_NAME
                                                ||'&pApxObjCode='||x.OBJ_CODE   
                                                ||'&pApxIdSel='||x.ID_SEL
                                                ||'&pApxFndSentence='||replace(x.FND_SENTENCE,' ','%20')
                                                ||'&pApxSequence='||x.SEQUENCE
                                                ||'&pApxExec='||x.EXECUTABLE
                                                ||'&pApxLast='||l_last_flag
                                                ||'&pEbsUser='||x.EBS_USER
                                                ||'';
        
                insert_debug(l_sequence,'REST url: '||l_url);

                BEGIN
                    l_data := APEX_WEB_SERVICE.make_rest_request(   p_url => l_url,
                													p_http_method => 'GET'
                												);
                EXCEPTION
                    WHEN OTHERS THEN
                        --:P7_LOG := :P7_LOG||' - EXCEpTION pre l_data  '||SQLERRM;
                        l_errors := 'Error en llamado a RestFull Service, '||SQLERRM;
                        insert_debug(l_sequence,l_errors);
                        raise NO_MAKE_REST_REQ;
                END;
              
                --insert_debug(l_sequence,'l_data '||l_data);

            END LOOP;
        END IF;

    EXCEPTION
        when NO_MAKE_REST_REQ then
            insert_debug(l_sequence,'Error NO_MAKE_REST_REQ: '||l_errors);
            apex_error.add_error(
                            p_message           => l_errors,
                            p_display_location  => apex_error.c_inline_in_notification
                            );
            x_error := l_errors;
        WHEN NO_AMBIENT THEN
            insert_debug(l_sequence,'Error NO_AMBIENT: '||l_errors);
            apex_error.add_error(
                            p_message           => l_errors,
                            p_display_location  => apex_error.c_inline_in_notification
                            );
            x_error := l_errors;
        WHEN OTHERS THEN 
            insert_debug(l_sequence,'Error OTHERS: '||SQLERRM);
            apex_error.add_error(
                            p_message           => 'send_sentence_to_ebs Errores: '||SQLERRM,
                            p_display_location  => apex_error.c_inline_in_notification
                            );
            x_error := 'send_sentence_to_ebs Errores: '||SQLERRM; 
    END send_sentence_to_ebs;

    /*============================================================================+ 
    |                                                                             | 
    | Public Function                                                             | 
    |    insert_sentence                                                          | 
    |                                                                             | 
    | Description                                                                 | 
    |    inserta una sentencia en la base de datos y maneja los errores           | 
    |                                                                             | 
    | Parameters                                                                  | 
    |    p_pkg           IN  NUMBER: ID del paquete                               | 
    |    p_user_id       IN  NUMBER: ID del usuario                               | 
    |    p_user_name     IN  VARCHAR2: Nombre del usuario                         | 
    |    p_obj_code      IN  VARCHAR2: Código del objeto                           | 
    |    p_id_Sel        IN  NUMBER: ID de selección                               | 
    |    p_sentence      IN  VARCHAR2: Sentencia a insertar                        | 
    |    p_seq           IN  NUMBER: Secuencia                                     | 
    |    p_req_ambient   IN  VARCHAR2: Ambiente de ejecución                      | 
    |    p_exec          IN  VARCHAR2: Ejecutable                                  | 
    |    x_error         OUT VARCHAR2: Mensaje de error                           | 
    +============================================================================*/ 
    PROCEDURE insert_sentence ( p_pkg               IN  NUMBER,
                                p_user_id           IN  NUMBER,
                                p_user_name         IN  VARCHAR2,
                                p_obj_code          IN  VARCHAR2,
                                p_id_Sel            IN  NUMBER,
                                p_sentence          IN  VARCHAR2,
                                p_seq               IN  NUMBER,
                                p_req_ambient       IN  VARCHAR2,
                                p_exec              IN  VARCHAR2,
                                p_pkg_description   IN  VARCHAR2,
                                p_ebs_user_name     IN  VARCHAR2,
                                x_error             OUT VARCHAR2) IS
         l_sequence          VARCHAR2(20) := 'insert_sentence';                            
    BEGIN
        insert_debug(l_sequence,'Insertando paquete: '||p_pkg||' Secuencia: '||p_seq);

        insert into XX_APX_SENTENCES_BY_REQUEST (ID_PACKAGE, 
                                                USER_ID, 
                                                USER_NAME, 
                                                OBJ_CODE, 
                                                ID_SEL, 
                                                FND_SENTENCE, 
                                                SEQUENCE,
                                                REQ_AMBIENT,
                                                executable,
                                                pkg_description,
                                                ebs_user)
                                        values
                                                (p_pkg,
                                                p_user_id,
                                                p_user_name,
                                                p_obj_code,
                                                p_id_Sel,
                                                p_sentence,
                                                p_seq,
                                                p_req_ambient,
                                                upper(p_exec),
                                                p_pkg_description,
                                                p_ebs_user_name
                                                ) ;

                                                COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            x_error := 'insert_sentence con errores '||SQLERRM;
            insert_debug(l_sequence,'Error '||x_error);
    END insert_sentence;


    --FIN Cambios abr2026
    -------------------------------------------------------------------------


    /*============================================================================+ 
    |                                                                             | 
    | Public Function                                                             | 
    |    get_sentence                                                          | 
    |                                                                             | 
    | Description                                                                 | 
    |    obtiene una sentencia de la base de datos y maneja los errores           | 
    |                                                                             | 
    | Parameters                                                                  | 
    |    p_current_user_id      IN  NUMBER: ID del usuario                        | 
    |    p_current_session_id   IN  NUMBER: ID de la sesión                       | 
    |    p_ambient              IN  VARCHAR2: Nombre del ambiente                 | 
    |    x_pkg                  OUT NUMBER: Numero de paquete generado            | 
    +============================================================================*/ 
    FUNCTION get_sentence ( p_current_user_id     IN  NUMBER, 
                            p_current_session_id  IN  NUMBER
                            --abr2026
                            ,p_ambient            IN  VARCHAR2
                            ,p_desc_pkg           IN  VARCHAR2
                            ,x_pkg                OUT NUMBER                            
                            --fin abr2026
                            ) RETURN VARCHAR2 IS 
        l_sentence      VARCHAR2(32000) := NULL; 
        --abr2026
        l_pkg           NUMBER:=0;
        l_username      VARCHAR2(1500);
        l_errores       VARCHAR2(20000) := NULL;
        l_sequence      VARCHAR2(20) := 'get_sentence';
        l_desc_pkg      VARCHAR2(255):=NULL;
        l_ebs_user_name VARCHAR2(200):=NULL;
        --FIN abr2026
    BEGIN 
        --abr2026
        l_pkg := XX_APX_PKG_SEQ.nextval;
        l_desc_pkg := p_desc_pkg;

        insert_debug(l_sequence,'Paquete generado: '||l_pkg);

        BEGIN
            l_username := APEX_UTIL.GET_USERNAME(p_userid => p_current_user_id);
        EXCEPTION
            WHEN OTHERS THEN
                l_username := 'ANONYMOUS';
        END;

        --BUSCO USURIO EBS EN DESCRIPCION
        BEGIN
            SELECT  description
            INTO    l_ebs_user_name
            FROM   apex_workspace_apex_users
            WHERE  user_name = l_username;
        EXCEPTION
            WHEN OTHERS THEN
                l_ebs_user_name := 'ANONYMOUS';
        END;
        --FIN abr2026

        FOR obj IN (SELECT  OBJ_CODE, OBJ_TYPE, OBJ_DESC, APP_SHORT_NAME, 
                            ADDITIONAl_1, ADDITIONAl_2, 
                            ADDITIONAl_3, ADDITIONAl_4, id_sel , app_id 
                    FROM    XX_APX_SEL_OBJ_GTT 
                    WHERE   USER_ID = p_current_user_id 
                    AND     SESSION_ID = p_current_session_id 
                    ORDER BY ID_SEL, OBJ_CODE, OBJ_TYPE) LOOP 

            insert_debug(l_sequence,'OBJ_TYPE '||obj.OBJ_TYPE);
            --IF obj.OBJ_TYPE = 'LOOKUPS' THEN 
            CASE obj.OBJ_CODE 
                WHEN 'LOOKUPS' THEN 
                    FOR I IN (SELECT  rtrim(executable||' '||parameter1||' '||parameter2||' '||parameter3||' '|| 
                                        replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '||parameter5||' '|| 
                                        replace(replace(parameter6,'%VIEW_APPSNAME%',obj.APP_SHORT_NAME),'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                        parameter7||' '||parameter8||' '||parameter9||' '||parameter10)||--';'|| 
                                        chr(10)   sentencia
                                        --abr2026 
                                        ,sequence
                                        ,executable
                                        --FIN abr2026
                                FROM    xx_apx_fnd_params 
                                WHERE   line_type_code = obj.OBJ_CODE --'LOOKUPS' 
                                AND     enabled = 'Y' 
                                ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026
                    END LOOP; 
    
                WHEN 'CONCPROG' THEN 
                    FOR I IN (SELECT  rtrim(executable||' '||parameter1||' '||parameter2||' '||parameter3||' '|| 
                                    replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '||parameter5||' '|| 
                                    replace(replace(parameter6,'%APPL_SHORT_NAME%',obj.APP_SHORT_NAME),'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    parameter7||' '||parameter8||' '||parameter9||' '||parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params 
                            WHERE   line_type_code = obj.OBJ_CODE --'CONCPROG' 
                            AND     enabled = 'Y' 
                            ORDER BY sequence ) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                        --FIN abr2026
                    END LOOP; 
    
                WHEN 'RESPONSIBILITIES' THEN 
                    FOR I IN (SELECT  rtrim(executable||' '||parameter1||' '||parameter2||' '||parameter3||' '|| 
                                    replace(replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE),' ','')||' '|| 
                                    replace(parameter5,'%OBJECT_NAME%',obj.OBJ_TYPE) ||' '||parameter6||' '|| 
                                    parameter7||' '||parameter8||' '||parameter9||' '||parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params 
                            WHERE   line_type_code = obj.OBJ_CODE --'RESPONSIBILITIES' 
                            AND     enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026
                    END LOOP; 
    
                WHEN 'ALERTS' THEN 
                    FOR I IN (SELECT  rtrim(executable||' '||parameter1||' '||parameter2||' '||parameter3||' '|| 
                                    --replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE)
                                    replace(replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE),' ','_')
                                    ||' '||parameter5||' '|| 
                                    replace(replace(parameter6,'%APPL_SHORT_NAME%',obj.APP_SHORT_NAME),'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    parameter7||' '||parameter8||' '||parameter9||' '||parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params 
                            WHERE   line_type_code = obj.OBJ_CODE --'ALERTS' 
                            AND     enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026
                    END LOOP; 
    
                WHEN 'VALUESETS' THEN 
                    FOR I IN (SELECT  rtrim(executable||' '||parameter1||' '||parameter2||' '||parameter3||' '|| 
                                    replace(parameter4,'%OBJECT_NAME%', obj.OBJ_TYPE )||' '||parameter5||' '|| 
                                    replace(parameter6,'%OBJECT_NAME%', obj.OBJ_TYPE)||' '|| 
                                    parameter7||' '||parameter8||' '||parameter9||' '||parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params 
                            WHERE   line_type_code = obj.OBJ_CODE --'VALUESETS' 
                            AND     enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026
                    END LOOP; 
    
                WHEN 'MENU' THEN 
                    FOR I IN (SELECT  rtrim(executable||' '||parameter1||' '||parameter2||' '||parameter3||' '|| 
                                    replace(replace(parameter4,'%OBJECT_NAME%', obj.OBJ_TYPE ),' ','_')||' '||parameter5||' '|| 
                                    replace(parameter6,'%OBJECT_NAME%', obj.OBJ_TYPE)||' '|| 
                                    parameter7||' '||parameter8||' '||parameter9||' '||parameter10)||--';'|| 
                                    chr(10)   sentencia
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026 
                            FROM    xx_apx_fnd_params 
                            WHERE   line_type_code = obj.OBJ_CODE --'MENU' 
                            AND     enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026 
                    END LOOP; 
    
                WHEN 'DESCFLEXS' THEN 
                    FOR I IN (SELECT  rtrim(executable||' '||parameter1||' '||parameter2||' '||parameter3||' '|| 
                                    --replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    replace(replace(replace(replace(parameter4,'%APPL_SHORT_NAME%',obj.app_short_name),'%APPL_ID%',obj.app_id),'%OBJECT_NAME%',obj.OBJ_TYPE), 
                                            '%SEQUENCE_NUM%',replace(obj.additional_4,'.','_'))||' '|| 
                                    parameter5||' '|| 
                                    replace(replace(parameter6,'%APPL_SHORT_NAME%',obj.APP_SHORT_NAME),'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    parameter7||' '||parameter8||' '||parameter9||' '||parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params 
                            WHERE   line_type_code = obj.OBJ_CODE --'DESCFLEXS' 
                            AND     enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026 
                    END LOOP; 
    
                WHEN 'FNDMSGS' THEN 
                    FOR I IN (SELECT  rtrim(executable||' '||parameter1||' '||parameter2||' '||parameter3||' '|| 
                                    replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '||parameter5||' '|| 
                                    replace(replace(parameter6,'%APPL_SHORT_NAME%',obj.APP_SHORT_NAME),'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    parameter7||' '||parameter8||' '||parameter9||' '||parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params 
                            WHERE   line_type_code = obj.OBJ_CODE --'FNDMSGS' 
                            AND     enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026 
                    END LOOP; 
    
                WHEN 'FORMPERS' THEN 
                    FOR I IN (SELECT  rtrim(executable||' '||parameter1||' '||parameter2||' '||parameter3||' '|| 
                                    replace(replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE),'%SEQUENCE_NUM%',replace(obj.additional_1,'.','_'))||' '|| 
                                    replace(parameter5,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    replace(replace(parameter6,'%XX_SEQUENCE_NUM%',obj.additional_1),'%FORM_NAME%',obj.additional_2)||' '|| 
                                    parameter7||' '||parameter8||' '||parameter9||' '||parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params 
                            WHERE   line_type_code = obj.OBJ_CODE --'FORMPERS' 
                            AND     enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026
                    END LOOP;  -- 
    
                WHEN 'MENU_ENTRY' THEN 
                    FOR I IN (SELECT  rtrim(xa.executable||' '||xa.parameter1||' '||xa.parameter2||' '||xa.parameter3||' '|| 
                                    --replace(replace(xa.parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE),'%SEQUENCE_NUM%',replace(obj.additional_4,'.','_'))||' '|| 
                                    replace(replace(replace(xa.parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE),'%SEQUENCE_NUM%',replace(obj.additional_4,'.','_')),' ','_')||' '|| 
                                    replace(xa.parameter5,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    replace(replace(xa.parameter6,'%FUNCTION_NAME%',obj.additional_2),'%SUB_MENU_NAME%',obj.additional_3)||' '|| 
                                    xa.parameter7||' '||xa.parameter8||' '||xa.parameter9||' '||xa.parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params xa 
                            WHERE   xa.line_type_code = obj.OBJ_CODE --'MENU_ENTRY' 
                            AND     xa.enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026  
    
                    END LOOP; 
    
                WHEN 'DESCFLEXS_CTXT_ATT' THEN 
                    FOR I IN (SELECT  rtrim(xa.executable||' '||xa.parameter1||' '||xa.parameter2||' '||xa.parameter3||' '|| 
                                    --replace(replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE),'%SEQUENCE_NUM%',REPLACE(obj.OBJ_DESC,' ','_')||'_'||replace(obj.additional_4,'.','_'))||' '|| 
                                    replace(replace(replace(replace(parameter4,'%APPL_SHORT_NAME%',obj.app_short_name),'%APPL_ID%',obj.app_id),'%OBJECT_NAME%',obj.OBJ_TYPE), 
                                            '%SEQUENCE_NUM%',replace(obj.additional_4,'.','_'))||' '|| 
                                    replace(xa.parameter5,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    replace(replace(parameter6,'%APPL_SHORT_NAME%',obj.APP_SHORT_NAME),'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    replace(xa.parameter7,'%CONTEXT_CODE%',obj.OBJ_DESC)||' '|| 
                                    replace(xa.parameter8,'%END_USER_COLNAME%',obj.additional_2)||' '|| 
                                    replace(xa.parameter9,'%APPL_COL_NAME%',obj.additional_3)||' '||xa.parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params xa 
                            WHERE   xa.line_type_code = obj.OBJ_CODE --'DESCFLEXS_CTXT_ATT' 
                            AND     xa.enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026 
                    END LOOP; 
    
                WHEN 'DESCFLEXS_CTXT' THEN 
                    FOR I IN (SELECT   rtrim(xa.executable||' '||xa.parameter1||' '||xa.parameter2||' '||xa.parameter3||' '|| 
                                    -- replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    --replace( 
                                        replace(replace(replace(parameter4,'%APPL_SHORT_NAME%',obj.app_short_name),'%APPL_ID%',obj.app_id),'%OBJECT_NAME%',obj.OBJ_TYPE) 
                                            --'%SEQUENCE_NUM%',replace(obj.additional_4,'.','_')) 
                                            ||' '|| 
                                    replace(xa.parameter5,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    replace(replace(parameter6,'%APPL_SHORT_NAME%',obj.APP_SHORT_NAME),'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    replace(xa.parameter7,'%CONTEXT_CODE%',obj.OBJ_DESC)||' '|| 
                                    xa.parameter8||' '||xa.parameter9||' '||xa.parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params xa 
                            WHERE   xa.line_type_code = obj.OBJ_CODE --'DESCFLEXS_CTXT' 
                            AND     xa.enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026 
                    END LOOP; 
    
                WHEN 'PROFILES' THEN 
                    FOR I IN (SELECT   rtrim(xa.executable||' '||xa.parameter1||' '||xa.parameter2||' '||xa.parameter3||' '|| 
                                    replace(parameter4,'%OBJECT_NAME%',(obj.OBJ_TYPE||'_'||obj.id_sel))||' '|| 
                                    replace(xa.parameter5,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    replace(replace(parameter6,'%APPL_SHORT_NAME%',obj.APP_SHORT_NAME),'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    replace(replace(replace(xa.parameter7,'%LEV%',obj.additional_1),'%LEV_NAME%',obj.additional_2),'%PROFILE_VALUES%',obj.additional_3)||' '|| 
                                    xa.parameter8||' '||xa.parameter9||' '||xa.parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params xa 
                            WHERE   xa.line_type_code = obj.OBJ_CODE --'PROFILES' 
                            AND     xa.enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026  
                    END LOOP; 
                        
                WHEN 'REQUESTGRP' THEN 
                    FOR I IN (SELECT  rtrim( xa.executable||' '||xa.parameter1||' '||xa.parameter2||' '||xa.parameter3||' '|| 
                                    replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    xa.parameter5||' '|| 
                                    replace(xa.parameter6,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    xa.parameter7||' '||xa.parameter8||' '||xa.parameter9||' '||xa.parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params xa 
                            WHERE   xa.line_type_code = obj.OBJ_CODE --'REQUESTGRP' 
                            AND     xa.enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026 
                    END LOOP; 
                        
                WHEN 'REQUESTGRPU' THEN 
                    FOR I IN (SELECT  rtrim(xa.executable||' '||xa.parameter1||' '||xa.parameter2||' '||xa.parameter3||' '|| 
                                    replace(replace(replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE),'%SEQUENCE_NUM%',obj.id_sel),' ','_')||' '|| 
                                    xa.parameter5||' '|| 
                                    replace(xa.parameter6,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    replace(replace(parameter7,'%UNIT_TYPE%',obj.additional_1),'%UNIT_NAME%',obj.additional_2)||' '|| 
                                    xa.parameter8||' '||xa.parameter9||' '||xa.parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params xa 
                            WHERE   xa.line_type_code = obj.OBJ_CODE --'REQUESTGRPU' 
                            AND     xa.enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026                    
                    END LOOP; 
    
    
                WHEN 'FUNCTIONS' THEN 
                    FOR I IN (SELECT  rtrim(xa.executable||' '||xa.parameter1||' '||xa.parameter2||' '||xa.parameter3||' '|| 
                                    replace(xa.parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    xa.parameter5||' '|| 
                                    replace(replace(parameter6,'%APPL_SHORT_NAME%',obj.APP_SHORT_NAME),'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    xa.parameter7||' '||xa.parameter8||' '||xa.parameter9||' '||xa.parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params xa 
                            WHERE   xa.line_type_code = obj.OBJ_CODE --'FUNCTIONS' 
                            AND     xa.enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026                    
                    END LOOP; 
    
                WHEN 'FORMS' THEN 
                    FOR I IN (SELECT  rtrim(executable||' '||parameter1||' '||parameter2||' '||parameter3||' '|| 
                                    replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '||parameter5||' '|| 
                                    replace(replace(parameter6,'%APPL_SHORT_NAME%',obj.APP_SHORT_NAME),'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    parameter7||' '||parameter8||' '||parameter9||' '||parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params 
                            WHERE   line_type_code = obj.OBJ_CODE --'FORMS' 
                            AND     enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026  
                    END LOOP; 
    
                WHEN 'KEYFLEXS' THEN 
                    FOR I IN (SELECT  rtrim(executable||' '||parameter1||' '||parameter2||' '||parameter3||' '|| 
                                    replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    replace(replace(parameter5,'%APPL_SHORT_NAME%',obj.APP_SHORT_NAME),'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    parameter6||' '|| 
                                    parameter7||' '||parameter8||' '||parameter9||' '||parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params 
                            WHERE   line_type_code =  obj.OBJ_CODE --'KEYFLEXS' 
                            AND     enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026  
                    END LOOP; 
    
                WHEN 'XDOTMLP' THEN 
                    FOR I IN (SELECT  rtrim(executable||' '||parameter1||' '||parameter2||' '||parameter3||' '|| 
                                    replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    parameter5||' '|| 
                                    replace(replace(parameter6,'%APPL_SHORT_NAME%',obj.APP_SHORT_NAME),'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    replace(replace(parameter7,'%TMPL_APP_SHORT_NAME%',''),'%TEMPLATE_CODE%','') 
                                    ||' '||parameter8||' '||parameter9||' '||parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params 
                            WHERE   line_type_code =  obj.OBJ_CODE --'KEYFLEXS' 
                            AND     enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026 
                    END LOOP; 
    
                WHEN 'REQSETLNK' THEN 
                    FOR I IN (SELECT  rtrim(executable||' '||parameter1||' '||parameter2||' '||parameter3||' '|| 
                                    replace(parameter4,'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    parameter5||' '|| 
                                    replace(replace(parameter6,'%APPL_SHORT_NAME%',obj.APP_SHORT_NAME),'%OBJECT_NAME%',obj.OBJ_TYPE)||' '|| 
                                    parameter7||' '||parameter8||' '||parameter9||' '||parameter10)||--';'|| 
                                    chr(10)   sentencia 
                                    --abr2026 
                                    ,sequence
                                    ,executable
                                    --FIN abr2026
                            FROM    xx_apx_fnd_params 
                            WHERE   line_type_code =  obj.OBJ_CODE --'KEYFLEXS' 
                            AND     enabled = 'Y' 
                            ORDER BY sequence) LOOP 
                        l_sentence := l_sentence ||I.sentencia; 
                        --abr2026
                        IF UPPER(i.executable) != 'EXPORT' THEN
                        
                            BEGIN
                                insert_sentence (p_pkg              =>  l_pkg,
                                                p_user_id           =>  p_current_user_id,
                                                p_user_name         =>  l_username,
                                                p_obj_code          =>  obj.OBJ_CODE,
                                                p_id_Sel            =>  OBJ.id_sel,
                                                p_sentence          =>  I.sentencia,
                                                p_seq               =>  I.sequence,
                                                p_req_ambient       =>  p_ambient,
                                                p_exec              =>  i.executable,
                                                p_pkg_description   =>  p_desc_pkg,
                                                p_ebs_user_name     =>  l_ebs_user_name,
                                                x_error             =>  l_errores);
                            
                            
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        l_sentence := l_sentence ||' CON ERRORES '||l_errores;
                            END;
                        END IF;
                    --FIN abr2026 
                    END LOOP; 
            ELSE 
                RETURN obj.OBJ_CODE||'-'||obj.OBJ_TYPE; --'NADA'; 
            END CASE; 
    
        END LOOP; --- FOR obj IN (SELE 
    
        --generar clob 
        -- enviar clob 
    
        IF l_sentence IS NOT NULL THEN 
            --abr2026
            --llamo funcion de envio al api
            --send_sentence_to_ebs;
            insert_debug(l_sequence,'Llamando a send_sentence_to_ebs ');
            BEGIN
                send_sentence_to_ebs   (p_id_pkg        =>  l_pkg,
                                        p_user_id       =>  p_current_user_id,
                                        p_req_ambient   =>  p_ambient,
                                        x_error         =>  l_errores);
            EXCEPTION
                WHEN OTHERS THEN
                    insert_debug(l_sequence,'ERROR llamando a send_sentence_to_ebs '||l_errores);                          
            END;
            

        /*    if l_pkg is not null then
            apex_application.g_print_success_message := 'Sentencia generada exitosamente. Nro de paquete: ' || l_pkg;
        else
            apex_application.g_print_success_message := 'Sentencia generada exitosamente.';
        end if;*/
            x_pkg := l_pkg;
            --fin abr2026
            RETURN 'Nro de pkg generado: '||l_pkg||chr(10)||'Si desea ejecutar la generacion de forma manual en gitHub, puede utilizar la siguiente sentencia: '||chr(10)||l_sentence; 
        ELSE 
            RETURN ''; 
        END IF; 
    EXCEPTION 
        WHEN OTHERS THEN 
            RETURN ''; 
    END get_sentence; 
 
 
END xx_apx_app_utils_pk;
/
/

SHOW err

EXIT