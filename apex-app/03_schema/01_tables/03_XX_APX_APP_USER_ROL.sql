 CREATE TABLE "XX_APX_APP_USER_ROL" 
   (	"APP_USER_ID" NUMBER NOT NULL ENABLE, 
	"APP_USERNAME" VARCHAR2(400 CHAR) NOT NULL ENABLE, 
	"APP_USER_ROLE" VARCHAR2(10 CHAR) NOT NULL ENABLE, 
	"APP_USER_ACTIVE" VARCHAR2(2 CHAR) NOT NULL ENABLE, 
	"CREATED_BY" NUMBER(25,0), 
	"CREATION_DATE" DATE, 
	"LAST_UPDATED_BY" NUMBER(25,0), 
	"LAST_UPDATE_DATE" DATE, 
	 CONSTRAINT "XX_APX_APP_USER_ROL_PK" PRIMARY KEY ("APP_USER_ID", "APP_USERNAME")
  USING INDEX  ENABLE
   ) ;


--  CREATE OR REPLACE EDITIONABLE TRIGGER "XX_APX_APP_USER_ROL_TRG" 
--before
--insert or update on "XX_APX_APP_USER_ROL"
--for each row
--begin
--    if :new.app_user_id is null then
--        select xx_apx_user_app_seq.nextval into :new.app_user_id from sys.dual;
--    end if;
--
--    if :new.CREATED_BY is null then
--        select APEX_UTIL.GET_CURRENT_USER_ID into :new.CREATED_BY from dual;
--    end if;
--
--    if :new.CREATION_DATE is null then
--        select sysdate into :new.CREATION_DATE from dual;
--    end if;
--
--    if (:new.LAST_UPDATED_BY is null) or (:new.LAST_UPDATED_BY != :old.LAST_UPDATED_BY) then
--        select APEX_UTIL.GET_CURRENT_USER_ID into :new.LAST_UPDATED_BY from dual;
--    end if;
--
--    if (:new.LAST_UPDATE_DATE is null) or (:new.LAST_UPDATE_DATE != :old.LAST_UPDATE_DATE) then
--        select sysdate into :new.LAST_UPDATE_DATE from dual;
--    end if;
--           
--end;
--/
--ALTER TRIGGER "XX_APX_APP_USER_ROL_TRG" ENABLE;
/
SHOW err

EXIT
  