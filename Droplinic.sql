-- =============================================
-- 1. сдюкемхе ясыеярбсчыху назейрнб
-- =============================================
BEGIN
    FOR r IN (SELECT 'DROP PUBLIC SYNONYM ' || synonym_name AS cmd FROM user_synonyms) LOOP
        EXECUTE IMMEDIATE r.cmd;
    END LOOP;

    FOR r IN (SELECT 'DROP SEQUENCE ' || sequence_name AS cmd FROM user_sequences where SEQUENCE_NAME like ('%_SEQ')) LOOP
        EXECUTE IMMEDIATE r.cmd;
    END LOOP;

    FOR r IN (SELECT 'DROP PACKAGE ' || object_name AS cmd FROM user_objects WHERE object_type = 'PACKAGE') LOOP
        BEGIN
            EXECUTE IMMEDIATE r.cmd;
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    END LOOP;
    
    FOR r IN (SELECT 'DROP VIEW ' || view_name AS cmd FROM user_views) LOOP
        EXECUTE IMMEDIATE r.cmd;
    END LOOP;
    
    FOR r IN (SELECT 'DROP TRIGGER ' || trigger_name AS cmd FROM user_triggers) LOOP
        EXECUTE IMMEDIATE r.cmd;
    END LOOP;
    FOR r IN (SELECT 'DROP ROLE ' || ROLE AS cmd from dba_roles where COMMON = 'NO') LOOP
        EXECUTE IMMEDIATE r.cmd;
    END LOOP;

    FOR r IN (SELECT 'DROP TABLE ' || table_name || ' CASCADE CONSTRAINTS' AS cmd FROM user_tables) LOOP
        EXECUTE IMMEDIATE r.cmd;
    END LOOP;

END;
/
    DROP USER app_doctor_user CASCADE;
    drop USER app_head_user CASCADE;
    drop USER app_registrar_user CASCADE;
    drop USER app_guest_user CASCADE;