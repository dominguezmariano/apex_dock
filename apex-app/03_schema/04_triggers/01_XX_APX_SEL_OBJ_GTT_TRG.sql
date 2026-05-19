create or replace trigger "XX_APX_SEL_OBJ_GTT_TRG"
before
insert or update on "XX_APX_SEL_OBJ_GTT"
for each row
begin
    if :new.id_sel is null then
        select XX_APX_SEL_SEQ.nextval into :new.id_sel from sys.dual;
    end if;

end;
/

SHOW err

EXIT