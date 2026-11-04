--CREATE OR REPLACE DIRECTORY JSON_DIR AS 'E:\json';

BEGIN
    export_medical_records_to_json(
        p_directory_name => 'JSON_DIR',
        p_file_name => 'medical_records.json'
    );
END;
/
TRUNCATE TABLE medical_records;
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM medical_records;
    DBMS_OUTPUT.PUT_LINE(v_count);
    import_medical_records_from_json(
        p_directory_name => 'JSON_DIR',
        p_file_name => 'medical_records.json'
    );
    SELECT COUNT(*) INTO v_count FROM medical_records;
    DBMS_OUTPUT.PUT_LINE(v_count);
END;
/