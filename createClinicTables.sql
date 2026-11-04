-- Отключение защиты от переполнения буфера
--SET SERVEROUTPUT ON SIZE UNLIMITED;
--SET DEFINE OFF;

--alter pluggable database all open;
-- Создание схемы и пользователей
--CREATE USER ADMIN IDENTIFIED BY "ClinicAdmin123!";
--GRANT CREATE SESSION TO ADMIN;
--GRANT CREATE TABLE TO ADMIN;
--GRANT CREATE TRIGGER TO ADMIN;
--GRANT CREATE SEQUENCE TO ADMIN;
--GRANT CREATE VIEW TO ADMIN;
--GRANT CREATE PROCEDURE TO ADMIN;
--GRANT CREATE TYPE TO ADMIN;
--GRANT CREATE SYNONYM TO ADMIN;
--GRANT UNLIMITED TABLESPACE TO ADMIN;
--GRANT CREATE PUBLIC SYNONYM TO ADMIN;
--GRANT CREATE ROLE TO ADMIN;
--GRANT EXECUTE ON DBMS_CRYPTO TO ADMIN;
--GRANT EXECUTE ON DBMS_REDACT TO ADMIN;
--GRANT EXECUTE ON DBMS_SESSION TO ADMIN;
--GRANT EXECUTE ON DBMS_RLS TO ADMIN;
--GRANT EXECUTE ON SYS.DBMS_CRYPTO TO admin;
--grant create any directory to admin;
-- Подключение как ADMIN
--CONNECT ADMIN/ClinicAdmin123!
-- Создание ролей для приложения

CREATE ROLE app_doctor_role NOT IDENTIFIED;
CREATE ROLE app_head_doctor_role NOT IDENTIFIED;
CREATE ROLE app_registrar_role NOT IDENTIFIED;
CREATE ROLE app_guest_role NOT IDENTIFIED;
-- Создание пользователей Oracle для каждой роли приложения
CREATE USER app_doctor_user IDENTIFIED BY "DoctorPass123!";
CREATE USER app_head_user IDENTIFIED BY "HeadPass123!";
CREATE USER app_registrar_user IDENTIFIED BY "RegistrarPass123!";
CREATE USER app_guest_user IDENTIFIED BY "GuestPass123!";

-- Назначение ролей пользователям
GRANT CREATE SESSION TO app_doctor_user, app_head_user, app_registrar_user, app_guest_user;
GRANT app_doctor_role TO app_doctor_user;
GRANT app_head_doctor_role TO app_head_user;
GRANT app_registrar_role TO app_registrar_user;
GRANT app_guest_role TO app_guest_user;
-- Таблица специальностей врачей
CREATE TABLE specialties (
    specialty_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    specialty_name VARCHAR2(100) NOT NULL UNIQUE,
    appointment_duration_minutes NUMBER NOT NULL CHECK (appointment_duration_minutes > 0)
);
-- Таблица пациентов
CREATE TABLE patients (
    patient_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    last_name VARCHAR2(100) NOT NULL,
    first_name VARCHAR2(100) NOT NULL,
    middle_name VARCHAR2(100),
    birth_date DATE NOT NULL,
    gender CHAR(1) CHECK (gender IN ('M', 'F')),
    address VARCHAR2(500),
    phone VARCHAR2(20) NOT NULL,
    passport_series_number VARCHAR2(9) NOT NULL,
    CONSTRAINT passport_format_chk CHECK (
        REGEXP_LIKE(passport_series_number, '^[A-Z]{2}\d{7}$')
    ),
    CONSTRAINT phone_unique UNIQUE (phone),
    CONSTRAINT passport_unique UNIQUE (passport_series_number)
);

-- Таблица врачей
CREATE TABLE doctors (
    doctor_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    last_name VARCHAR2(100) NOT NULL,
    first_name VARCHAR2(100) NOT NULL,
    middle_name VARCHAR2(100),
    specialty_id NUMBER NOT NULL,
    phone VARCHAR2(20) UNIQUE,
    office_number VARCHAR2(10),
    passport_series_number VARCHAR2(9) UNIQUE,
    CONSTRAINT fk_doctor_specialty
        FOREIGN KEY (specialty_id) REFERENCES specialties(specialty_id)
        ON DELETE SET NULL,
    CONSTRAINT doctor_passport_format_chk CHECK (
        passport_series_number IS NULL OR REGEXP_LIKE(passport_series_number, '^[A-Z]{2}\d{7}$')
    )
);

CREATE OR REPLACE VIEW masked_doctors AS
SELECT 
    doctor_id,
    last_name,
    first_name,
    middle_name,
    specialty_id,
    CASE 
        WHEN SYS_CONTEXT('USERENV', 'SESSION_USER') = 'APP_REGISTRAR_USER' OR
                SYS_CONTEXT('USERENV', 'SESSION_USER') = 'APP_DOCTOR_USER'
         THEN '***-***-' || SUBSTR(phone, -4)  
       ELSE phone
    END AS phone,
    office_number,
    CASE 
        WHEN SYS_CONTEXT('USERENV', 'SESSION_USER') = 'APP_REGISTRAR_USER'
         OR SYS_CONTEXT('USERENV', 'SESSION_USER') = 'APP_DOCTOR_USER'
        THEN SUBSTR(passport_series_number, 1, 2) || '*****' || SUBSTR(passport_series_number, 7, 2)
        ELSE passport_series_number
    END AS passport_series_number
FROM admin.doctors;
CREATE OR REPLACE VIEW masked_patients AS
SELECT 
    patient_id,
    last_name,
    first_name,
    middle_name,
    birth_date,
    gender,
    address,
    -- Маскируем телефон
    CASE 
        WHEN SYS_CONTEXT('USERENV', 'SESSION_USER') = 'APP_REGISTRAR_USER' OR
        SYS_CONTEXT('USERENV', 'SESSION_USER') = 'APP_DOCTOR_USER'
        THEN '***-***-' || SUBSTR(phone, -4)  
        ELSE phone
    END AS phone,
    -- Маскируем паспорт
    CASE 
        WHEN SYS_CONTEXT('USERENV', 'SESSION_USER') = 'APP_REGISTRAR_USER' OR
                SYS_CONTEXT('USERENV', 'SESSION_USER') = 'APP_DOCTOR_USER'
        THEN SUBSTR(passport_series_number, 1, 2) || '*****' || SUBSTR(passport_series_number, 7, 2)
        ELSE passport_series_number
    END AS passport_series_number
FROM admin.patients;

-- Таблица специальностей врачей

CREATE SEQUENCE doctor_schedule_seq 
    START WITH 1 
    INCREMENT BY 1 
    NOCACHE 
    NOCYCLE;
CREATE SEQUENCE appointment_seq 
    START WITH 1 
    INCREMENT BY 1 
    NOCACHE 
    NOCYCLE;
CREATE TABLE doctor_schedules (
    schedule_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doctor_id NUMBER NOT NULL,
    day_of_week NUMBER(1) NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP NOT NULL,
    CONSTRAINT fk_schedule_doctor
        FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id)
        ON DELETE CASCADE,
    CONSTRAINT schedule_time_chk CHECK (end_time > start_time),
    CONSTRAINT unique_doctor_slot UNIQUE (doctor_id, day_of_week, start_time)
);

-- Записи на прием
create TABLE appointments (
    appointment_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id NUMBER NOT NULL,
    doctor_id NUMBER NOT NULL,
    appointment_date TIMESTAMP NOT NULL,
    status VARCHAR2(20) DEFAULT 'SCHEDULED' CHECK (status IN ('SCHEDULED', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT fk_appointment_patient
        FOREIGN KEY (patient_id) REFERENCES patients(patient_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_appointment_doctor
        FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id)
        ON DELETE CASCADE,
    CONSTRAINT unique_doctor_time UNIQUE (doctor_id, appointment_date)
);
-- Медицинские записи
CREATE TABLE medical_records (
    record_id NUMBER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    patient_id NUMBER NOT NULL,
    doctor_id NUMBER NOT NULL,
    diagnosis CLOB,
    prescription CLOB,
    notes CLOB,
    record_date DATE DEFAULT SYSDATE NOT NULL,
    CONSTRAINT fk_record_doctor
        FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id)
        ON DELETE cascade,
    CONSTRAINT fk_record_patient
        FOREIGN KEY (patient_id) REFERENCES patients(patient_id)
        ON DELETE CASCADE
);

-- Результаты анализов
CREATE TABLE test_results (
    result_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id NUMBER NOT NULL,
    test_type VARCHAR2(200) NOT NULL,
    test_date DATE NOT NULL,
    result_date DATE,
    result_value VARCHAR2(4000),
    normal_range VARCHAR2(500),
    CONSTRAINT fk_result_patient
        FOREIGN KEY (patient_id) REFERENCES patients(patient_id)
        ON DELETE CASCADE
);
CREATE OR REPLACE VIEW masked_test_results AS
SELECT 
    result_id,
    patient_id,
    test_type,
    test_date,
    result_date,
    CASE 
        WHEN SYS_CONTEXT('USERENV', 'SESSION_USER') = 'APP_REGISTRAR_USER'
        THEN '***' 
        ELSE result_value
    END AS result_value,
    normal_range
FROM admin.test_results;
CREATE TABLE app_users (
    user_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username VARCHAR2(50) NOT NULL UNIQUE,
    encrypted_password RAW(256) NOT NULL,
    role_name VARCHAR2(20) NOT NULL CHECK (role_name IN ('DOCTOR', 'HEAD_DOCTOR', 'REGISTRAR')),
    doctor_id NUMBER NULL,
    CONSTRAINT fk_app_user_doctor
        FOREIGN KEY (doctor_id) REFERENCES doctors(doctor_id)
        ON DELETE cascade
);
