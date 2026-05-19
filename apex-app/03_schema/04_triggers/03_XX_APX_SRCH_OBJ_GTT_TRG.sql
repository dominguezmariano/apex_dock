create or replace trigger "XX_APX_SRCH_OBJ_GTT_TRG"
before
insert or update on "XX_APX_SRCH_OBJ_GTT"
for each row
begin
    if :new.id_srch is null then
        select XX_APX_SRCH_SEQ.nextval into :new.id_srch from sys.dual;
    end if;



end;
/

SHOW err

EXIT