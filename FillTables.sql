--drop table app_users cascade constraints;
DECLARE
BEGIN
    FOR i IN 1..100000 LOOP
        INSERT INTO app_users (
            username, 
            encrypted_password, 
            role_name
        ) VALUES (
            'user_' || LPAD(i, 6, '0'),
            auth_pkg.encrypt_password('Pass' || LPAD(i, 6, '0') || '!'),
            CASE MOD(i, 10)
            WHEN 0 THEN 'HEAD_DOCTOR'
            WHEN 1 THEN 'REGISTRAR'
            ELSE 'DOCTOR'
        END
        );
    END LOOP;
    COMMIT;
END;
/
select count(*) from app_users;
select * from app_users 
fetch first 20 rows only;
EXPLAIN PLAN FOR
SELECT * FROM app_users WHERE username = 'user_050000';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
