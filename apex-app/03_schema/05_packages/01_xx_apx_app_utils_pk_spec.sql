create or replace PACKAGE xx_apx_app_utils_pk AUTHID DEFINER AS 
 
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

    procedure insert_debug(p_module   IN VARCHAR2,
                        p_message   IN VARCHAR2);
 
    /*============================================================================+ 
    |                                                                             | 
    | Public Function                                                             | 
    |    app_sets_prc                                                      | 
    |                                                                             | 
    | Description                                                                 | 
    |    setea la opcion no proxy para llamado a RestFull services y el Auth      | 
    |                                                                             | 
    | Parameters                                                                  | 
    |    p_ambiente   IN  VARCHAR2: Ambiente de ejecucion                         | 
    +============================================================================*/ 
    PROCEDURE app_sets_prc (p_ambiente    IN Varchar2); 
 
    /*============================================================================+ 
    |                                                                             | 
    | Public Function                                                             | 
    |    xx_apx_app_admin_prof_fn                                                 | 
    |                                                                             | 
    | Description                                                                 | 
    |    devuelve el nivel de acceso para el usuario interno y los menues visibles| 
    |                                                                             | 
    | Parameters                                                                  | 
    |    p_current_user_id   IN  NUMBER: Ambiente de ejecucion                         | 
    +============================================================================*/ 
    FUNCTION app_admin_prof_fn(p_current_user_id IN NUMBER) RETURN BOOLEAN; 
 
 
    FUNCTION get_sentence ( p_current_user_id   IN  NUMBER,  
                          p_current_session_id  IN  NUMBER
                          --abr2026
                          ,p_ambient            IN  VARCHAR2
                          ,p_desc_pkg           IN  VARCHAR2
                          ,x_pkg                OUT NUMBER
                          --fin abr2026
                          ) RETURN VARCHAR2; 
 
END xx_apx_app_utils_pk;
/

SHOW err

EXIT