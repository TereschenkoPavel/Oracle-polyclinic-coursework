-- Создание контекста приложения для управления сессиями
CREATE OR REPLACE CONTEXT app_ctx USING auth_pkg;
-- Пакет аутентификации и авторизации

CREATE OR REPLACE PACKAGE auth_pkg IS
    -- Аутентификация пользователя (изменена с функции на процедуру)
    PROCEDURE authenticate_user(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    -- Регистрация пользователя
    PROCEDURE register_user (
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    -- Проверка прав доступа
    FUNCTION check_permission(
        p_required_role IN VARCHAR2
    ) RETURN BOOLEAN;
    PROCEDURE get_users_by_role_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    PROCEDURE update_user_password_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    PROCEDURE delete_user_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    -- Вспомогательные функции
    FUNCTION encrypt_password(p_password IN VARCHAR2) RETURN RAW;
  
END auth_pkg;
/
CREATE OR REPLACE PACKAGE BODY auth_pkg IS
    
    FUNCTION encrypt_password(p_password IN VARCHAR2) RETURN RAW IS
        v_key RAW(256) := HEXTORAW('0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF');
        v_encrypted_raw RAW(2048);
    BEGIN
        v_encrypted_raw := DBMS_CRYPTO.ENCRYPT(
            src => UTL_I18N.STRING_TO_RAW(p_password, 'AL32UTF8'),
            typ => DBMS_CRYPTO.DES_CBC_PKCS5,
            key => v_key
        );
        RETURN v_encrypted_raw;
    END encrypt_password;

    PROCEDURE register_user (
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        -- Переменные для входных параметров
        v_username VARCHAR2(50);
        v_password VARCHAR2(100);
        v_role_name VARCHAR2(20);
        v_doctor_id NUMBER;
        
        -- Внутренние переменные
        v_user_id NUMBER;
        v_encrypted_password RAW(200);
        v_validation_error VARCHAR2(500);
        
        -- Коды возврата
        v_return_code NUMBER := 0;
        v_message VARCHAR2(255) := 'User registered successfully';
        
        -- Исключения
        e_invalid_role EXCEPTION;
        e_invalid_doctor EXCEPTION;
        e_username_exists EXCEPTION;
        e_validation_error EXCEPTION;
    BEGIN
    IF NOT  auth_pkg.check_permission('HEAD_DOCTOR') THEN
        v_return_code := -1;
            v_message := v_validation_error;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'Доступ запрещен: требуется роль заведующего'
            );
             return;
    END IF;
        -- Парсим входной JSON
        BEGIN
            SELECT 
                jt.username,
                jt.password_hash,
                jt.role_name
            INTO v_username, v_password, v_role_name
            FROM JSON_TABLE(p_input_json, '$'
                COLUMNS (
                    username VARCHAR2(50) PATH '$.username',
                    password_hash VARCHAR2(100) PATH '$.password',
                    role_name VARCHAR2(20) PATH '$.role'
                )
            ) jt;
        EXCEPTION
            WHEN OTHERS THEN
                v_return_code := -1;
                v_message := 'Invalid input JSON format. Required fields: username, password, role';
                RAISE_APPLICATION_ERROR(-20001, v_message);
        END;
        
        -- 1. Валидация роли
        IF v_role_name NOT IN ('DOCTOR', 'HEAD_DOCTOR', 'REGISTRAR') THEN
            v_validation_error := 'Invalid role. Allowed values: DOCTOR, HEAD_DOCTOR, REGISTRAR';
            RAISE e_invalid_role;
        END IF;
        
        -- 2. Проверка уникальности username
        BEGIN
            SELECT 1 INTO v_validation_error
            FROM app_users
            WHERE username = v_username
            AND ROWNUM = 1;
            
            v_validation_error := 'Username already exists';
            RAISE e_username_exists;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                NULL; -- Username свободен, продолжаем
        END;
        
        
        -- 3. Шифрование пароля
        v_encrypted_password := encrypt_password(v_password);
        
        -- 4. Вставка пользователя
        INSERT INTO app_users (
            username, 
            encrypted_password, 
            role_name
        ) VALUES (
            v_username,
            v_encrypted_password,
            v_role_name
        ) RETURNING user_id INTO v_user_id;
        
        COMMIT;
        
        -- 5. Формируем успешный ответ
        p_output_json := JSON_OBJECT(
            'return_code' VALUE v_return_code,
            'message' VALUE v_message,
            'data' VALUE JSON_OBJECT(
                'user_id' VALUE v_user_id,
                'username' VALUE v_username,
                'role_name' VALUE v_role_name
                )
        );
        
    EXCEPTION
        WHEN e_invalid_role THEN
            v_return_code := -1;
            v_message := v_validation_error;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message,
                'data' VALUE NULL
            );
            
        WHEN e_username_exists THEN
            v_return_code := -1;
            v_message := v_validation_error;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message,
                'data' VALUE NULL
            );
            
        WHEN e_invalid_doctor THEN
            v_return_code := -1;
            v_message := v_validation_error;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message,
                'data' VALUE NULL
            );
            
        WHEN e_validation_error THEN
            v_return_code := -1;
            v_message := v_validation_error;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message,
                'data' VALUE NULL
            );
            
        WHEN OTHERS THEN
            ROLLBACK;
            v_return_code := -1;
            v_message := 'System error: ' || SQLERRM;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message,
                'data' VALUE NULL
            );
    END register_user;
     
    PROCEDURE authenticate_user(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        -- Переменные для входных параметров
        v_username VARCHAR2(50);
        v_password VARCHAR2(100);
        
        -- Внутренние переменные
        v_user_id NUMBER := -1;
        v_role_name VARCHAR2(20) := '';
        v_doctor_id NUMBER := -1;
        v_encrypted_password RAW(200);
        v_stored_password RAW(200);
        
        -- Коды возврата
        v_return_code NUMBER := 0;
        v_message VARCHAR2(255) := 'Login successful';
        
        -- Исключения
        e_invalid_format EXCEPTION;
        e_user_not_found EXCEPTION;
        e_invalid_password EXCEPTION;
    BEGIN
        -- Парсим входной JSON
        BEGIN
            SELECT username, password
            INTO v_username, v_password
            FROM JSON_TABLE(p_input_json, '$' 
                COLUMNS (
                    username VARCHAR2(50) PATH '$.login',
                    password VARCHAR2(100) PATH '$.password'
                )
            );
        EXCEPTION
            WHEN OTHERS THEN
                v_return_code := -1;
                v_message := 'Invalid input JSON format. Required fields: login, password';
                RAISE e_invalid_format;
        END;
        
        -- Поиск пользователя в базе данных
        BEGIN
            SELECT user_id, role_name, doctor_id, encrypted_password
            INTO v_user_id, v_role_name, v_doctor_id, v_stored_password
            FROM app_users
            WHERE username = v_username;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_return_code := -1;
                v_message := 'User not found';
                RAISE e_user_not_found;
            WHEN OTHERS THEN
                v_return_code := -1;
                v_message := 'Database error during user lookup: ' || SQLERRM;
                RAISE_APPLICATION_ERROR(-20002, v_message);
        END;
        
        -- Сравниваем пароли
        v_encrypted_password := encrypt_password(v_password);
        
        IF v_encrypted_password != v_stored_password THEN
            v_return_code := -1;
            v_message := 'Invalid credentials';
            RAISE e_invalid_password;
        END IF;

        p_output_json := JSON_OBJECT(
            'return_code' VALUE v_return_code,
            'message' VALUE v_message,
              'user_id' VALUE v_user_id,
              'role_name' VALUE v_role_name,
              'doctor_id' VALUE v_doctor_id,
              'db_connection' VALUE CASE v_role_name
                  WHEN 'DOCTOR' THEN 'app_doctor_user'
                  WHEN 'HEAD_DOCTOR' THEN 'app_head_user'
                  WHEN 'REGISTRAR' THEN 'app_registrar_user'
                  WHEN 'GUEST' THEN 'app_guest_user'
                  ELSE 'app_guest_user'
              END,
              'db_connection_pass' VALUE CASE v_role_name
                  WHEN 'DOCTOR' THEN 'DoctorPass123!'
                  WHEN 'HEAD_DOCTOR' THEN 'HeadPass123!'
                  WHEN 'REGISTRAR' THEN 'RegistrarPass123!'
                  WHEN 'GUEST' THEN 'GuestPass123!'
                  ELSE 'GuestPass123!'
              END
        );
        
    EXCEPTION
        WHEN e_invalid_format THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message,
                'data' VALUE NULL
            );
            
        WHEN e_user_not_found THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message,
                'data' VALUE NULL
            );
            
        WHEN e_invalid_password THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message,
                'data' VALUE NULL
            );
            
        WHEN OTHERS THEN
            v_return_code := -1;
            v_message := 'System error: ' || SQLERRM;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message,
                'data' VALUE NULL
            );
    END authenticate_user;
    PROCEDURE get_users_by_role_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) AS
        l_role_name VARCHAR2(20);
        l_cursor SYS_REFCURSOR;
        l_json_array JSON_ARRAY_T;
        l_json_obj   JSON_OBJECT_T;
        l_result_obj JSON_OBJECT_T;
        v_user_id NUMBER;
        v_username VARCHAR2(50);
        v_role_name_db VARCHAR2(20);
        v_doctor_id NUMBER;
    BEGIN
        -- Парсим входной JSON
        l_json_obj := JSON_OBJECT_T.parse(p_input_json);
        l_role_name := l_json_obj.get_string('role_name');
        
        -- Проверка прав доступа - только HEAD_DOCTOR может просматривать пользователей
        IF NOT check_permission('HEAD_DOCTOR') THEN
            RAISE_APPLICATION_ERROR(-20020, 'Доступ запрещен: требуется роль заведующего');
        END IF;
        
        OPEN l_cursor FOR
            SELECT user_id, username, role_name, doctor_id
            FROM app_users
            WHERE role_name = l_role_name;
        
        l_json_array := JSON_ARRAY_T();
        
        LOOP
            FETCH l_cursor INTO v_user_id, v_username, v_role_name_db, v_doctor_id;
            EXIT WHEN l_cursor%NOTFOUND;
            
            l_json_obj := JSON_OBJECT_T();
            l_json_obj.put('user_id', v_user_id);
            l_json_obj.put('username', v_username);
            l_json_obj.put('role_name', v_role_name_db);
            l_json_obj.put('doctor_id', v_doctor_id);
            
            l_json_array.append(l_json_obj);
        END LOOP;
        
        CLOSE l_cursor;
        
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', 0);
        l_result_obj.put('message', 'Success');
        l_result_obj.put('data', l_json_array);
        
        p_output_json := l_result_obj.to_clob();
            
    EXCEPTION
        WHEN OTHERS THEN
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', -1);
            l_result_obj.put('message', SQLERRM);
            p_output_json := l_result_obj.to_clob();
    END get_users_by_role_json;
    
    PROCEDURE update_user_password_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) AS
        v_user_id NUMBER;
        v_new_password VARCHAR2(100);
        v_encrypted_password RAW(200);
        v_return_code NUMBER := 0;
        v_message VARCHAR2(255) := 'Password updated successfully';
        l_json_obj JSON_OBJECT_T;
        l_result_obj JSON_OBJECT_T;
    BEGIN
        -- Проверка прав доступа
        IF NOT check_permission('HEAD_DOCTOR') THEN
            RAISE_APPLICATION_ERROR(-20020, 'Доступ запрещен: требуется роль заведующего');
        END IF;
        
        -- Парсим входной JSON
        l_json_obj := JSON_OBJECT_T.parse(p_input_json);
        
        v_user_id := l_json_obj.get_number('user_id');
        v_new_password := l_json_obj.get_string('new_password');
        
        -- Шифруем новый пароль
        v_encrypted_password := encrypt_password(v_new_password);
        
        -- Обновляем пароль
        UPDATE app_users
        SET encrypted_password = v_encrypted_password
        WHERE user_id = v_user_id;
        
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20021, 'Пользователь не найден');
        END IF;
        
        COMMIT;
        
        -- Формируем успешный ответ
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', v_return_code);
        l_result_obj.put('message', v_message);
        l_result_obj.put('data', v_user_id);
        
        p_output_json := l_result_obj.to_clob();
            
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', -1);
            l_result_obj.put('message', SQLERRM);
            p_output_json := l_result_obj.to_clob();
    END update_user_password_json;
    
    PROCEDURE delete_user_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) AS
        v_user_id NUMBER;
        v_username VARCHAR2(50);
        v_role_name VARCHAR2(20);
        v_return_code NUMBER := 0;
        v_message VARCHAR2(255) := 'User deleted successfully';
        l_json_obj JSON_OBJECT_T;
        l_result_obj JSON_OBJECT_T;
    BEGIN
        -- Проверка прав доступа
        IF NOT check_permission('HEAD_DOCTOR') THEN
            RAISE_APPLICATION_ERROR(-20020, 'Доступ запрещен: требуется роль заведующего');
        END IF;
        
        -- Парсим входной JSON
        l_json_obj := JSON_OBJECT_T.parse(p_input_json);
        
        v_user_id := l_json_obj.get_number('user_id');
        
        -- Получаем информацию о пользователе для проверки
        BEGIN
            SELECT username, role_name INTO v_username, v_role_name
            FROM app_users
            WHERE user_id = v_user_id;
            
            -- Нельзя удалить самого себя
            IF v_username = SYS_CONTEXT('APP_CTX', 'USERNAME') THEN
                RAISE_APPLICATION_ERROR(-20022, 'Нельзя удалить собственный аккаунт');
            END IF;
            
            -- Нельзя удалить других HEAD_DOCTOR
            IF v_role_name = 'HEAD_DOCTOR' THEN
                RAISE_APPLICATION_ERROR(-20023, 'Нельзя удалить аккаунт заведующего');
            END IF;
            
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20021, 'Пользователь не найден');
        END;
        
        -- Удаляем пользователя
        DELETE FROM app_users
        WHERE user_id = v_user_id;
        
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20021, 'Пользователь не найден');
        END IF;
        
        COMMIT;
        
        -- Формируем успешный ответ
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', v_return_code);
        l_result_obj.put('message', v_message);
        l_result_obj.put('data', v_user_id);
        
        p_output_json := l_result_obj.to_clob();
            
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', -1);
            l_result_obj.put('message', SQLERRM);
            p_output_json := l_result_obj.to_clob();
    END delete_user_json;

    FUNCTION check_permission(
    p_required_role IN VARCHAR2
) RETURN BOOLEAN IS
    v_session_user VARCHAR2(128);
    v_user_role VARCHAR2(20);
BEGIN
    v_session_user := SYS_CONTEXT('USERENV', 'SESSION_USER');
    CASE UPPER(v_session_user)
        WHEN 'APP_DOCTOR_USER' THEN
            v_user_role := 'DOCTOR';
        WHEN 'APP_HEAD_USER' THEN
            v_user_role := 'HEAD_DOCTOR';
        WHEN 'APP_REGISTRAR_USER' THEN
            v_user_role := 'REGISTRAR';
        WHEN 'APP_GUEST_USER' THEN
            v_user_role := 'GUEST';
        WHEN 'ADMIN' THEN RETURN true;
    END CASE;
    RETURN UPPER(p_required_role) = v_user_role;
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END check_permission;
    
    
END auth_pkg;
/
CREATE OR REPLACE PACKAGE doctor_schedule_pkg_json AS

    PROCEDURE get_doctor_schedule_json(
        p_doctor_id    IN NUMBER,
        p_output_json  OUT VARCHAR2
    );
    
    -- Добавить/обновить расписание врача
    PROCEDURE save_doctor_schedule_json(
        p_input_json   IN VARCHAR2,
        p_output_json  OUT VARCHAR2
    );
    
    -- Удалить расписание
    PROCEDURE delete_schedule_json(
        p_input_json   IN VARCHAR2,
        p_output_json  OUT VARCHAR2
    );
    
    -- Удалить все расписание врача
    PROCEDURE delete_all_schedule_json(
        p_input_json   IN VARCHAR2,
        p_output_json  OUT VARCHAR2
    );
    

    
    -- Получить доступные слоты времени для врача на дату
    PROCEDURE get_available_slots_json(
        p_input_json   IN VARCHAR2,
        p_output_json  OUT VARCHAR2
    );

END doctor_schedule_pkg_json;
/
CREATE OR REPLACE PACKAGE BODY doctor_schedule_pkg_json AS
    PROCEDURE get_available_slots_json(
    p_input_json   IN VARCHAR2,
    p_output_json  OUT VARCHAR2
) AS
    l_doctor_id NUMBER;
    l_appointment_date DATE;
    l_day_of_week NUMBER;
    l_start_time DATE;
    l_end_time DATE;
    l_current_slot DATE;
    l_slots JSON_ARRAY_T := JSON_ARRAY_T();
    l_json_obj JSON_OBJECT_T;
    l_result_obj JSON_OBJECT_T;
    l_slot_time VARCHAR2(5);
    v_duration_minutes NUMBER;
    v_doctor_exists NUMBER;
    v_current_time DATE := SYSDATE;
    v_work_start_full DATE;
    v_work_end_full DATE;
    v_slot_end DATE;
    v_is_available BOOLEAN;
    v_is_today BOOLEAN;
    v_rounded_minutes NUMBER;
BEGIN
    -- Парсим входной JSON
    l_json_obj := JSON_OBJECT_T.parse(p_input_json);
    
    l_doctor_id := l_json_obj.get_number('doctor_id');
    l_appointment_date := TO_DATE(l_json_obj.get_string('appointment_date'), 'YYYY-MM-DD');
    v_is_today := (TRUNC(l_appointment_date) = TRUNC(v_current_time));
    
    -- Проверяем существование врача
    SELECT COUNT(*) INTO v_doctor_exists
    FROM doctors
    WHERE doctor_id = l_doctor_id;
    
    IF v_doctor_exists = 0 THEN
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', -1);
        l_result_obj.put('message', 'Врач не найден');
        l_result_obj.put('available_slots', l_slots);
        p_output_json := l_result_obj.to_clob();
        RETURN;
    END IF;
    
    -- Получаем длительность приема из таблицы specialties
    BEGIN
        SELECT s.appointment_duration_minutes 
        INTO v_duration_minutes
        FROM doctors d
        JOIN specialties s ON d.specialty_id = s.specialty_id
        WHERE d.doctor_id = l_doctor_id;
    END;
    
    -- Получаем день недели (с учетом Oracle)
    l_day_of_week := 1 + TRUNC(l_appointment_date) - TRUNC(l_appointment_date, 'IW');
    
    -- Обрабатываем каждый период работы врача в этот день
    FOR schedule_rec IN (
        SELECT start_time, end_time 
        FROM doctor_schedules
        WHERE doctor_id = l_doctor_id 
          AND day_of_week = l_day_of_week
        ORDER BY start_time
    ) LOOP
        l_start_time := schedule_rec.start_time;
        l_end_time := schedule_rec.end_time;
        
        -- Пропускаем если время не задано
        CONTINUE WHEN l_start_time IS NULL OR l_end_time IS NULL;
        
        -- Преобразуем рабочие часы в полные даты
        v_work_start_full := TO_DATE(
            TO_CHAR(l_appointment_date, 'YYYY-MM-DD') || ' ' || TO_CHAR(l_start_time, 'HH24:MI'),
            'YYYY-MM-DD HH24:MI'
        );
        v_work_end_full := TO_DATE(
            TO_CHAR(l_appointment_date, 'YYYY-MM-DD') || ' ' || TO_CHAR(l_end_time, 'HH24:MI'),
            'YYYY-MM-DD HH24:MI'
        );
        
        -- Если конец раньше начала, пропускаем некорректный период
        CONTINUE WHEN v_work_end_full <= v_work_start_full;
        
        -- Начинаем с первого доступного времени в периоде
        l_current_slot := v_work_start_full;
        
        
        -- Генерируем слоты в текущем периоде с шагом  минут
        WHILE l_current_slot + (v_duration_minutes / 1440) <= v_work_end_full LOOP
            v_slot_end := l_current_slot + (v_duration_minutes / 1440);
            v_is_available := TRUE;
            
            -- Проверяем, не занят ли слот
            BEGIN
                -- Проверяем наличие пересечений с существующими записями
                FOR existing IN (
                    SELECT 1 
                    FROM appointments a
                    JOIN doctors d ON a.doctor_id = d.doctor_id
                    JOIN specialties s ON d.specialty_id = s.specialty_id
                    WHERE a.doctor_id = l_doctor_id
                      AND TRUNC(a.appointment_date) = l_appointment_date
                      AND a.status NOT IN ('CANCELLED')
                      AND (
                          (a.appointment_date <= v_slot_end) AND
                          (a.appointment_date + (s.appointment_duration_minutes / 1440) >= l_current_slot)
                      )
                ) LOOP
                    
                    v_is_available := FALSE;
                    EXIT;
                END LOOP;
                -- Если слот свободен, добавляем его
                IF v_is_available THEN
                    l_slot_time := TO_CHAR(l_current_slot, 'HH24:MI');
                    l_slots.append(l_slot_time);
                END IF;
                
            EXCEPTION
                WHEN OTHERS THEN
                    -- В случае ошибки пропускаем слот
                    NULL;
            END;
            
            -- Переходим к следующему слоту
            l_current_slot := l_current_slot + (v_duration_minutes  / 1440);
        END LOOP;
    END LOOP;
    
    -- Проверяем, есть ли вообще расписание на этот день
    DECLARE
        v_schedule_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_schedule_count
        FROM doctor_schedules
        WHERE doctor_id = l_doctor_id 
          AND day_of_week = l_day_of_week
          AND start_time IS NOT NULL 
          AND end_time IS NOT NULL;
          
        IF v_schedule_count = 0 THEN
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', 1);
            l_result_obj.put('message', 'Врач не работает в этот день');
            l_result_obj.put('available_slots', l_slots);
            p_output_json := l_result_obj.to_clob();
            RETURN;
        END IF;
    END;
    
    -- Проверяем, если слотов нет
    IF l_slots.get_size() = 0 THEN
        IF v_is_today THEN
            -- Проверяем, закончился ли рабочий день
            DECLARE
                v_last_work_end DATE;
            BEGIN
                SELECT MAX(TO_DATE(
                    TO_CHAR(l_appointment_date, 'YYYY-MM-DD') || ' ' || TO_CHAR(end_time, 'HH24:MI'),
                    'YYYY-MM-DD HH24:MI'
                )) INTO v_last_work_end
                FROM doctor_schedules
                WHERE doctor_id = l_doctor_id 
                  AND day_of_week = l_day_of_week
                  AND end_time IS NOT NULL;
                
                IF v_current_time >= v_last_work_end THEN
                    l_result_obj := JSON_OBJECT_T();
                    l_result_obj.put('return_code', 2);
                    l_result_obj.put('message', 'Рабочий день уже закончился');
                    l_result_obj.put('available_slots', l_slots);
                    p_output_json := l_result_obj.to_clob();
                    RETURN;
                END IF;
            END;
        END IF;
        
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', 2);
        l_result_obj.put('message', 'Нет доступных слотов для записи');
        l_result_obj.put('available_slots', l_slots);
        p_output_json := l_result_obj.to_clob();
        RETURN;
    END IF;
    
    -- Создаем объект для результата
    l_result_obj := JSON_OBJECT_T();
    l_result_obj.put('return_code', 0);
    l_result_obj.put('message', 'Success');
    l_result_obj.put('duration_minutes', v_duration_minutes);
    l_result_obj.put('available_slots', l_slots);
    p_output_json := l_result_obj.to_clob();
        
EXCEPTION
    WHEN OTHERS THEN
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', -1);
        l_result_obj.put('message', SQLERRM);
        l_result_obj.put('available_slots', JSON_ARRAY_T());
        p_output_json := l_result_obj.to_clob();
END get_available_slots_json;
    
    PROCEDURE get_doctor_schedule_json(
        p_doctor_id    IN NUMBER,
        p_output_json  OUT VARCHAR2
    ) AS
        l_cursor SYS_REFCURSOR;
        l_json_array JSON_ARRAY_T;
        l_json_obj   JSON_OBJECT_T;
        l_result_obj JSON_OBJECT_T;
        v_schedule_id NUMBER;
        v_doctor_id NUMBER;
        v_day_of_week NUMBER;
        v_start_time VARCHAR2(5);
        v_end_time VARCHAR2(5);
    BEGIN
        l_json_array := JSON_ARRAY_T();
        
        OPEN l_cursor FOR
            SELECT 
                schedule_id,
                doctor_id,
                day_of_week,
                TO_CHAR(start_time, 'HH24:MI') as start_time,
                TO_CHAR(end_time, 'HH24:MI') as end_time
            FROM doctor_schedules
            WHERE doctor_id = p_doctor_id
            ORDER BY day_of_week, start_time;
        
        LOOP
            FETCH l_cursor INTO 
                v_schedule_id, 
                v_doctor_id, 
                v_day_of_week, 
                v_start_time, 
                v_end_time;
            EXIT WHEN l_cursor%NOTFOUND;
            
            l_json_obj := JSON_OBJECT_T();
            l_json_obj.put('schedule_id', v_schedule_id);
            l_json_obj.put('doctor_id', v_doctor_id);
            l_json_obj.put('day_of_week', v_day_of_week);
            l_json_obj.put('start_time', v_start_time);
            l_json_obj.put('end_time', v_end_time);
            
            l_json_array.append(l_json_obj);
        END LOOP;
        
        CLOSE l_cursor;
        
        -- Создаем объект для результата
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', 0);
        l_result_obj.put('message', 'Success');
        l_result_obj.put('data', l_json_array);
        
        p_output_json := l_result_obj.to_clob();
            
    EXCEPTION
        WHEN OTHERS THEN
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', -1);
            l_result_obj.put('message', SQLERRM);
            p_output_json := l_result_obj.to_clob();
    END get_doctor_schedule_json;
    
PROCEDURE save_doctor_schedule_json(
    p_input_json  IN VARCHAR2,
    p_output_json OUT VARCHAR2
) AS
    l_doctor_id NUMBER;
    l_day_of_week NUMBER;
    l_start_time VARCHAR2(8);
    l_end_time VARCHAR2(8);
    l_schedule_id NUMBER;
    l_json_obj JSON_OBJECT_T;
    l_result_obj JSON_OBJECT_T;
    l_start_timestamp TIMESTAMP;
    l_end_timestamp TIMESTAMP;
    l_has_overlap NUMBER;
BEGIN
    -- Парсим входной JSON
    l_json_obj := JSON_OBJECT_T.parse(p_input_json);
    
    l_doctor_id := l_json_obj.get_number('doctor_id');
    l_day_of_week := l_json_obj.get_number('day_of_week');
    l_start_time := l_json_obj.get_string('start_time');
    l_end_time := l_json_obj.get_string('end_time');
    
    -- Преобразуем строки времени в TIMESTAMP (с произвольной датой)
    l_start_timestamp := TO_TIMESTAMP('2025-01-01 ' || l_start_time, 'YYYY-MM-DD HH24:MI:SS');
    l_end_timestamp := TO_TIMESTAMP('2025-01-01 ' || l_end_time, 'YYYY-MM-DD HH24:MI:SS');
    
    -- Проверяем корректность временного интервала
    IF l_end_timestamp <= l_start_timestamp THEN
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', -1);
        l_result_obj.put('message', 'Время окончания должно быть больше времени начала');
        p_output_json := l_result_obj.to_clob();
        RETURN;
    END IF;
    
    -- Проверяем пересечение с существующими записями для этого врача и дня
    SELECT COUNT(*)
    INTO l_has_overlap
    FROM doctor_schedules
    WHERE doctor_id = l_doctor_id 
      AND day_of_week = l_day_of_week
      AND (l_start_timestamp <= end_time
      AND l_end_timestamp >= start_time);

    IF l_has_overlap > 0 THEN
        -- Найдены пересечения, не добавляем новую запись
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', -2);
        l_result_obj.put('message', 'Указанный интервал пересекается с существующим расписанием на этот день');
        p_output_json := l_result_obj.to_clob();
        RETURN;
    END IF;
    
    -- Создаем новую запись (пересечений нет)
    INSERT INTO doctor_schedules (
        doctor_id, day_of_week, start_time, end_time
    ) VALUES (
        l_doctor_id, l_day_of_week, 
        l_start_timestamp,
        l_end_timestamp
    )
    RETURNING schedule_id INTO l_schedule_id;
    
    COMMIT;
    
    l_result_obj := JSON_OBJECT_T();
    l_result_obj.put('return_code', 0);
    l_result_obj.put('data', l_schedule_id);
    l_result_obj.put('message', 'Расписание успешно сохранено');
    p_output_json := l_result_obj.to_clob();
    
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', -1);
        
        -- Проверяем, не нарушено ли ограничение уникальности
        IF SQLCODE = -1 AND SQLERRM LIKE '%UNIQUE_DOCTOR_SLOT%' THEN
            l_result_obj.put('message', 'Расписание с таким временем начала для этого врача и дня уже существует');
        ELSE
            l_result_obj.put('message', 'Ошибка при сохранении расписания: ' || SQLERRM);
        END IF;
        
        p_output_json := l_result_obj.to_clob();
END save_doctor_schedule_json;

    PROCEDURE delete_schedule_json(
        p_input_json   IN VARCHAR2,
        p_output_json  OUT VARCHAR2
    ) AS
        l_schedule_id NUMBER;
        l_doctor_id NUMBER;
        l_day_of_week NUMBER;
        l_json_obj JSON_OBJECT_T;
        l_result_obj JSON_OBJECT_T;
        v_future_appointments NUMBER;
        v_doctor_exists NUMBER;
    BEGIN
     IF auth_pkg.check_permission('HEAD_DOCTOR') THEN
                NULL;
            ELSE
                l_result_obj := JSON_OBJECT_T();
                l_result_obj.put('return_code', -1);
                l_result_obj.put('message', 'Доступ запрещен');
                  
                p_output_json := l_result_obj.to_clob();
                RETURN;
            END IF;
        -- Парсим входной JSON
        l_json_obj := JSON_OBJECT_T.parse(p_input_json);
        
        -- Проверяем, по какому параметру удаляем (schedule_id или doctor_id + day_of_week)
        IF l_json_obj.has('schedule_id') THEN
            l_schedule_id := l_json_obj.get_number('schedule_id');
            
            -- Проверяем существование расписания
            DECLARE
                v_doctor_id NUMBER;
                v_day_of_week NUMBER;
            BEGIN
                SELECT doctor_id, day_of_week
                INTO v_doctor_id, v_day_of_week
                FROM doctor_schedules
                WHERE schedule_id = l_schedule_id;
                
                -- Проверяем будущие записи с учетом длительности приема
                SELECT COUNT(*) INTO v_future_appointments
                FROM appointments a
                JOIN doctors d ON a.doctor_id = d.doctor_id
                JOIN specialties s ON d.specialty_id = s.specialty_id
                WHERE a.doctor_id = v_doctor_id
                  AND 1 + TRUNC (a.appointment_date) - TRUNC (a.appointment_date, 'IW') = v_day_of_week 
                  AND a.appointment_date >= SYSDATE
                  AND a.status NOT IN ('CANCELLED', 'COMPLETED');
                  
                IF v_future_appointments > 0 THEN
                    RAISE_APPLICATION_ERROR(-20010, 
                        'Нельзя удалить расписание, так как есть будущие записи (' || 
                        v_future_appointments || ' записей). Сначала отмените записи.');
                END IF;
                
                -- Удаляем расписание по schedule_id
                DELETE FROM doctor_schedules
                WHERE schedule_id = l_schedule_id;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    RAISE_APPLICATION_ERROR(-20012, 'Расписание не найдено');
            END;
            
        ELSIF l_json_obj.has('doctor_id') AND l_json_obj.has('day_of_week') THEN
            l_doctor_id := l_json_obj.get_number('doctor_id');
            l_day_of_week := l_json_obj.get_number('day_of_week');
            
            -- Проверяем существование врача
            SELECT COUNT(*) INTO v_doctor_exists
            FROM doctors
            WHERE doctor_id = l_doctor_id;
            
            IF v_doctor_exists = 0 THEN
                RAISE_APPLICATION_ERROR(-20002, 'Врач не найден');
            END IF;
            
            -- Проверяем будущие записи с учетом длительности приема
            SELECT COUNT(*) INTO v_future_appointments
            FROM appointments a
            JOIN doctors d ON a.doctor_id = d.doctor_id
            JOIN specialties s ON d.specialty_id = s.specialty_id
            WHERE a.doctor_id = l_doctor_id
              AND 1 + TRUNC (a.appointment_date) - TRUNC (a.appointment_date, 'IW') = l_day_of_week 
              AND a.appointment_date >= SYSDATE
              AND a.status NOT IN ('CANCELLED', 'COMPLETED');
              
            IF v_future_appointments > 0 THEN
                RAISE_APPLICATION_ERROR(-20010, 
                    'Нельзя удалить расписание, так как есть будущие записи (' || 
                    v_future_appointments || ' записей). Сначала отмените записи.');
            END IF;
            
            -- Удаляем расписание по doctor_id и day_of_week
            DELETE FROM doctor_schedules
            WHERE doctor_id = l_doctor_id
              AND day_of_week = l_day_of_week;
              
        ELSE
            RAISE_APPLICATION_ERROR(-20011, 
                'Необходимо указать либо schedule_id, либо doctor_id и day_of_week');
        END IF;
        
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20012, 'Расписание не найдено');
        END IF;
        
        COMMIT;
        
        -- Создаем объект для результата
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', 0);
        l_result_obj.put('message', 'Расписание успешно удалено');
        l_result_obj.put('deleted_count', SQL%ROWCOUNT);
        p_output_json := l_result_obj.to_clob();
            
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', -1);
            l_result_obj.put('message', SQLERRM);
            p_output_json := l_result_obj.to_clob();
    END delete_schedule_json;

    PROCEDURE delete_all_schedule_json(
        p_input_json   IN VARCHAR2,
        p_output_json  OUT VARCHAR2
    ) AS
        l_doctor_id NUMBER;
        l_json_obj JSON_OBJECT_T;
        l_result_obj JSON_OBJECT_T;
        v_future_appointments NUMBER;
        v_deleted_count NUMBER;
        v_doctor_exists NUMBER;
    BEGIN
     IF auth_pkg.check_permission('HEAD_DOCTOR') THEN
                NULL;
            ELSE
                l_result_obj := JSON_OBJECT_T();
                l_result_obj.put('return_code', -1);
                l_result_obj.put('message', 'Доступ запрещен');
                  
                p_output_json := l_result_obj.to_clob();
                RETURN;
            END IF;
        -- Парсим входной JSON
        l_json_obj := JSON_OBJECT_T.parse(p_input_json);
        
        l_doctor_id := l_json_obj.get_number('doctor_id');
        
        -- Проверяем существование врача
        SELECT COUNT(*) INTO v_doctor_exists
        FROM doctors
        WHERE doctor_id = l_doctor_id;
        
        IF v_doctor_exists = 0 THEN
            RAISE_APPLICATION_ERROR(-20002, 'Врач не найден');
        END IF;
        
        -- Проверяем, есть ли будущие записи у врача с учетом длительности приема
        SELECT COUNT(*) INTO v_future_appointments
        FROM appointments a
        JOIN doctors d ON a.doctor_id = d.doctor_id
        JOIN specialties s ON d.specialty_id = s.specialty_id
        WHERE a.doctor_id = l_doctor_id
          AND a.appointment_date >= SYSDATE
          AND a.status NOT IN ('CANCELLED', 'COMPLETED');
          
        IF v_future_appointments > 0 THEN
            RAISE_APPLICATION_ERROR(-20013, 
                'Нельзя удалить все расписание, так как есть будущие записи (' || 
                v_future_appointments || ' записей). Сначала отмените записи.');
        END IF;
        
        -- Удаляем все расписание врача
        DELETE FROM doctor_schedules
        WHERE doctor_id = l_doctor_id;
        
        v_deleted_count := SQL%ROWCOUNT;
        
        COMMIT;
        
        -- Создаем объект для результата
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', 0);
        l_result_obj.put('message', 'Все расписание врача удалено');
        l_result_obj.put('deleted_count', v_deleted_count);
        p_output_json := l_result_obj.to_clob();
            
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', -1);
            l_result_obj.put('message', SQLERRM);
            p_output_json := l_result_obj.to_clob();
    END delete_all_schedule_json;

END doctor_schedule_pkg_json;
/
CREATE OR REPLACE PACKAGE appointment_pkg_json AS
    PROCEDURE check_appointment_time_json(
        p_input_json   IN VARCHAR2,
        p_output_json  OUT VARCHAR2
    );
    PROCEDURE get_doctor_appointments_json(
        p_input_json  IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    PROCEDURE create_appointment_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    PROCEDURE cancel_appointment_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    PROCEDURE update_appointment_status_json(
        p_input_json  IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    PROCEDURE get_all_appointments_json(
        p_output_json OUT VARCHAR2
    );
    PROCEDURE get_appointment_by_id_json(
        p_input_json  IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    PROCEDURE reschedule_appointment_json(
            p_input_json IN VARCHAR2,
            p_output_json OUT VARCHAR2
    );
    PROCEDURE get_appointment_slots_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    PROCEDURE delete_appointment_json(
    p_input_json  IN VARCHAR2,
    p_output_json OUT VARCHAR2
  );
    
END appointment_pkg_json;
/
CREATE OR REPLACE PACKAGE BODY appointment_pkg_json AS
PROCEDURE delete_appointment_json(
    p_input_json  IN VARCHAR2,
    p_output_json OUT VARCHAR2
) AS
    l_appointment_id NUMBER;
    l_json_obj      JSON_OBJECT_T;
    l_result_obj    JSON_OBJECT_T;
    v_doctor_id     NUMBER;
    v_appointment_date DATE;
    v_current_user_id NUMBER;
    v_patient_id    NUMBER;
    v_doctor_name   VARCHAR2(255);
    v_patient_name  VARCHAR2(255);
BEGIN
    -- Парсим входной JSON
    l_json_obj := JSON_OBJECT_T.parse(p_input_json);
    l_appointment_id := l_json_obj.get_number('appointment_id');
    
    -- Получаем информацию о записи
    SELECT 
        a.doctor_id,
        a.appointment_date,
        a.patient_id,
        d.last_name || ' ' || d.first_name || ' ' || COALESCE(d.middle_name, '') as doctor_name,
        p.last_name || ' ' || p.first_name || ' ' || COALESCE(p.middle_name, '') as patient_name
    INTO 
        v_doctor_id,
        v_appointment_date,
        v_patient_id,
        v_doctor_name,
        v_patient_name
    FROM appointments a
    JOIN doctors d ON a.doctor_id = d.doctor_id
    JOIN patients p ON a.patient_id = p.patient_id
    WHERE a.appointment_id = l_appointment_id;
    
    -- Проверка прав доступа
    IF auth_pkg.check_permission('HEAD_DOCTOR') THEN
        NULL; -- HEAD_DOCTOR может удалять любые записи
    ELSIF auth_pkg.check_permission('REGISTRAR') THEN
        -- REGISTRAR может удалять записи только за 24 часа до приема
        IF v_appointment_date < SYSDATE + 1 THEN
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', -1);
            l_result_obj.put('message', 
                'Регистратор может удалять записи только если до приема осталось более 24 часов');
            p_output_json := l_result_obj.to_clob();
            RETURN;
        END IF;
    ELSE
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', -1);
        l_result_obj.put('message', 'Доступ запрещен. Требуются права HEAD_DOCTOR или REGISTRAR');
        p_output_json := l_result_obj.to_clob();
        RETURN;
    END IF;
    
    -- Проверяем, что запись не в статусе 'COMPLETED' (завершенные нельзя удалять)
    DECLARE
        v_status VARCHAR2(20);
    BEGIN
        SELECT status INTO v_status
        FROM appointments
        WHERE appointment_id = l_appointment_id;
        
        IF v_status = 'COMPLETED' THEN
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', -1);
            l_result_obj.put('message', 'Нельзя удалить завершенную запись');
            p_output_json := l_result_obj.to_clob();
            RETURN;
        END IF;
    END;
    
    -- Удаляем запись
    DELETE FROM appointments WHERE appointment_id = l_appointment_id;
    
    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20050, 'Запись не найдена');
    END IF;
    
    COMMIT;
    
    -- Формируем результат с информацией об удаленной записи
    l_result_obj := JSON_OBJECT_T();
    l_result_obj.put('return_code', 0);
    l_result_obj.put('message', 'Запись успешно удалена');
    
    -- Возвращаем информацию об удаленной записи для лога
    DECLARE
        l_info_obj JSON_OBJECT_T;
    BEGIN
        l_info_obj := JSON_OBJECT_T();
        l_info_obj.put('appointment_id', l_appointment_id);
        l_info_obj.put('doctor_id', v_doctor_id);
        l_info_obj.put('patient_id', v_patient_id);
        l_info_obj.put('appointment_date', TO_CHAR(v_appointment_date, 'YYYY-MM-DD"T"HH24:MI:SS'));
        l_info_obj.put('doctor_name', v_doctor_name);
        l_info_obj.put('patient_name', v_patient_name);
        l_info_obj.put('deleted_at', TO_CHAR(SYSDATE, 'YYYY-MM-DD"T"HH24:MI:SS'));
        
        l_result_obj.put('data', l_info_obj);
    END;
    
    p_output_json := l_result_obj.to_clob();
    
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', -1);
        l_result_obj.put('message', 'Запись не найдена');
        p_output_json := l_result_obj.to_clob();
    WHEN OTHERS THEN
        ROLLBACK;
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', -1);
        l_result_obj.put('message', 'Ошибка при удалении записи: ' || SQLERRM);
        p_output_json := l_result_obj.to_clob();
END delete_appointment_json;

    PROCEDURE check_appointment_time_json(
    p_input_json   IN VARCHAR2,
    p_output_json  OUT VARCHAR2
) AS
    l_doctor_id NUMBER;
    l_appointment_datetime DATE;
    l_appointment_date DATE;
    l_appointment_time VARCHAR2(5);
    l_day_of_week NUMBER;
    l_appointment_start DATE;
    l_appointment_end DATE;
    l_duration_minutes NUMBER;
    l_is_available BOOLEAN := TRUE;
    l_message VARCHAR2(500);
    l_json_obj JSON_OBJECT_T;
    l_result_obj JSON_OBJECT_T;
    v_doctor_exists NUMBER;
    v_current_time DATE := SYSDATE;
    v_found_schedule BOOLEAN := FALSE;
    v_appointment_in_schedule BOOLEAN := FALSE;
    v_schedule_list VARCHAR2(4000) := '';
    l_appointment_datetime_str VARCHAR2(30);
BEGIN
    -- Парсим входной JSON
    l_json_obj := JSON_OBJECT_T.parse(p_input_json);
    
    l_doctor_id := l_json_obj.get_number('doctor_id');
    
    l_appointment_datetime_str := l_json_obj.get_string('appointment_date');
    l_appointment_datetime := TO_DATE(l_appointment_datetime_str, 'YYYY-MM-DD HH24:MI');
    l_appointment_date := TRUNC(l_appointment_datetime);
    l_appointment_time := TO_CHAR(l_appointment_datetime, 'HH24:MI');
    
    SELECT COUNT(*) INTO v_doctor_exists
    FROM doctors
    WHERE doctor_id = l_doctor_id;
    
    IF v_doctor_exists = 0 THEN
        l_is_available := FALSE;
        l_message := 'Врач не найден';
    END IF;
    
    -- Получаем длительность приема из таблицы specialties
    IF l_is_available THEN
        BEGIN
            SELECT s.appointment_duration_minutes 
            INTO l_duration_minutes
            FROM doctors d
            JOIN specialties s ON d.specialty_id = s.specialty_id
            WHERE d.doctor_id = l_doctor_id;
            
            IF l_duration_minutes IS NULL OR l_duration_minutes <= 0 THEN
                l_duration_minutes := 30; -- Значение по умолчанию
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                l_duration_minutes := 30; -- Значение по умолчанию
        END;
    END IF;
    
    -- Получаем день недели записи
    IF l_is_available THEN
        SELECT 1 + TRUNC(l_appointment_date) - TRUNC(l_appointment_date, 'IW') 
        INTO l_day_of_week
        FROM dual;
    END IF;
    
    -- Создаем полную дату для приема
    IF l_is_available THEN
        l_appointment_start := TO_DATE(
            TO_CHAR(l_appointment_date, 'YYYY-MM-DD') || ' ' || l_appointment_time,
            'YYYY-MM-DD HH24:MI'
        );
        l_appointment_end := l_appointment_start + (l_duration_minutes / 1440);
    END IF;
    
    -- Проверяем рабочий день врача (может быть несколько промежутков)
    IF l_is_available THEN
        v_found_schedule := FALSE;
        v_appointment_in_schedule := FALSE;
        v_schedule_list := '';
        
        -- Проверяем все расписания врача на этот день недели
        FOR schedule_rec IN (
            SELECT start_time, end_time 
            FROM doctor_schedules
            WHERE doctor_id = l_doctor_id 
              AND day_of_week = l_day_of_week
            ORDER BY start_time
        ) LOOP
            v_found_schedule := TRUE;
            
            -- Формируем список промежутков для сообщения об ошибке
            IF LENGTH(v_schedule_list) > 0 THEN
                v_schedule_list := v_schedule_list || ', ';
            END IF;
            v_schedule_list := v_schedule_list || 
                TO_CHAR(schedule_rec.start_time, 'HH24:MI') || '-' || 
                TO_CHAR(schedule_rec.end_time, 'HH24:MI');
            
            -- Создаем полные даты для рабочего промежутка
            DECLARE
                v_work_start DATE;
                v_work_end DATE;
                v_diff_minutes NUMBER;
            BEGIN
                v_work_start := TO_DATE(
                    TO_CHAR(l_appointment_date, 'YYYY-MM-DD') || ' ' || 
                    TO_CHAR(schedule_rec.start_time, 'HH24:MI:SS'),
                    'YYYY-MM-DD HH24:MI:SS'
                );
                v_work_end := TO_DATE(
                    TO_CHAR(l_appointment_date, 'YYYY-MM-DD') || ' ' || 
                    TO_CHAR(schedule_rec.end_time, 'HH24:MI:SS'),
                    'YYYY-MM-DD HH24:MI:SS'
                );
                
                -- Проверяем, что время в рамках этого рабочего промежутка
                IF l_appointment_start >= v_work_start AND l_appointment_end <= v_work_end THEN
                    v_appointment_in_schedule := TRUE;
                    
                    -- Проверка кратности времени приема
                    -- Вычисляем разницу в минутах между началом промежутка и временем приема
                    v_diff_minutes := ROUND((l_appointment_start - v_work_start) * 24 * 60);
                    
                    -- Проверяем, что разница кратна длительности приема
                    IF MOD(v_diff_minutes, l_duration_minutes) != 0 THEN
                        l_is_available := FALSE;
                        l_message := 'Время записи должно быть кратно ' || l_duration_minutes || 
                                     ' минутам от начала рабочего промежутка. ' ||
                                     'Начало промежутка: ' || TO_CHAR(v_work_start, 'HH24:MI') || 
                                     '. Допустимые времена: ';
                        
                        -- Генерируем список допустимых времен для этого промежутка
                        DECLARE
                            v_current_time_slot DATE := v_work_start;
                            v_slots_list VARCHAR2(1000) := '';
                        BEGIN
                            WHILE v_current_time_slot < v_work_end LOOP
                                IF v_slots_list IS NOT NULL AND LENGTH(v_slots_list) > 0 THEN
                                    v_slots_list := v_slots_list || ', ';
                                END IF;
                                v_slots_list := v_slots_list || TO_CHAR(v_current_time_slot, 'HH24:MI');
                                v_current_time_slot := v_current_time_slot + (l_duration_minutes / 1440);
                            END LOOP;
                            
                            l_message := l_message || v_slots_list;
                        END;
                      
                        EXIT;
                    END IF;
                    
                    EXIT;
                END IF;
            END;
        END LOOP;
        
        -- Проверяем результаты поиска расписания
        IF NOT v_found_schedule THEN
            l_is_available := FALSE;
            l_message := 'Врач не работает в этот день (день недели: ' || 
                         CASE l_day_of_week
                            WHEN 1 THEN 'понедельник'
                            WHEN 2 THEN 'вторник'
                            WHEN 3 THEN 'среда'
                            WHEN 4 THEN 'четверг'
                            WHEN 5 THEN 'пятница'
                            WHEN 6 THEN 'суббота'
                            WHEN 7 THEN 'воскресенье'
                         END || ')';
        ELSIF NOT v_appointment_in_schedule AND l_is_available THEN
            l_is_available := FALSE;
            l_message := 'Время приема выходит за рамки рабочего дня врача. ' ||
                         'Рабочие промежутки: ' || v_schedule_list;
        END IF;
    END IF;
    
    -- Проверяем, что слот не занят другими приемами (с учетом длительности приема)
    IF l_is_available THEN
        FOR existing IN (
            SELECT 1 FROM appointments a
            JOIN doctors d ON a.doctor_id = d.doctor_id
            JOIN specialties s ON d.specialty_id = s.specialty_id
            WHERE a.doctor_id = l_doctor_id
              AND TRUNC(a.appointment_date) = l_appointment_date
              AND a.status NOT IN ('CANCELLED')
              AND (
                  (a.appointment_date < l_appointment_end) AND
                  (a.appointment_date + (s.appointment_duration_minutes / 1440) > l_appointment_start)
              )
        ) LOOP
            l_is_available := FALSE;
            l_message := 'Данное время уже занято другим приемом';
            EXIT;
        END LOOP;
    END IF;
    
    -- Проверяем, что дата не в прошлом
    IF l_is_available AND l_appointment_date < TRUNC(v_current_time) THEN
        l_is_available := FALSE;
        l_message := 'Нельзя записаться на прошедшую дату';
    END IF;
    
    
    -- Создаем объект для результата
    l_result_obj := JSON_OBJECT_T();
    l_result_obj.put('return_code', CASE WHEN l_is_available THEN 0 ELSE 1 END);
    l_result_obj.put('data', CASE WHEN l_is_available THEN 1 ELSE 0 END);
    l_result_obj.put('message', CASE WHEN l_is_available THEN 'Время доступно для записи' ELSE l_message END);

    p_output_json := l_result_obj.to_clob();
        
EXCEPTION
    WHEN OTHERS THEN
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', -1);
        l_result_obj.put('data', 0);
        l_result_obj.put('message', 'Системная ошибка: ' || SQLERRM);
        p_output_json := l_result_obj.to_clob();
END check_appointment_time_json;

    PROCEDURE get_appointment_slots_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_doctor_id NUMBER;
        v_appointment_date DATE;
        v_available_slots JSON_ARRAY_T;
        v_result_obj JSON_OBJECT_T;
    BEGIN
        -- Парсим входной JSON
        SELECT 
            jt.doctor_id,
            TO_DATE(jt.appointment_date, 'YYYY-MM-DD')
        INTO 
            v_doctor_id,
            v_appointment_date
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                doctor_id NUMBER PATH '$.doctor_id',
                appointment_date VARCHAR2(10) PATH '$.appointment_date'
            )
        ) jt;
        
        -- Получаем доступные слоты через существующую процедуру
        DECLARE
            v_slots_input VARCHAR2(1000);
            v_slots_output VARCHAR2(4000);
            v_slots_obj JSON_OBJECT_T;
        BEGIN
            v_slots_input := JSON_OBJECT(
                'doctor_id' VALUE v_doctor_id,
                'appointment_date' VALUE TO_CHAR(v_appointment_date, 'YYYY-MM-DD')
            );
            
            doctor_schedule_pkg_json.get_available_slots_json(v_slots_input, v_slots_output);
            v_slots_obj := JSON_OBJECT_T.parse(v_slots_output);
            IF v_slots_obj.get_number('return_code') = 0 THEN
                v_available_slots := v_slots_obj.get_array('available_slots');
            ELSE
                v_available_slots := JSON_ARRAY_T();
            END IF;
        END;
        
        -- Формируем результат
        v_result_obj := JSON_OBJECT_T();
        v_result_obj.put('return_code', 0);
        v_result_obj.put('message', 'Success');
        v_result_obj.put('data', v_available_slots);
        p_output_json := v_result_obj.to_clob();
        
    EXCEPTION
        WHEN OTHERS THEN
            v_result_obj := JSON_OBJECT_T();
            v_result_obj.put('return_code', -1);
            v_result_obj.put('message', SQLERRM);
            p_output_json := v_result_obj.to_clob();
    END get_appointment_slots_json;
    
    PROCEDURE create_appointment_json(
    p_input_json  IN VARCHAR2,
    p_output_json OUT VARCHAR2
) AS
    l_patient_id           NUMBER;
    l_doctor_id           NUMBER;
    l_appointment_date_str VARCHAR2(100);
    l_appointment_date    DATE;
    l_appointment_id      NUMBER;
    l_duration_minutes    NUMBER;
    l_json_obj           JSON_OBJECT_T;
    l_result_obj         JSON_OBJECT_T;
    l_check_json         VARCHAR2(4000);
    l_check_result_obj   JSON_OBJECT_T;
    v_patient_exists     NUMBER;
    v_cancelled_appointment_id NUMBER;
    v_action_type        VARCHAR2(20) := 'CREATED'; -- Для отслеживания действия
BEGIN
    -- Проверка прав доступа
    IF auth_pkg.check_permission('HEAD_DOCTOR') THEN
        NULL;
    ELSIF auth_pkg.check_permission('REGISTRAR') THEN
        NULL;
    ELSE
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', -1);
        l_result_obj.put('message', 'Доступ запрещен');
          
        p_output_json := l_result_obj.to_clob();
        RETURN;
    END IF;
    
    -- Парсим входной JSON
    l_json_obj := JSON_OBJECT_T.parse(p_input_json);
    
    -- Извлекаем данные
    l_patient_id := l_json_obj.get_number('patient_id');
    l_doctor_id := l_json_obj.get_number('doctor_id');
    l_appointment_date_str := l_json_obj.get_string('appointment_date');
    
    -- Преобразуем строку в дату
    BEGIN
        l_appointment_date := TO_TIMESTAMP(l_appointment_date_str, 'YYYY-MM-DD"T"HH24:MI:SS');
    EXCEPTION
        WHEN OTHERS THEN
            l_appointment_date := TO_DATE(l_appointment_date_str, 'YYYY-MM-DD HH24:MI:SS');
    END;
    
    -- Получаем длительность приема для передачи в проверку
    BEGIN
        SELECT s.appointment_duration_minutes
        INTO l_duration_minutes
        FROM doctors d
        JOIN specialties s ON d.specialty_id = s.specialty_id
        WHERE d.doctor_id = l_doctor_id;
        
        IF l_duration_minutes IS NULL OR l_duration_minutes <= 0 THEN
            l_duration_minutes := 30; -- Значение по умолчанию
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            l_duration_minutes := 30; -- Значение по умолчанию
    END;
    
    -- Проверяем время с помощью существующей процедуры
    DECLARE
        l_check_input_json VARCHAR2(4000);
    BEGIN
        l_check_input_json := '{
            "doctor_id": ' || l_doctor_id || ',
            "appointment_date": "' || TO_CHAR(l_appointment_date, 'YYYY-MM-DD HH24:MI') || '"
        }';
        
        check_appointment_time_json(l_check_input_json, l_check_json);
        
        l_check_result_obj := JSON_OBJECT_T.parse(l_check_json);
        
        IF l_check_result_obj.get_number('return_code') != 0 THEN
            -- Возвращаем ошибку из проверки
            p_output_json := l_check_json;
            RETURN;
        END IF;
    END;
    
    -- Проверяем, что пациент существует
    SELECT COUNT(*) INTO v_patient_exists
    FROM patients
    WHERE patient_id = l_patient_id;
    
    IF v_patient_exists = 0 THEN
        RAISE_APPLICATION_ERROR(-20005, 'Пациент не найден');
    END IF;
    
    -- Проверяем, есть ли отмененная запись на это время
    BEGIN
        SELECT appointment_id INTO v_cancelled_appointment_id
        FROM appointments
        WHERE doctor_id = l_doctor_id
          AND appointment_date = l_appointment_date
          AND status = 'CANCELLED'
          AND ROWNUM = 1; -- Берем первую отмененную запись, если их несколько
        
        -- Нашли отмененную запись - обновляем ее
        UPDATE appointments
        SET patient_id = l_patient_id,
            status = 'SCHEDULED'
        WHERE appointment_id = v_cancelled_appointment_id
        RETURNING appointment_id INTO l_appointment_id;
        
        v_action_type := 'REUSED_CANCELLED';
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Нет отмененной записи - создаем новую
            INSERT INTO appointments (
                patient_id,
                doctor_id,
                appointment_date,
                status
            ) VALUES (
                l_patient_id,
                l_doctor_id,
                l_appointment_date,
                'SCHEDULED'
            )
            RETURNING appointment_id INTO l_appointment_id;
            
            v_action_type := 'CREATED_NEW';
    END;
    
    COMMIT;
    
    -- Формируем успешный ответ с информацией о действии
    l_result_obj := JSON_OBJECT_T();
    l_result_obj.put('return_code', 0);
    
    IF v_action_type = 'REUSED_CANCELLED' THEN
        l_result_obj.put('message', 'Запись успешно создана на месте отмененной записи');
    ELSE
        l_result_obj.put('message', 'Запись успешно создана');
    END IF;
    
    -- Возвращаем информацию о записи
    BEGIN
        -- Если была использована отмененная запись, возвращаем ее старый ID
        IF v_action_type = 'REUSED_CANCELLED' THEN
        l_result_obj.put('data', v_cancelled_appointment_id);
        END IF;
        
        l_result_obj.put('data', l_data_obj);
    END;
    
    p_output_json := l_result_obj.to_clob();
    
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', -1);
        l_result_obj.put('message', SQLERRM);
        p_output_json := l_result_obj.to_clob();
END create_appointment_json;
    PROCEDURE get_doctor_appointments_json(
        p_input_json  IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) AS
        l_doctor_id      NUMBER;
        l_start_date     DATE;
        l_end_date       DATE;
        l_cursor         SYS_REFCURSOR;
        l_json_array     JSON_ARRAY_T;
        l_json_obj       JSON_OBJECT_T;
        l_result_obj     JSON_OBJECT_T;
        v_appointment_id NUMBER;
        v_patient_id     NUMBER;
        v_doctor_id      NUMBER;
        v_appointment_date DATE;
        v_status         VARCHAR2(20);
        v_patient_name   VARCHAR2(255);
        v_doctor_name    VARCHAR2(255);
        v_phone          VARCHAR2(20);
        v_office_number  VARCHAR2(10);
    BEGIN
        -- Парсим входной JSON
        l_json_obj := JSON_OBJECT_T.parse(p_input_json);
        
        -- Извлекаем данные с проверкой наличия полей
        IF l_json_obj.has('doctor_id') THEN
            l_doctor_id := l_json_obj.get_number('doctor_id');
        ELSE
            l_doctor_id := NULL;
        END IF;
        
        IF l_json_obj.has('start_date') THEN
            l_start_date := TO_DATE(l_json_obj.get_string('start_date'), 'YYYY-MM-DD');
        ELSE
            l_start_date := TRUNC(SYSDATE);
        END IF;
        
        IF l_json_obj.has('end_date') THEN
            l_end_date := TO_DATE(l_json_obj.get_string('end_date'), 'YYYY-MM-DD');
        ELSE
            l_end_date := TRUNC(SYSDATE) + 7;
        END IF;
        
        -- Открываем курсор в зависимости от параметров
        IF l_doctor_id IS NOT NULL THEN
            OPEN l_cursor FOR
                SELECT 
                    a.appointment_id,
                    a.patient_id,
                    a.doctor_id,
                    a.appointment_date,
                    a.status,
                    p.last_name || ' ' || p.first_name || ' ' || COALESCE(p.middle_name, '') as patient_name,
                    d.last_name || ' ' || d.first_name || ' ' || COALESCE(d.middle_name, '') as doctor_name,
                    p.phone,
                    d.office_number
                FROM appointments a
                JOIN patients p ON a.patient_id = p.patient_id
                JOIN doctors d ON a.doctor_id = d.doctor_id
                WHERE a.doctor_id = l_doctor_id
                  AND TRUNC(a.appointment_date) >= l_start_date
                  AND TRUNC(a.appointment_date) <= l_end_date
                ORDER BY a.appointment_date;
        ELSE
            -- Для заведующего: все записи
            OPEN l_cursor FOR
                SELECT 
                    a.appointment_id,
                    a.patient_id,
                    a.doctor_id,
                    a.appointment_date,
                    a.status,
                    p.last_name || ' ' || p.first_name || ' ' || COALESCE(p.middle_name, '') as patient_name,
                    d.last_name || ' ' || d.first_name || ' ' || COALESCE(d.middle_name, '') as doctor_name,
                    p.phone,
                    d.office_number
                FROM appointments a
                JOIN patients p ON a.patient_id = p.patient_id
                JOIN doctors d ON a.doctor_id = d.doctor_id
                WHERE TRUNC(a.appointment_date) >= l_start_date
                  AND TRUNC(a.appointment_date) <= l_end_date
                ORDER BY a.appointment_date;
        END IF;
        
        l_json_array := JSON_ARRAY_T();
        
        LOOP
            FETCH l_cursor INTO 
                v_appointment_id,
                v_patient_id,
                v_doctor_id,
                v_appointment_date,
                v_status,
                v_patient_name,
                v_doctor_name,
                v_phone,
                v_office_number;
            EXIT WHEN l_cursor%NOTFOUND;
            
            l_json_obj := JSON_OBJECT_T();
            l_json_obj.put('appointment_id', v_appointment_id);
            l_json_obj.put('patient_id', v_patient_id);
            l_json_obj.put('doctor_id', v_doctor_id);
            l_json_obj.put('appointment_date', TO_CHAR(v_appointment_date, 'YYYY-MM-DD"T"HH24:MI:SS'));
            l_json_obj.put('status', v_status);
            l_json_obj.put('patient_name', v_patient_name);
            l_json_obj.put('doctor_name', v_doctor_name);
            l_json_obj.put('phone', v_phone);
            l_json_obj.put('office_number', v_office_number);
            
            l_json_array.append(l_json_obj);
        END LOOP;
        
        CLOSE l_cursor;
        
        -- Формируем результат
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', 0);
        l_result_obj.put('message', 'Success');
        l_result_obj.put('data', l_json_array);
        
        p_output_json := l_result_obj.to_clob();
        
    EXCEPTION
        WHEN OTHERS THEN
            IF l_cursor%ISOPEN THEN
                CLOSE l_cursor;
            END IF;
            
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', -1);
            l_result_obj.put('message', SQLERRM);
            l_result_obj.put('data', JSON_ARRAY_T());
            p_output_json := l_result_obj.to_clob();
    END get_doctor_appointments_json;
    
    PROCEDURE update_appointment_status_json(
        p_input_json  IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) AS
        l_appointment_id NUMBER;
        l_status        VARCHAR2(20);
        l_json_obj      JSON_OBJECT_T;
        l_result_obj    JSON_OBJECT_T;
        v_updated_count NUMBER;
    BEGIN
        -- Парсим входной JSON
        l_json_obj := JSON_OBJECT_T.parse(p_input_json);
        
      
        l_appointment_id := l_json_obj.get_number('appointment_id');
        l_status := l_json_obj.get_string('status');
        
        -- Проверяем допустимые статусы
        IF l_status NOT IN ('SCHEDULED', 'COMPLETED', 'CANCELLED') THEN
            RAISE_APPLICATION_ERROR(-20010, 'Недопустимый статус записи');
        END IF;
        
        
        
        -- Обновляем статус
        UPDATE appointments
        SET status = l_status
        WHERE appointment_id = l_appointment_id;
        
        v_updated_count := SQL%ROWCOUNT;
        
        IF v_updated_count = 0 THEN
            RAISE_APPLICATION_ERROR(-20011, 'Запись не найдена');
        END IF;
        
        COMMIT;
        
        -- Формируем результат
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', 0);
        l_result_obj.put('message', 'Статус записи обновлен');
        
        p_output_json := l_result_obj.to_clob();
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', -1);
            l_result_obj.put('message', SQLERRM);
            p_output_json := l_result_obj.to_clob();
    END update_appointment_status_json;
    
    PROCEDURE get_all_appointments_json(
        p_output_json OUT VARCHAR2
    ) AS
        l_cursor     SYS_REFCURSOR;
        l_json_array JSON_ARRAY_T;
        l_json_obj   JSON_OBJECT_T;
        l_result_obj JSON_OBJECT_T;
        v_appointment_id NUMBER;
        v_patient_id     NUMBER;
        v_doctor_id      NUMBER;
        v_appointment_date DATE;
        v_status         VARCHAR2(20);
        v_patient_name   VARCHAR2(255);
        v_doctor_name    VARCHAR2(255);
        v_phone          VARCHAR2(20);
        v_office_number  VARCHAR2(10);
    BEGIN
        OPEN l_cursor FOR
            SELECT 
                a.appointment_id,
                a.patient_id,
                a.doctor_id,
                a.appointment_date,
                a.status,
                p.last_name || ' ' || p.first_name || ' ' || COALESCE(p.middle_name, '') as patient_name,
                d.last_name || ' ' || d.first_name || ' ' || COALESCE(d.middle_name, '') as doctor_name,
                p.phone,
                d.office_number
            FROM appointments a
            JOIN patients p ON a.patient_id = p.patient_id
            JOIN doctors d ON a.doctor_id = d.doctor_id
            WHERE a.appointment_date >= TRUNC(SYSDATE) - 30
            ORDER BY a.appointment_date DESC;
        
        l_json_array := JSON_ARRAY_T();
        
        LOOP
            FETCH l_cursor INTO 
                v_appointment_id,
                v_patient_id,
                v_doctor_id,
                v_appointment_date,
                v_status,
                v_patient_name,
                v_doctor_name,
                v_phone,
                v_office_number;
            EXIT WHEN l_cursor%NOTFOUND;
            
            l_json_obj := JSON_OBJECT_T();
            l_json_obj.put('appointment_id', v_appointment_id);
            l_json_obj.put('patient_id', v_patient_id);
            l_json_obj.put('doctor_id', v_doctor_id);
            l_json_obj.put('appointment_date', TO_CHAR(v_appointment_date, 'YYYY-MM-DD"T"HH24:MI:SS'));
            l_json_obj.put('status', v_status);
            l_json_obj.put('patient_name', v_patient_name);
            l_json_obj.put('doctor_name', v_doctor_name);
            l_json_obj.put('phone', v_phone);
            l_json_obj.put('office_number', v_office_number);
            
            l_json_array.append(l_json_obj);
        END LOOP;
        
        CLOSE l_cursor;
        
        -- Формируем результат
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', 0);
        l_result_obj.put('message', 'Success');
        l_result_obj.put('data', l_json_array);
        
        p_output_json := l_result_obj.to_clob();
        
    EXCEPTION
        WHEN OTHERS THEN
            IF l_cursor%ISOPEN THEN
                CLOSE l_cursor;
            END IF;
            
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', -1);
            l_result_obj.put('message', SQLERRM);
            p_output_json := l_result_obj.to_clob();
    END get_all_appointments_json;
    
    PROCEDURE cancel_appointment_json(
        p_input_json  IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) AS
        l_appointment_id NUMBER;
        l_cancel_reason VARCHAR2(500);
        l_json_obj      JSON_OBJECT_T;
        l_result_obj    JSON_OBJECT_T;
        v_appointment_date DATE;
    BEGIN
        -- Парсим входной JSON
        l_json_obj := JSON_OBJECT_T.parse(p_input_json);
        
        l_appointment_id := l_json_obj.get_number('appointment_id');
      
        
        SELECT appointment_date INTO v_appointment_date
        FROM appointments
        WHERE appointment_id = l_appointment_id;
        
        -- Обновляем статус
        UPDATE appointments
        SET status = 'CANCELLED'
        WHERE appointment_id = l_appointment_id;
        
        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20021, 'Запись не найдена');
        END IF;
        
        COMMIT;
        
        -- Формируем результат
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', 0);
        l_result_obj.put('message', 'Запись успешно отменена');
        
        p_output_json := l_result_obj.to_clob();
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', -1);
            l_result_obj.put('message', 'Запись не найдена');
            p_output_json := l_result_obj.to_clob();
        WHEN OTHERS THEN
            ROLLBACK;
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', -1);
            l_result_obj.put('message', SQLERRM);
            p_output_json := l_result_obj.to_clob();
    END cancel_appointment_json;
    
    PROCEDURE get_appointment_by_id_json(
        p_input_json  IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) AS
        l_appointment_id NUMBER;
        l_json_obj      JSON_OBJECT_T;
        l_result_obj    JSON_OBJECT_T;
        v_appointment_id NUMBER;
        v_patient_id     NUMBER;
        v_doctor_id      NUMBER;
        v_appointment_date DATE;
        v_status         VARCHAR2(20);
        v_patient_name   VARCHAR2(255);
        v_doctor_name    VARCHAR2(255);
        v_patient_phone  VARCHAR2(20);
        v_doctor_phone   VARCHAR2(20);
        v_office_number  VARCHAR2(10);
        v_specialty_name VARCHAR2(100);
        v_duration_minutes NUMBER;
    BEGIN
        -- Парсим входной JSON
        l_json_obj := JSON_OBJECT_T.parse(p_input_json);
        
        l_appointment_id := l_json_obj.get_number('appointment_id');
        
        -- Получаем данные записи
        SELECT 
            a.appointment_id,
            a.patient_id,
            a.doctor_id,
            a.appointment_date,
            a.status,
            p.last_name || ' ' || p.first_name || ' ' || COALESCE(p.middle_name, '') as patient_name,
            d.last_name || ' ' || d.first_name || ' ' || COALESCE(d.middle_name, '') as doctor_name,
            p.phone as patient_phone,
            d.phone as doctor_phone,
            d.office_number,
            s.specialty_name,
            s.appointment_duration_minutes
        INTO 
            v_appointment_id,
            v_patient_id,
            v_doctor_id,
            v_appointment_date,
            v_status,
            v_patient_name,
            v_doctor_name,
            v_patient_phone,
            v_doctor_phone,
            v_office_number,
            v_specialty_name,
            v_duration_minutes
        FROM appointments a
        JOIN patients p ON a.patient_id = p.patient_id
        JOIN doctors d ON a.doctor_id = d.doctor_id
        JOIN specialties s ON d.specialty_id = s.specialty_id
        WHERE a.appointment_id = l_appointment_id;
        
        -- Формируем результат
        l_result_obj := JSON_OBJECT_T();
        l_result_obj.put('return_code', 0);
        l_result_obj.put('message', 'Success');
        
        l_json_obj := JSON_OBJECT_T();
        l_json_obj.put('appointment_id', v_appointment_id);
        l_json_obj.put('patient_id', v_patient_id);
        l_json_obj.put('doctor_id', v_doctor_id);
        l_json_obj.put('appointment_date', TO_CHAR(v_appointment_date, 'YYYY-MM-DD"T"HH24:MI:SS'));
        l_json_obj.put('status', v_status);
        l_json_obj.put('patient_name', v_patient_name);
        l_json_obj.put('doctor_name', v_doctor_name);
        l_json_obj.put('patient_phone', v_patient_phone);
        l_json_obj.put('doctor_phone', v_doctor_phone);
        l_json_obj.put('office_number', v_office_number);
        l_json_obj.put('specialty_name', v_specialty_name);
        l_json_obj.put('duration_minutes', v_duration_minutes);
        l_json_obj.put('appointment_end', 
            TO_CHAR(v_appointment_date + (v_duration_minutes / 1440), 'YYYY-MM-DD"T"HH24:MI:SS'));
        
        l_result_obj.put('data', l_json_obj);
        p_output_json := l_result_obj.to_clob();
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', -1);
            l_result_obj.put('message', 'Запись не найдена');
            p_output_json := l_result_obj.to_clob();
        WHEN OTHERS THEN
            l_result_obj := JSON_OBJECT_T();
            l_result_obj.put('return_code', -1);
            l_result_obj.put('message', SQLERRM);
            p_output_json := l_result_obj.to_clob();
    END get_appointment_by_id_json;
    
    PROCEDURE reschedule_appointment_json(
            p_input_json IN VARCHAR2,
            p_output_json OUT VARCHAR2
        ) IS
            v_appointment_id NUMBER;
            v_new_appointment_date DATE;
            v_doctor_id NUMBER;
            v_patient_id NUMBER;
            v_return_code NUMBER := 0;
            v_message VARCHAR2(255) := 'Appointment rescheduled successfully';
            v_current_user_id NUMBER;
            v_validation_result VARCHAR2(32767);
        BEGIN
            -- Парсим входной JSON
            SELECT 
                jt.appointment_id,
                TO_DATE(jt.new_appointment_date, 'YYYY-MM-DD"T"HH24:MI:SS')
            INTO 
                v_appointment_id,
                v_new_appointment_date
            FROM JSON_TABLE(p_input_json, '$'
                COLUMNS (
                    appointment_id NUMBER PATH '$.appointment_id',
                    new_appointment_date VARCHAR2(30) PATH '$.new_appointment_date'
                )
            ) jt;
            
            SELECT doctor_id, patient_id
            INTO v_doctor_id, v_patient_id
            FROM appointments
            WHERE appointment_id = v_appointment_id;
            
            IF auth_pkg.check_permission('HEAD_DOCTOR') THEN
                NULL;
            ELSIF auth_pkg.check_permission('REGISTRAR') THEN
                NULL;
            ELSE
                v_return_code := -1;
                v_message := 'Доступ запрещен';
                p_output_json := JSON_OBJECT(
                    'return_code' VALUE v_return_code,
                    'message' VALUE v_message
                );
                RETURN;
            END IF;
            
            -- Проверяем, что новое время не в прошлом
            IF v_new_appointment_date < SYSDATE THEN
                v_return_code := -1;
                v_message := 'Нельзя назначить прием на прошедшее время';
                p_output_json := JSON_OBJECT(
                    'return_code' VALUE v_return_code,
                    'message' VALUE v_message
                );
                RETURN;
            END IF;
            
            DECLARE
                v_check_input VARCHAR2(10000);
                v_check_output VARCHAR2(32767);
            BEGIN
                v_check_input := JSON_OBJECT(
                    'doctor_id' VALUE v_doctor_id,
                    'appointment_date' VALUE TO_CHAR(v_new_appointment_date, 'YYYY-MM-DD'),
                    'appointment_time' VALUE TO_CHAR(v_new_appointment_date, 'HH24:MI')
                );
                
                appointment_pkg_json.check_appointment_time_json(v_check_input, v_check_output);
                
                -- Парсим результат проверки
                DECLARE
                    v_check_obj JSON_OBJECT_T := JSON_OBJECT_T.parse(v_check_output);
                    v_is_valid NUMBER;
                BEGIN
                    v_is_valid := v_check_obj.get_number('is_valid');
                    IF v_is_valid = 0 THEN
                        v_return_code := -1;
                        v_message := v_check_obj.get_string('message');
                        p_output_json := JSON_OBJECT(
                            'return_code' VALUE v_return_code,
                            'message' VALUE v_message
                        );
                        RETURN;
                    END IF;
                END;
            END;
            
            UPDATE appointments
            SET appointment_date = v_new_appointment_date,
                status = 'RESCHEDULED'
            WHERE appointment_id = v_appointment_id;
            
            IF SQL%ROWCOUNT = 0 THEN
                v_return_code := -1;
                v_message := 'Прием не найден';
            END IF;
            
            COMMIT;
            
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message
            );
            
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_return_code := -1;
                v_message := 'Прием не найден';
                p_output_json := JSON_OBJECT(
                    'return_code' VALUE v_return_code,
                    'message' VALUE v_message
                );
            WHEN OTHERS THEN
                ROLLBACK;
                v_return_code := -1;
                v_message := 'System error: ' || SQLERRM;
                p_output_json := JSON_OBJECT(
                    'return_code' VALUE v_return_code,
                    'message' VALUE v_message
                );
        END reschedule_appointment_json;
        
END appointment_pkg_json;
/
CREATE OR REPLACE PACKAGE patient_pkg_json IS 
    PROCEDURE add_patient_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    PROCEDURE update_patient_json(
    p_input_json IN VARCHAR2,
    p_output_json OUT VARCHAR2
    );
    PROCEDURE delete_patient_json(
    p_input_json IN VARCHAR2,
    p_output_json OUT VARCHAR2
    );

    PROCEDURE get_all_patients_json(
        p_output_json OUT VARCHAR2
    );
    
    PROCEDURE find_patient_by_name_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    PROCEDURE get_patient_by_id_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
END patient_pkg_json;
/
CREATE OR REPLACE PACKAGE BODY patient_pkg_json  IS

    -- Обновление данных пациента
  PROCEDURE update_patient_json(
      p_input_json IN VARCHAR2,
      p_output_json OUT VARCHAR2
  ) IS
      v_patient_id NUMBER;
      v_last_name VARCHAR2(100);
      v_first_name VARCHAR2(100);
      v_middle_name VARCHAR2(100);
      v_birth_date DATE;
      v_gender VARCHAR2(1);
      v_address VARCHAR2(200);
      v_phone VARCHAR2(20);
      v_passport VARCHAR2(20);
      v_return_code NUMBER := 0;
      v_message VARCHAR2(255) := 'Patient updated successfully';
  BEGIN
      -- Проверка прав доступа - только HEAD_DOCTOR может редактировать
      IF NOT auth_pkg.check_permission('HEAD_DOCTOR') AND NOT auth_pkg.check_permission('REGISTRAR') THEN
          v_return_code := -1;
          v_message := 'Доступ запрещен: требуется роль заведующего или регистратора';
          p_output_json := JSON_OBJECT('return_code' VALUE v_return_code, 'message' VALUE v_message);
          RETURN;
      END IF;
      
      -- Парсим входной JSON
      SELECT 
          jt.patient_id,
          jt.last_name,
          jt.first_name,
          jt.middle_name,
          TO_DATE(jt.birth_date, 'YYYY-MM-DD'),
          jt.gender,
          jt.address,
          jt.phone,
          jt.passport_series_number
      INTO 
          v_patient_id,
          v_last_name,
          v_first_name,
          v_middle_name,
          v_birth_date,
          v_gender,
          v_address,
          v_phone,
          v_passport
      FROM JSON_TABLE(p_input_json, '$'
          COLUMNS (
              patient_id NUMBER PATH '$.patient_id',
              last_name VARCHAR2(100) PATH '$.last_name',
              first_name VARCHAR2(100) PATH '$.first_name',
              middle_name VARCHAR2(100) PATH '$.middle_name',
              birth_date VARCHAR2(10) PATH '$.birth_date',
              gender VARCHAR2(1) PATH '$.gender',
              address VARCHAR2(200) PATH '$.address',
              phone VARCHAR2(20) PATH '$.phone',
              passport_series_number VARCHAR2(20) PATH '$.passport_series_number'
          )
      ) jt;
  
      -- Обновление пациента
      UPDATE patients
      SET last_name = v_last_name,
          first_name = v_first_name,
          middle_name = v_middle_name,
          birth_date = v_birth_date,
          gender = v_gender,
          address = v_address,
          phone = v_phone,
          passport_series_number = v_passport
      WHERE patient_id = v_patient_id;
      
      IF SQL%ROWCOUNT = 0 THEN
          v_return_code := -1;
          v_message := 'Patient not found';
      END IF;
      
      COMMIT;
      
      -- Формируем успешный ответ
      p_output_json := JSON_OBJECT(
          'return_code' VALUE v_return_code,
          'message' VALUE v_message
      );
      
  EXCEPTION
      WHEN DUP_VAL_ON_INDEX THEN
          ROLLBACK;
          v_return_code := -1;
          v_message := 'Пациент с таким телефоном или паспортом уже существует';
          p_output_json := JSON_OBJECT(
              'return_code' VALUE v_return_code,
              'message' VALUE v_message
          );
      WHEN OTHERS THEN
          ROLLBACK;
          v_return_code := -1;
          v_message := 'System error: ' || SQLERRM;
          p_output_json := JSON_OBJECT(
              'return_code' VALUE v_return_code,
              'message' VALUE v_message
          );
  END update_patient_json;
  
  -- Удаление пациента
  PROCEDURE delete_patient_json(
      p_input_json IN VARCHAR2,
      p_output_json OUT VARCHAR2
  ) IS
      v_patient_id NUMBER;
      v_return_code NUMBER := 0;
      v_message VARCHAR2(255) := 'Patient deleted successfully';
      v_appointment_count NUMBER;
      v_medical_record_count NUMBER;
      v_test_result_count NUMBER;
  BEGIN
      -- Проверка прав доступа - только HEAD_DOCTOR может удалять
      IF NOT auth_pkg.check_permission('HEAD_DOCTOR') AND NOT auth_pkg.check_permission('REGISTRAR') THEN
          v_return_code := -1;
          v_message := 'Доступ запрещен: требуется роль заведующего';
          p_output_json := JSON_OBJECT('return_code' VALUE v_return_code, 'message' VALUE v_message);
          RETURN;
      END IF;
      
      -- Парсим входной JSON
      SELECT jt.patient_id
      INTO v_patient_id
      FROM JSON_TABLE(p_input_json, '$'
          COLUMNS (
              patient_id NUMBER PATH '$.patient_id'
          )
      ) jt;
  
      -- Проверяем, есть ли связанные записи
      -- Приемы
      SELECT COUNT(*) INTO v_appointment_count
      FROM appointments
      WHERE patient_id = v_patient_id;
      
      -- Медицинские записи
      SELECT COUNT(*) INTO v_medical_record_count
      FROM medical_records 
      WHERE patient_id = v_patient_id;
      
      -- Результаты анализов
      SELECT COUNT(*) INTO v_test_result_count
      FROM admin.masked_test_results
      WHERE patient_id = v_patient_id;
      
      -- Если есть связанные записи, запрещаем удаление
      IF v_appointment_count > 0 OR v_medical_record_count > 0 OR v_test_result_count > 0 THEN
          v_return_code := -1;
          v_message := 'Нельзя удалить пациента. Существуют связанные записи: ' ||
                       CASE 
                           WHEN v_appointment_count > 0 THEN 'приемы (' || v_appointment_count || '), '
                           ELSE ''
                       END ||
                       CASE 
                           WHEN v_medical_record_count > 0 THEN 'медицинские записи (' || v_medical_record_count || '), '
                           ELSE ''
                       END ||
                       CASE 
                           WHEN v_test_result_count > 0 THEN 'результаты анализов (' || v_test_result_count || ')'
                           ELSE ''
                       END;
          p_output_json := JSON_OBJECT(
              'return_code' VALUE v_return_code,
              'message' VALUE v_message
          );
          RETURN;
      END IF;
      
      -- Удаление пациента
      DELETE FROM patients
      WHERE patient_id = v_patient_id;
      
      IF SQL%ROWCOUNT = 0 THEN
          v_return_code := -1;
          v_message := 'Patient not found';
      END IF;
      
      COMMIT;
      
      -- Формируем успешный ответ
      p_output_json := JSON_OBJECT(
          'return_code' VALUE v_return_code,
          'message' VALUE v_message
      );
      
  EXCEPTION
      WHEN OTHERS THEN
          ROLLBACK;
          v_return_code := -1;
          v_message := 'System error: ' || SQLERRM;
          p_output_json := JSON_OBJECT(
              'return_code' VALUE v_return_code,
              'message' VALUE v_message
          );
  END delete_patient_json;
    PROCEDURE add_patient_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_last_name VARCHAR2(100);
        v_first_name VARCHAR2(100);
        v_middle_name VARCHAR2(100);
        v_birth_date DATE;
        v_gender VARCHAR2(1);
        v_address VARCHAR2(200);
        v_phone VARCHAR2(20);
        v_passport VARCHAR2(20);
        v_patient_id NUMBER;
        v_return_code NUMBER := 0;
        v_message VARCHAR2(255) := 'Patient added successfully';
    BEGIN
        -- Проверка прав доступа
        IF NOT auth_pkg.check_permission('REGISTRAR') 
           AND NOT auth_pkg.check_permission('HEAD_DOCTOR') THEN
            v_return_code := -1;
            v_message := 'Доступ запрещен: требуется роль регистратора или заведующего';
            p_output_json := JSON_OBJECT('return_code' VALUE v_return_code, 'message' VALUE v_message);
            RETURN;
        END IF;
        
        -- Парсим входной JSON
        SELECT 
            jt.last_name,
            jt.first_name,
            jt.middle_name,
            TO_DATE(jt.birth_date, 'YYYY-MM-DD'),
            jt.gender,
            jt.address,
            jt.phone,
            jt.passport_series_number
        INTO 
            v_last_name,
            v_first_name,
            v_middle_name,
            v_birth_date,
            v_gender,
            v_address,
            v_phone,
            v_passport
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                last_name VARCHAR2(100) PATH '$.last_name',
                first_name VARCHAR2(100) PATH '$.first_name',
                middle_name VARCHAR2(100) PATH '$.middle_name',
                birth_date VARCHAR2(10) PATH '$.birth_date',
                gender VARCHAR2(1) PATH '$.gender',
                address VARCHAR2(200) PATH '$.address',
                phone VARCHAR2(20) PATH '$.phone',
                passport_series_number VARCHAR2(20) PATH '$.passport_series_number'
            )
        ) jt;

        -- Вставка пациента
        INSERT INTO patients (
            last_name, first_name, middle_name, birth_date,
            gender, address, phone, passport_series_number
        ) VALUES (
            v_last_name, v_first_name, v_middle_name, v_birth_date,
            v_gender, v_address, v_phone, v_passport
        ) RETURNING patient_id INTO v_patient_id;
        
        COMMIT;
        
        -- Формируем успешный ответ
        p_output_json := JSON_OBJECT(
            'return_code' VALUE v_return_code,
            'message' VALUE v_message,
            'patient_id' VALUE v_patient_id
        );
        
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            ROLLBACK;
            v_return_code := -1;
            v_message := 'Пациент с таким телефоном или паспортом уже существует';
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message
            );
        WHEN OTHERS THEN
            ROLLBACK;
            v_return_code := -1;
            v_message := 'System error: ' || SQLERRM;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message
            );
    END add_patient_json;
    
    PROCEDURE get_all_patients_json(
        p_output_json OUT VARCHAR2
    ) IS
        v_json_clob CLOB;
    BEGIN
        
        SELECT JSON_ARRAYAGG(
            JSON_OBJECT(
                'patient_id' VALUE patient_id,
                'last_name' VALUE last_name,
                'first_name' VALUE first_name,
                'middle_name' VALUE middle_name,
                'birth_date' VALUE TO_CHAR(birth_date, 'YYYY-MM-DD'),
                'gender' VALUE gender,
                'address' VALUE address,
                'phone' VALUE phone,
                'passport_series_number' VALUE passport_series_number
                )
        ) INTO v_json_clob
        FROM admin.masked_patients
        ORDER BY last_name, first_name;
        
        p_output_json := JSON_OBJECT(
            'return_code' VALUE 0,
            'message' VALUE 'Success',
            'data' VALUE JSON_QUERY(NVL(v_json_clob, '[]'), '$')
        );
        
    EXCEPTION
        WHEN OTHERS THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'System error: ' || SQLERRM,
                'data' VALUE '[]'
            );
    END get_all_patients_json;
    
    PROCEDURE find_patient_by_name_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_last_name VARCHAR2(100);
        v_first_name VARCHAR2(100);
        v_middle_name VARCHAR2(100);
        v_json_clob CLOB;
    BEGIN
        IF NOT auth_pkg.check_permission('REGISTRAR') 
           AND NOT auth_pkg.check_permission('HEAD_DOCTOR')
           AND NOT auth_pkg.check_permission('DOCTOR') THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'Доступ запрещен',
                'data' VALUE '[]'
            );
            RETURN;
        END IF;
        
        -- Парсим входной JSON
        BEGIN
            SELECT 
                jt.last_name,
                jt.first_name,
                jt.middle_name
            INTO 
                v_last_name,
                v_first_name,
                v_middle_name
            FROM JSON_TABLE(p_input_json, '$'
                COLUMNS (
                    last_name VARCHAR2(100) PATH '$.last_name',
                    first_name VARCHAR2(100) PATH '$.first_name',
                    middle_name VARCHAR2(100) PATH '$.middle_name'
                )
            ) jt;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_last_name := NULL;
                v_first_name := NULL;
                v_middle_name := NULL;
        END;
        
        SELECT JSON_ARRAYAGG(
            JSON_OBJECT(
                'patient_id' VALUE patient_id,
                'last_name' VALUE last_name,
                'first_name' VALUE first_name,
                'middle_name' VALUE middle_name,
                'birth_date' VALUE TO_CHAR(birth_date, 'YYYY-MM-DD'),
                'gender' VALUE gender,
                'address' VALUE address,
                'phone' VALUE phone,
                'passport_series_number' VALUE passport_series_number
                )
        ) INTO v_json_clob
        FROM admin.masked_patients
        WHERE (v_last_name IS NULL OR UPPER(last_name) LIKE '%' || UPPER(v_last_name) || '%')
          AND (v_first_name IS NULL OR UPPER(first_name) LIKE '%' || UPPER(v_first_name) || '%')
          AND (v_middle_name IS NULL OR UPPER(middle_name) LIKE '%' || UPPER(v_middle_name) || '%')
        ORDER BY last_name, first_name;
        
        p_output_json := JSON_OBJECT(
            'return_code' VALUE 0,
            'message' VALUE 'Success',
            'data' VALUE JSON_QUERY(NVL(v_json_clob, '[]'), '$')
        );
        
    EXCEPTION
        WHEN OTHERS THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'System error: ' || SQLERRM,
                'data' VALUE '[]'
            );
    END find_patient_by_name_json;
    
    PROCEDURE get_patient_by_id_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_patient_id NUMBER;
        v_json_obj CLOB;
    BEGIN
        IF NOT auth_pkg.check_permission('REGISTRAR') 
           AND NOT auth_pkg.check_permission('HEAD_DOCTOR')
           AND NOT auth_pkg.check_permission('DOCTOR') THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'Доступ запрещен',
                'data' VALUE NULL
            );
            RETURN;
        END IF;
        
        -- Парсим входной JSON
        SELECT jt.patient_id
        INTO v_patient_id
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                patient_id NUMBER PATH '$.patient_id'
            )
        ) jt;
        
        SELECT JSON_OBJECT(
            'patient_id' VALUE patient_id,
            'last_name' VALUE last_name,
            'first_name' VALUE first_name,
            'middle_name' VALUE middle_name,
            'birth_date' VALUE TO_CHAR(birth_date, 'YYYY-MM-DD'),
            'gender' VALUE gender,
            'address' VALUE address,
            'phone' VALUE phone,
            'passport_series_number' VALUE passport_series_number
            ) INTO v_json_obj
        FROM admin.masked_patients
        WHERE patient_id = v_patient_id;
        
        p_output_json := JSON_OBJECT(
            'return_code' VALUE 0,
            'message' VALUE 'Success',
            'data' VALUE JSON_QUERY(v_json_obj, '$')
        );
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'Пациент не найден',
                'data' VALUE NULL
            );
        WHEN OTHERS THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'System error: ' || SQLERRM,
                'data' VALUE NULL
            );
    END get_patient_by_id_json;
    
END patient_pkg_json;
/
CREATE OR REPLACE PACKAGE doctor_management_pkg_json IS
    -- Добавление врача через JSON
    PROCEDURE add_doctor_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    PROCEDURE update_doctor_credentials_json(
    p_input_json IN VARCHAR2,
    p_output_json OUT VARCHAR2
    );
    PROCEDURE get_doctor_credentials_json(
    p_input_json IN VARCHAR2,
    p_output_json OUT VARCHAR2
    );
    PROCEDURE get_doctor_by_id_json(
    p_input_json IN VARCHAR2,
    p_output_json OUT VARCHAR2
    );
    PROCEDURE update_doctor_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    PROCEDURE delete_doctor_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) ;
    -- Получение списка врачей через JSON
    PROCEDURE get_doctors_list(
    p_result_cursor OUT SYS_REFCURSOR
    );
    
    -- Получение специальностей через JSON
    PROCEDURE get_specialties_json(
        p_output_json OUT VARCHAR2
    );
    
END doctor_management_pkg_json;
/
CREATE OR REPLACE PACKAGE BODY doctor_management_pkg_json IS
        
      PROCEDURE update_doctor_credentials_json(
      p_input_json IN VARCHAR2,
      p_output_json OUT VARCHAR2
  ) IS
      v_doctor_id NUMBER;
      v_username VARCHAR2(50);
      v_password VARCHAR2(100);
      v_return_code NUMBER := 0;
      v_message VARCHAR2(255) := 'Doctor credentials updated successfully';
      v_user_id NUMBER;
      v_encrypted_password RAW(256);
  BEGIN
      IF NOT auth_pkg.check_permission('HEAD_DOCTOR') THEN
          v_return_code := -1;
          v_message := 'Доступ запрещен: требуется роль заведующего';
          p_output_json := JSON_OBJECT('return_code' VALUE v_return_code,
                      'message' VALUE v_message);
          RETURN;
      END IF;
      
      SELECT 
          jt.doctor_id,
          jt.username,
          jt.password
      INTO 
          v_doctor_id,
          v_username,
          v_password
      FROM JSON_TABLE(p_input_json, '$'
          COLUMNS (
              doctor_id NUMBER PATH '$.doctor_id',
              username VARCHAR2(50) PATH '$.username',
              password VARCHAR2(100) PATH '$.password'
          )
      ) jt;
      
      BEGIN
          SELECT user_id INTO v_user_id
          FROM app_users
          WHERE doctor_id = v_doctor_id;
          
          IF v_user_id IS NULL THEN
              RAISE NO_DATA_FOUND;
          END IF;
      EXCEPTION
          WHEN NO_DATA_FOUND THEN
              v_return_code := -1;
              v_message := 'User account not found for this doctor';
              p_output_json := JSON_OBJECT(
                  'return_code' VALUE v_return_code,
                  'message' VALUE v_message
              );
              RETURN;
      END;
      
      IF v_username IS NOT NULL THEN
          DECLARE
              v_existing_user_id NUMBER;
          BEGIN
              SELECT user_id INTO v_existing_user_id
              FROM app_users
              WHERE username = v_username
                AND user_id != v_user_id
                AND ROWNUM = 1;
              
              v_return_code := -1;
              v_message := 'Username already exists';
              p_output_json := JSON_OBJECT(
                  'return_code' VALUE v_return_code,
                  'message' VALUE v_message
              );
              RETURN;
          EXCEPTION
              WHEN NO_DATA_FOUND THEN
                  NULL; 
          END;
          
          UPDATE app_users
          SET username = v_username
          WHERE user_id = v_user_id;
          COMMIT;
      END IF;
      IF v_password IS NOT NULL THEN
          v_encrypted_password := auth_pkg.encrypt_password(v_password);
          
          UPDATE app_users
          SET encrypted_password = v_encrypted_password
          WHERE user_id = v_user_id;
      END IF;
      COMMIT;
      
      p_output_json := JSON_OBJECT(
          'return_code' VALUE v_return_code,
          'message' VALUE v_message
      );

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            v_return_code := -1;
            v_message := 'System error: ' || SQLERRM;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message
            );
    END update_doctor_credentials_json;
    

      PROCEDURE get_doctor_credentials_json(
          p_input_json IN VARCHAR2,
          p_output_json OUT VARCHAR2
      ) IS
          v_doctor_id NUMBER;
          v_username VARCHAR2(50);
          v_return_code NUMBER := 0;
          v_message VARCHAR2(255) := 'Success';
      BEGIN
          IF NOT auth_pkg.check_permission('HEAD_DOCTOR') THEN
              v_return_code := -1;
              v_message := 'Доступ запрещен: требуется роль заведующего';
              p_output_json := JSON_OBJECT('return_code' VALUE v_return_code,
                          'message' VALUE v_message);
              RETURN;
          END IF;
          
          -- Парсим входной JSON
          SELECT jt.doctor_id INTO v_doctor_id
          FROM JSON_TABLE(p_input_json, '$'
              COLUMNS (doctor_id NUMBER PATH '$.doctor_id')
          ) jt;
          
          -- Получаем логин пользователя
          SELECT username INTO v_username
          FROM app_users
          WHERE doctor_id = v_doctor_id;
          
          p_output_json := JSON_OBJECT(
              'return_code' VALUE v_return_code,
              'message' VALUE v_message,
              'data' VALUE JSON_OBJECT(
                  'username' VALUE v_username
              )
          );
          
      EXCEPTION
          WHEN NO_DATA_FOUND THEN
              v_return_code := -1;
              v_message := 'User account not found for this doctor';
              p_output_json := JSON_OBJECT(
                  'return_code' VALUE v_return_code,
                  'message' VALUE v_message,
                  'data' VALUE NULL
              );
          WHEN OTHERS THEN
              v_return_code := -1;
              v_message := 'System error: ' || SQLERRM;
              p_output_json := JSON_OBJECT(
                  'return_code' VALUE v_return_code,
                  'message' VALUE v_message,
                  'data' VALUE NULL
              );
      END get_doctor_credentials_json;
    PROCEDURE get_doctor_by_id_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_json_clob CLOB;
        v_doctor_id NUMBER;
    BEGIN
        -- Парсим входной JSON для получения doctor_id
        SELECT jt.doctor_id INTO v_doctor_id
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (doctor_id NUMBER PATH '$.doctor_id')
        ) jt;
    
        -- Получаем данные конкретного врача
        SELECT JSON_OBJECT(
                   'doctor_id' VALUE d.doctor_id,
                   'last_name' VALUE d.last_name,
                   'first_name' VALUE d.first_name,
                   'middle_name' VALUE d.middle_name,
                   'specialty_id' VALUE d.specialty_id,
                   'specialty_name' VALUE s.specialty_name,
                   'office_number' VALUE d.office_number,
                   'phone' VALUE d.phone,
                   'passport_series_number' VALUE d.passport_series_number
               ) INTO v_json_clob
        FROM admin.masked_doctors d
        JOIN specialties s ON d.specialty_id = s.specialty_id
        WHERE d.doctor_id = v_doctor_id;
        
        p_output_json := JSON_OBJECT(
            'return_code' VALUE 0,
            'message' VALUE 'Success',
            'data' VALUE JSON_QUERY(NVL(v_json_clob, '{}'), '$')
        );
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'Doctor not found',
                'data' VALUE NULL
            );
        WHEN OTHERS THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'System error: ' || SQLERRM,
                'data' VALUE NULL
            );
    END get_doctor_by_id_json;
    
    PROCEDURE update_doctor_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_doctor_id NUMBER;
        v_last_name VARCHAR2(100);
        v_first_name VARCHAR2(100);
        v_middle_name VARCHAR2(100);
        v_specialty_id NUMBER;
        v_office_number VARCHAR2(20);
        v_phone VARCHAR2(20);
        v_passport VARCHAR2(20);
        v_return_code NUMBER := 0;
        v_message VARCHAR2(255) := 'Doctor updated successfully';
    BEGIN
        IF NOT auth_pkg.check_permission('HEAD_DOCTOR') THEN
            v_return_code := -1;
            v_message := 'Доступ запрещен: требуется роль заведующего';
            p_output_json := JSON_OBJECT('return_code' VALUE v_return_code,
                        'message' VALUE v_message);
            RETURN;
        END IF;
        
        -- Парсим входной JSON
        SELECT 
            jt.doctor_id,
            jt.last_name,
            jt.first_name,
            jt.middle_name,
            jt.specialty_id,
            jt.office_number,
            jt.phone,
            jt.passport_series_number
        INTO 
            v_doctor_id,
            v_last_name,
            v_first_name,
            v_middle_name,
            v_specialty_id,
            v_office_number,
            v_phone,
            v_passport
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                doctor_id NUMBER PATH '$.doctor_id',
                last_name VARCHAR2(100) PATH '$.last_name',
                first_name VARCHAR2(100) PATH '$.first_name',
                middle_name VARCHAR2(100) PATH '$.middle_name',
                specialty_id NUMBER PATH '$.specialty_id',
                office_number VARCHAR2(20) PATH '$.office_number',
                phone VARCHAR2(20) PATH '$.phone',
                passport_series_number VARCHAR2(20) PATH '$.passport_series_number'
            )
        ) jt;
        
        -- Обновляем данные врача
        UPDATE doctors
        SET last_name = v_last_name,
            first_name = v_first_name,
            middle_name = v_middle_name,
            specialty_id = v_specialty_id,
            office_number = v_office_number,
            phone = v_phone,
            passport_series_number = v_passport
        WHERE doctor_id = v_doctor_id;
        
        IF SQL%ROWCOUNT = 0 THEN
            v_return_code := -1;
            v_message := 'Doctor not found';
        END IF;
        
        COMMIT;
        
        p_output_json := JSON_OBJECT(
            'return_code' VALUE v_return_code,
            'message' VALUE v_message
        );
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            v_return_code := -1;
            v_message := 'System error: ' || SQLERRM;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message
            );
    END update_doctor_json;
    
    PROCEDURE delete_doctor_json(
    p_input_json IN VARCHAR2,
    p_output_json OUT VARCHAR2
) IS
    v_doctor_id NUMBER;
    v_return_code NUMBER := 0;
    v_message VARCHAR2(255) := 'Doctor deleted successfully';
    v_deleted_count NUMBER := 0;
BEGIN
    IF NOT auth_pkg.check_permission('HEAD_DOCTOR') THEN
        v_return_code := -1;
        v_message := 'Доступ запрещен: требуется роль заведующего';
        p_output_json := JSON_OBJECT('return_code' VALUE v_return_code,
                    'message' VALUE v_message);
        RETURN;
    END IF;
    
    -- Парсим входной JSON для получения doctor_id
    SELECT jt.doctor_id INTO v_doctor_id
    FROM JSON_TABLE(p_input_json, '$'
        COLUMNS (doctor_id NUMBER PATH '$.doctor_id')
    ) jt;
    
    DELETE FROM doctors WHERE doctor_id = v_doctor_id;
    
    IF SQL%ROWCOUNT = 0 THEN
        v_return_code := -1;
        v_message := 'Doctor not found';
        p_output_json := JSON_OBJECT(
            'return_code' VALUE v_return_code,
            'message' VALUE v_message
        );
        RETURN;
    END IF;
    
    COMMIT;
    
    p_output_json := JSON_OBJECT(
        'return_code' VALUE v_return_code,
        'message' VALUE v_message
    );
    
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        v_return_code := -1;
        v_message := 'System error: ' || SQLERRM;
        p_output_json := JSON_OBJECT(
            'return_code' VALUE v_return_code,
            'message' VALUE v_message
        );
END delete_doctor_json;

    PROCEDURE add_doctor_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_last_name VARCHAR2(100);
        v_first_name VARCHAR2(100);
        v_middle_name VARCHAR2(100);
        v_specialty_id NUMBER;
        v_office_number VARCHAR2(20);
        v_phone VARCHAR2(20);
        v_passport VARCHAR2(20);
        v_username VARCHAR2(50);
        v_password VARCHAR2(100);
        v_doctor_id NUMBER;
        v_return_code NUMBER := 0;
        v_message VARCHAR2(255) := 'Doctor added successfully';
        v_register_input VARCHAR2(1000);
        v_register_output VARCHAR2(32767);
    BEGIN
        IF NOT auth_pkg.check_permission('HEAD_DOCTOR') THEN
            v_return_code := -1;
            v_message := 'Доступ запрещен: требуется роль заведующего';
            p_output_json := JSON_OBJECT('return_code' VALUE v_return_code,
                        'message' VALUE v_message);
            RETURN;
        END IF;
        
        -- Парсим входной JSON
        SELECT 
            jt.last_name,
            jt.first_name,
            jt.middle_name,
            jt.specialty_id,
            jt.office_number,
            jt.phone,
            jt.passport_series_number,
            jt.username,
            jt.password
        INTO 
            v_last_name,
            v_first_name,
            v_middle_name,
            v_specialty_id,
            v_office_number,
            v_phone,
            v_passport,
            v_username,
            v_password
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                last_name VARCHAR2(100) PATH '$.last_name',
                first_name VARCHAR2(100) PATH '$.first_name',
                middle_name VARCHAR2(100) PATH '$.middle_name',
                specialty_id NUMBER PATH '$.specialty_id',
                office_number VARCHAR2(20) PATH '$.office_number',
                phone VARCHAR2(20) PATH '$.phone',
                passport_series_number VARCHAR2(20) PATH '$.passport_series_number',
                username VARCHAR2(50) PATH '$.username',
                password VARCHAR2(100) PATH '$.password'
            )
        ) jt;
        
        -- Вставка врача
        INSERT INTO doctors (
            last_name, first_name, middle_name, 
            specialty_id, office_number, phone, passport_series_number
        ) VALUES (
            v_last_name, v_first_name, v_middle_name, 
            v_specialty_id, v_office_number, v_phone, v_passport
        ) RETURNING doctor_id INTO v_doctor_id;
        
        -- Регистрация пользователя для врача
        v_register_input := JSON_OBJECT(
            'username' VALUE v_username,
            'password' VALUE v_password,
            'role' VALUE 'DOCTOR'
        );
        
        auth_pkg.register_user(v_register_input, v_register_output);
        
        UPDATE app_users 
        SET doctor_id = v_doctor_id
        WHERE username = v_username;
        
        COMMIT;
        
        p_output_json := JSON_OBJECT(
            'return_code' VALUE v_return_code,
            'message' VALUE v_message,
            'doctor_id' VALUE v_doctor_id
        );
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            v_return_code := -1;
            v_message := 'System error: ' || SQLERRM;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message
            );
    END add_doctor_json;
    
    PROCEDURE get_doctors_list(
    p_result_cursor OUT SYS_REFCURSOR
) IS
BEGIN
    -- Открываем курсор со списком врачей
    OPEN p_result_cursor FOR
    SELECT 
        d.doctor_id,
        d.last_name,
        d.first_name,
        d.middle_name,
        d.specialty_id,
        s.specialty_name,
        d.office_number,
        d.phone,
        d.passport_series_number
    FROM admin.masked_doctors d
    JOIN specialties s ON d.specialty_id = s.specialty_id
    ORDER BY d.last_name, d.first_name, d.middle_name;
    
EXCEPTION
    WHEN OTHERS THEN
        -- В случае ошибки открываем пустой курсор
        OPEN p_result_cursor FOR
        SELECT 
            NULL as doctor_id,
            NULL as last_name,
            NULL as first_name,
            NULL as middle_name,
            NULL as specialty_id,
            NULL as specialty_name,
            NULL as office_number,
            NULL as phone,
            NULL as passport_series_number
        FROM DUAL WHERE 1=0;
END get_doctors_list;

    PROCEDURE get_specialties_json(
        p_output_json OUT VARCHAR2
    ) IS
        v_json_clob CLOB;
    BEGIN
        -- Доступно всем ролям
        SELECT JSON_ARRAYAGG(
            JSON_OBJECT(
                'specialty_id' VALUE specialty_id,
                'specialty_name' VALUE specialty_name,
                'appointment_duration_minutes' VALUE appointment_duration_minutes
            )
        ) INTO v_json_clob
        FROM specialties
        ORDER BY specialty_name;
        
        p_output_json := JSON_OBJECT(
            'return_code' VALUE 0,
            'message' VALUE 'Success',
            'data' VALUE JSON_QUERY(NVL(v_json_clob, '[]'), '$')
        );
        
    EXCEPTION
        WHEN OTHERS THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'System error: ' || SQLERRM,
                'data' VALUE '[]'
            );
    END get_specialties_json;
    
END doctor_management_pkg_json;
/
CREATE OR REPLACE PACKAGE medical_record_pkg_json IS
    PROCEDURE create_medical_record_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    PROCEDURE get_doctor_records_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    PROCEDURE get_patient_records_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    PROCEDURE get_medical_record_by_id_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    PROCEDURE update_medical_record_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    PROCEDURE delete_medical_record_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    PROCEDURE get_all_medical_records(
    p_result_cursor OUT SYS_REFCURSOR
);
END medical_record_pkg_json;
/

CREATE OR REPLACE PACKAGE BODY medical_record_pkg_json IS
    
    PROCEDURE create_medical_record_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_diagnosis CLOB;
        v_prescription CLOB;
        v_notes CLOB;
        v_record_id NUMBER;
        v_patient_id NUMBER;
        v_doctor_id NUMBER;
        v_return_code NUMBER := 0;
        v_message VARCHAR2(255) := 'Medical record created successfully';
    BEGIN
        -- Проверка прав доступа
        IF NOT auth_pkg.check_permission('DOCTOR') 
           AND NOT auth_pkg.check_permission('HEAD_DOCTOR') THEN
            v_return_code := -1;
            v_message := 'Доступ запрещен: требуется роль врача или заведующего';
            p_output_json := JSON_OBJECT('return_code' VALUE v_return_code, 'message' VALUE v_message);
            RETURN;
        END IF;
        
        -- Парсим входной JSON
        SELECT 
            jt.patient_id,
            jt.doctor_id,
            jt.diagnosis,
            jt.prescription,
            jt.notes
        INTO 
            v_patient_id,
            v_doctor_id,
            v_diagnosis,
            v_prescription,
            v_notes
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                patient_id NUMBER PATH '$.patient_id',
                doctor_id NUMBER PATH '$.doctor_id',
                diagnosis VARCHAR2(32767) PATH '$.diagnosis',
                prescription VARCHAR2(32767) PATH '$.prescription',
                notes VARCHAR2(32767) PATH '$.notes'
            )
        ) jt;
        
        -- Валидация
        IF v_patient_id IS NULL THEN
            v_return_code := -1;
            v_message := 'Patient ID is required';
            p_output_json := JSON_OBJECT('return_code' VALUE v_return_code, 'message' VALUE v_message);
            RETURN;
        END IF;
        
        IF v_doctor_id IS NULL THEN
            v_return_code := -1;
            v_message := 'Doctor ID is required';
            p_output_json := JSON_OBJECT('return_code' VALUE v_return_code, 'message' VALUE v_message);
            RETURN;
        END IF;
        
        -- Создание медицинской записи
        INSERT INTO medical_records (
            patient_id, doctor_id,
            diagnosis, prescription, notes,
            record_date
        ) VALUES (
            v_patient_id, v_doctor_id,
            v_diagnosis, v_prescription, v_notes,
            SYSDATE
        ) RETURNING record_id INTO v_record_id;
        
        COMMIT;
        
        -- Формируем успешный ответ
        p_output_json := JSON_OBJECT(
            'return_code' VALUE v_return_code,
            'message' VALUE v_message,
            'record_id' VALUE v_record_id
        );
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            v_return_code := -1;
            v_message := 'System error: ' || SQLERRM;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message
            );
    END create_medical_record_json;
    
    PROCEDURE get_doctor_records_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_doctor_id NUMBER;
        v_json_clob CLOB;
    BEGIN
        -- Получаем doctor_id из входного JSON
        BEGIN
            SELECT jt.doctor_id
            INTO v_doctor_id
            FROM JSON_TABLE(p_input_json, '$'
                COLUMNS (
                    doctor_id NUMBER PATH '$.doctor_id'
                )
            ) jt;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_doctor_id := NULL;
        END;
        
        
        SELECT JSON_ARRAYAGG(
            JSON_OBJECT(
                'record_id' VALUE mr.record_id,
                'diagnosis' VALUE mr.diagnosis,
                'prescription' VALUE mr.prescription,
                'notes' VALUE mr.notes,
                'record_date' VALUE TO_CHAR(mr.record_date, 'YYYY-MM-DD"T"HH24:MI:SS'),
                'patient_id' VALUE p.patient_id,
                'patient_name' VALUE p.last_name || ' ' || p.first_name || ' ' || NVL(p.middle_name, ''),
                'doctor_id' VALUE d.doctor_id,
                'doctor_name' VALUE d.last_name || ' ' || d.first_name || ' ' || NVL(d.middle_name, '')
            )
        ) INTO v_json_clob
        FROM medical_records mr
        JOIN admin.masked_patients p ON mr.patient_id = p.patient_id
        JOIN admin.masked_doctors d ON mr.doctor_id = d.doctor_id
        WHERE (v_doctor_id IS NULL OR mr.doctor_id = v_doctor_id)
        ORDER BY mr.record_date DESC;
        
        p_output_json := JSON_OBJECT(
            'return_code' VALUE 0,
            'message' VALUE 'Success',
            'data' VALUE JSON_QUERY(NVL(v_json_clob, '[]'), '$')
        );
        
    EXCEPTION
        WHEN OTHERS THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'System error: ' || SQLERRM,
                'data' VALUE '[]'
            );
    END get_doctor_records_json;
    
    PROCEDURE get_patient_records_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_patient_id NUMBER;
        v_json_clob CLOB;
    BEGIN
        -- Парсим входной JSON
        SELECT jt.patient_id
        INTO v_patient_id
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                patient_id NUMBER PATH '$.patient_id'
            )
        ) jt;
        
        
        SELECT JSON_ARRAYAGG(
            JSON_OBJECT(
                'record_id' VALUE mr.record_id,
                'diagnosis' VALUE mr.diagnosis,
                'prescription' VALUE mr.prescription,
                'notes' VALUE mr.notes,
                'record_date' VALUE TO_CHAR(mr.record_date, 'YYYY-MM-DD"T"HH24:MI:SS'),
                'doctor_id' VALUE d.doctor_id,
                'doctor_name' VALUE d.last_name || ' ' || d.first_name || ' ' || NVL(d.middle_name, '')
            )
        ) INTO v_json_clob
        FROM medical_records mr
        JOIN admin.masked_doctors d ON mr.doctor_id = d.doctor_id
        WHERE mr.patient_id = v_patient_id
        ORDER BY mr.record_date DESC;
        
        p_output_json := JSON_OBJECT(
            'return_code' VALUE 0,
            'message' VALUE 'Success',
            'data' VALUE JSON_QUERY(NVL(v_json_clob, '[]'), '$')
        );
        
    EXCEPTION
        WHEN OTHERS THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'System error: ' || SQLERRM,
                'data' VALUE '[]'
            );
    END get_patient_records_json;
    
    PROCEDURE get_medical_record_by_id_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_record_id NUMBER;
        v_json_clob CLOB;
    BEGIN
        -- Парсим входной JSON
        SELECT jt.record_id
        INTO v_record_id
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                record_id NUMBER PATH '$.record_id'
            )
        ) jt;
        

        
        SELECT JSON_OBJECT(
            'record_id' VALUE mr.record_id,
            'diagnosis' VALUE mr.diagnosis,
            'prescription' VALUE mr.prescription,
            'notes' VALUE mr.notes,
            'record_date' VALUE TO_CHAR(mr.record_date, 'YYYY-MM-DD"T"HH24:MI:SS'),
            'patient_id' VALUE p.patient_id,
            'patient_name' VALUE p.last_name || ' ' || p.first_name || ' ' || NVL(p.middle_name, ''),
            'doctor_id' VALUE d.doctor_id,
            'doctor_name' VALUE d.last_name || ' ' || d.first_name || ' ' || NVL(d.middle_name, '')
        ) INTO v_json_clob
        FROM medical_records mr
        JOIN admin.masked_patients p ON mr.patient_id = p.patient_id
        JOIN admin.masked_doctors d ON mr.doctor_id = d.doctor_id
        WHERE mr.record_id = v_record_id;
        
        p_output_json := JSON_OBJECT(
            'return_code' VALUE 0,
            'message' VALUE 'Success',
            'data' VALUE JSON_QUERY(v_json_clob, '$')
        );
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'Medical record not found',
                'data' VALUE '{}'
            );
        WHEN OTHERS THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'System error: ' || SQLERRM,
                'data' VALUE '{}'
            );
    END get_medical_record_by_id_json;
    
    PROCEDURE update_medical_record_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_record_id NUMBER;
        v_diagnosis CLOB;
        v_prescription CLOB;
        v_notes CLOB;
        v_return_code NUMBER := 0;
        v_message VARCHAR2(255) := 'Medical record updated successfully';
    BEGIN
        -- Проверка прав доступа
        IF NOT auth_pkg.check_permission('HEAD_DOCTOR') AND NOT auth_pkg.check_permission('DOCTOR') THEN
            v_return_code := -1;
            v_message := 'Доступ запрещен: требуется роль заведующего или врача';
            p_output_json := JSON_OBJECT('return_code' VALUE v_return_code, 'message' VALUE v_message);
            RETURN;
        END IF;
        
        -- Парсим входной JSON
        SELECT 
            jt.record_id,
            jt.diagnosis,
            jt.prescription,
            jt.notes
        INTO 
            v_record_id,
            v_diagnosis,
            v_prescription,
            v_notes
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                record_id NUMBER PATH '$.record_id',
                diagnosis VARCHAR2(32767) PATH '$.diagnosis',
                prescription VARCHAR2(32767) PATH '$.prescription',
                notes VARCHAR2(32767) PATH '$.notes'
            )
        ) jt;
        
        -- Обновление медицинской записи
        UPDATE medical_records
        SET 
            diagnosis = v_diagnosis,
            prescription = v_prescription,
            notes = v_notes
        WHERE record_id = v_record_id;
        
        IF SQL%ROWCOUNT = 0 THEN
            v_return_code := -1;
            v_message := 'Медицинская запись не найдена';
        END IF;
        
        COMMIT;
        
        -- Формируем ответ
        p_output_json := JSON_OBJECT(
            'return_code' VALUE v_return_code,
            'message' VALUE v_message
        );
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            v_return_code := -1;
            v_message := 'System error: ' || SQLERRM;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message
            );
    END update_medical_record_json;
    
    PROCEDURE delete_medical_record_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_record_id NUMBER;
        v_return_code NUMBER := 0;
        v_message VARCHAR2(255) := 'Medical record deleted successfully';
    BEGIN
        -- Проверка прав доступа
        IF NOT auth_pkg.check_permission('HEAD_DOCTOR') AND NOT auth_pkg.check_permission('DOCTOR') THEN
            v_return_code := -1;
            v_message := 'Доступ запрещен: требуется роль заведующего';
            p_output_json := JSON_OBJECT('return_code' VALUE v_return_code, 'message' VALUE v_message);
            RETURN;
        END IF;
        
        -- Парсим входной JSON
        SELECT jt.record_id
        INTO v_record_id
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                record_id NUMBER PATH '$.record_id'
            )
        ) jt;
        
        -- Удаление медицинской записи
        DELETE FROM medical_records
        WHERE record_id = v_record_id;
        
        IF SQL%ROWCOUNT = 0 THEN
            v_return_code := -1;
            v_message := 'Медицинская запись не найдена';
        END IF;
        
        COMMIT;
        
        -- Формируем ответ
        p_output_json := JSON_OBJECT(
            'return_code' VALUE v_return_code,
            'message' VALUE v_message
        );
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            v_return_code := -1;
            v_message := 'System error: ' || SQLERRM;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message
            );
    END delete_medical_record_json;
    
    PROCEDURE get_all_medical_records(
    p_result_cursor OUT SYS_REFCURSOR
) IS
BEGIN
    -- Открываем курсор с результатами
    OPEN p_result_cursor FOR
    SELECT 
        mr.record_id,
        mr.diagnosis,
        mr.prescription,
        mr.notes,
        mr.record_date,
        p.patient_id,
        p.last_name || ' ' || p.first_name || ' ' || COALESCE(p.middle_name, '') as patient_name,
        d.doctor_id,
        d.last_name || ' ' || d.first_name || ' ' || COALESCE(d.middle_name, '') as doctor_name
    FROM medical_records mr
    JOIN admin.masked_patients p ON mr.patient_id = p.patient_id
    JOIN admin.masked_doctors d ON mr.doctor_id = d.doctor_id
    ORDER BY mr.record_date DESC;
    
EXCEPTION
    WHEN OTHERS THEN
        -- В случае ошибки открываем пустой курсор
        OPEN p_result_cursor FOR
        SELECT 
            NULL as record_id,
            NULL as diagnosis,
            NULL as prescription,
            NULL as notes,
            NULL as record_date,
            NULL as patient_id,
            NULL as patient_name,
            NULL as doctor_id,
            NULL as doctor_name
        FROM DUAL WHERE 1=0;
END get_all_medical_records;

END medical_record_pkg_json;
/
CREATE OR REPLACE PACKAGE test_result_pkg_json IS
    -- Добавление результата анализа через JSON
    PROCEDURE add_test_result_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    -- Получение результатов пациента через JSON
    PROCEDURE get_patient_test_results(
        p_input_json IN VARCHAR2,
        p_result_cursor OUT SYS_REFCURSOR
    );
    
    -- Получение всех результатов через JSON
    PROCEDURE get_all_test_results(
    p_result_cursor OUT SYS_REFCURSOR
      );
    
    PROCEDURE get_test_result_by_id_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    PROCEDURE update_test_result_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    PROCEDURE delete_test_result_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    );
    
    PROCEDURE find_test_results_by_patient_name(
        p_input_json IN VARCHAR2,
        p_result_cursor OUT SYS_REFCURSOR
    );
    
END test_result_pkg_json;
/
CREATE OR REPLACE PACKAGE BODY test_result_pkg_json IS
    
    -- Существующая процедура add_test_result_json
    PROCEDURE add_test_result_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_patient_id NUMBER;
        v_test_type VARCHAR2(100);
        v_test_date DATE;
        v_result_value CLOB;
        v_normal_range VARCHAR2(200);
        v_result_id NUMBER;
        v_return_code NUMBER := 0;
        v_message VARCHAR2(255) := 'Test result added successfully';
    BEGIN
        -- Проверка прав доступа
        IF NOT auth_pkg.check_permission('DOCTOR') 
           AND NOT auth_pkg.check_permission('HEAD_DOCTOR') THEN
            v_return_code := -1;
            v_message := 'Доступ запрещен: требуется роль врача или заведующего';
            p_output_json := JSON_OBJECT('return_code' VALUE v_return_code, 'message' VALUE v_message);
            RETURN;
        END IF;
        
        -- Парсим входной JSON
        SELECT 
            jt.patient_id,
            jt.test_type,
            TO_DATE(jt.test_date, 'YYYY-MM-DD'),
            jt.result_value,
            jt.normal_range
        INTO 
            v_patient_id,
            v_test_type,
            v_test_date,
            v_result_value,
            v_normal_range
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                patient_id NUMBER PATH '$.patient_id',
                test_type VARCHAR2(100) PATH '$.test_type',
                test_date VARCHAR2(10) PATH '$.test_date',
                result_value VARCHAR2(32767) PATH '$.result_value',
                normal_range VARCHAR2(200) PATH '$.normal_range'
            )
        ) jt;
        
        -- Проверка существования пациента
        DECLARE
            v_exists NUMBER;
        BEGIN
            SELECT COUNT(*) INTO v_exists FROM admin.masked_patients WHERE patient_id = v_patient_id;
            IF v_exists = 0 THEN
                v_return_code := -1;
                v_message := 'Пациент не найден';
                p_output_json := JSON_OBJECT('return_code' VALUE v_return_code, 'message' VALUE v_message);
                RETURN;
            END IF;
        END;
        
        -- Проверка даты
        IF v_test_date > SYSDATE THEN
            v_return_code := -1;
            v_message := 'Дата анализа не может быть в будущем';
            p_output_json := JSON_OBJECT('return_code' VALUE v_return_code, 'message' VALUE v_message);
            RETURN;
        END IF;
        
        -- Добавление результата
        INSERT INTO test_results (
            patient_id, test_type,
            test_date, result_value, normal_range,
            result_date
        ) VALUES (
            v_patient_id, v_test_type,
            v_test_date, v_result_value, v_normal_range,
            SYSDATE
        ) RETURNING result_id INTO v_result_id;
        
        COMMIT;
        
        -- Формируем успешный ответ
        p_output_json := JSON_OBJECT(
            'return_code' VALUE v_return_code,
            'message' VALUE v_message,
            'data' VALUE v_result_id
        );
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            v_return_code := -1;
            v_message := 'System error: ' || SQLERRM;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message
            );
    END add_test_result_json;
    
    PROCEDURE get_patient_test_results(
    p_input_json IN VARCHAR2,
    p_result_cursor OUT SYS_REFCURSOR
) IS
    v_patient_id NUMBER;
BEGIN
    -- Парсим входной JSON
    BEGIN
        SELECT jt.patient_id
        INTO v_patient_id
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                patient_id NUMBER PATH '$.patient_id'
            )
        ) jt;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_patient_id := NULL;
    END;
    
    -- Открываем курсор с результатами
    OPEN p_result_cursor FOR
    SELECT 
        tr.result_id,
        tr.patient_id,
        tr.test_type,
        tr.test_date,
        tr.result_date,
        tr.result_value,
        tr.normal_range
    FROM admin.masked_test_results tr
    WHERE (v_patient_id IS NULL OR tr.patient_id = v_patient_id)
    ORDER BY tr.test_date DESC;
    
EXCEPTION
    WHEN OTHERS THEN
        -- В случае ошибки открываем пустой курсор
        OPEN p_result_cursor FOR
        SELECT 
            NULL as result_id,
            NULL as patient_id,
            NULL as test_type,
            NULL as test_date,
            NULL as result_date,
            NULL as result_value,
            NULL as normal_range
        FROM DUAL WHERE 1=0;
END get_patient_test_results;
    
    PROCEDURE get_all_test_results(
    p_result_cursor OUT SYS_REFCURSOR
) IS
BEGIN
    -- Открываем курсор с результатами тестов
    OPEN p_result_cursor FOR
    SELECT 
        tr.result_id,
        tr.patient_id,
        tr.test_type,
        TO_CHAR(tr.test_date, 'YYYY-MM-DD') as test_date,
        TO_CHAR(tr.result_date, 'YYYY-MM-DD"T"HH24:MI:SS') as result_date,
        tr.result_value,
        tr.normal_range
    FROM admin.masked_test_results tr
    ORDER BY tr.test_date DESC;
    
EXCEPTION
    WHEN OTHERS THEN
        -- В случае ошибки открываем пустой курсор
        OPEN p_result_cursor FOR
        SELECT 
            NULL as result_id,
            NULL as patient_id,
            NULL as test_type,
            NULL as test_date,
            NULL as result_date,
            NULL as result_value,
            NULL as normal_range
        FROM DUAL WHERE 1=0;
END get_all_test_results;
    PROCEDURE get_test_result_by_id_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_result_id NUMBER;
        v_json_obj CLOB;
    BEGIN
        -- Парсим входной JSON
        SELECT jt.result_id
        INTO v_result_id
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                result_id NUMBER PATH '$.result_id'
            )
        ) jt;
        
 
        
        SELECT JSON_OBJECT(
            'result_id' VALUE tr.result_id,
            'patient_id' VALUE tr.patient_id,
            'test_type' VALUE tr.test_type,
            'test_date' VALUE TO_CHAR(tr.test_date, 'YYYY-MM-DD'),
            'result_date' VALUE TO_CHAR(tr.result_date, 'YYYY-MM-DD"T"HH24:MI:SS'),
            'result_value' VALUE tr.result_value,
            'normal_range' VALUE tr.normal_range
        ) INTO v_json_obj
        FROM admin.masked_test_results tr
        WHERE tr.result_id = v_result_id;
        
        p_output_json := JSON_OBJECT(
            'return_code' VALUE 0,
            'message' VALUE 'Success',
            'data' VALUE JSON_QUERY(v_json_obj, '$')
        );
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'Результат анализа не найден',
                'data' VALUE NULL
            );
        WHEN OTHERS THEN
            p_output_json := JSON_OBJECT(
                'return_code' VALUE -1,
                'message' VALUE 'System error: ' || SQLERRM,
                'data' VALUE NULL
            );
    END get_test_result_by_id_json;
    
    PROCEDURE update_test_result_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_result_id NUMBER;
        v_test_type VARCHAR2(100);
        v_test_date DATE;
        v_result_value CLOB;
        v_normal_range VARCHAR2(200);
        v_return_code NUMBER := 0;
        v_message VARCHAR2(255) := 'Test result updated successfully';
    BEGIN
        -- Проверка прав доступа
        IF NOT auth_pkg.check_permission('HEAD_DOCTOR') AND NOT auth_pkg.check_permission('DOCTOR') THEN
            v_return_code := -1;
            v_message := 'Доступ запрещен: требуется роль врача или заведующего';
            p_output_json := JSON_OBJECT('return_code' VALUE v_return_code, 'message' VALUE v_message);
            RETURN;
        END IF;
        
        -- Парсим входной JSON
        SELECT 
            jt.result_id,
            jt.test_type,
            TO_DATE(jt.test_date, 'YYYY-MM-DD'),
            jt.result_value,
            jt.normal_range
        INTO 
            v_result_id,
            v_test_type,
            v_test_date,
            v_result_value,
            v_normal_range
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                result_id NUMBER PATH '$.result_id',
                test_type VARCHAR2(100) PATH '$.test_type',
                test_date VARCHAR2(10) PATH '$.test_date',
                result_value VARCHAR2(32767) PATH '$.result_value',
                normal_range VARCHAR2(200) PATH '$.normal_range'
            )
        ) jt;
        
        -- Проверка даты
        IF v_test_date > SYSDATE THEN
            v_return_code := -1;
            v_message := 'Дата анализа не может быть в будущем';
            p_output_json := JSON_OBJECT('return_code' VALUE v_return_code, 'message' VALUE v_message);
            RETURN;
        END IF;
        
        -- Обновление результата
        UPDATE test_results
        SET test_type = v_test_type,
            test_date = v_test_date,
            result_value = v_result_value,
            normal_range = v_normal_range,
            result_date = SYSDATE
        WHERE result_id = v_result_id;
        
        IF SQL%ROWCOUNT = 0 THEN
            v_return_code := -1;
            v_message := 'Результат анализа не найден';
        END IF;
        
        COMMIT;
        
        -- Формируем успешный ответ
        p_output_json := JSON_OBJECT(
            'return_code' VALUE v_return_code,
            'message' VALUE v_message,
            'data' VALUE v_result_id
        );
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            v_return_code := -1;
            v_message := 'System error: ' || SQLERRM;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message
            );
    END update_test_result_json;
    
    PROCEDURE delete_test_result_json(
        p_input_json IN VARCHAR2,
        p_output_json OUT VARCHAR2
    ) IS
        v_result_id NUMBER;
        v_return_code NUMBER := 0;
        v_message VARCHAR2(255) := 'Test result deleted successfully';
    BEGIN
        -- Проверка прав доступа
        IF NOT auth_pkg.check_permission('HEAD_DOCTOR') AND NOT auth_pkg.check_permission('DOCTOR') THEN
            v_return_code := -1;
            v_message := 'Доступ запрещен: требуется роль заведующего или доктора';
            p_output_json := JSON_OBJECT('return_code' VALUE v_return_code, 'message' VALUE v_message);
            RETURN;
        END IF;
        
        -- Парсим входной JSON
        SELECT jt.result_id
        INTO v_result_id
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                result_id NUMBER PATH '$.result_id'
            )
        ) jt;
        
        -- Удаление результата
        DELETE FROM test_results
        WHERE result_id = v_result_id;
        
        IF SQL%ROWCOUNT = 0 THEN
            v_return_code := -1;
            v_message := 'Результат анализа не найден';
        END IF;
        
        COMMIT;
        
        -- Формируем успешный ответ
        p_output_json := JSON_OBJECT(
            'return_code' VALUE v_return_code,
            'message' VALUE v_message,
            'data' VALUE v_result_id
        );
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            v_return_code := -1;
            v_message := 'System error: ' || SQLERRM;
            p_output_json := JSON_OBJECT(
                'return_code' VALUE v_return_code,
                'message' VALUE v_message
            );
    END delete_test_result_json;
    
    PROCEDURE find_test_results_by_patient_name(
    p_input_json IN VARCHAR2,
    p_result_cursor OUT SYS_REFCURSOR
) IS
    v_search_term VARCHAR2(100);
BEGIN
    -- Парсим входной JSON
    BEGIN
        SELECT jt.search_term
        INTO v_search_term
        FROM JSON_TABLE(p_input_json, '$'
            COLUMNS (
                search_term VARCHAR2(100) PATH '$.search_term'
            )
        ) jt;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_search_term := NULL;
    END;
    
    -- Открываем курсор с результатами
    OPEN p_result_cursor FOR
    SELECT 
        tr.result_id,
        tr.patient_id,
        tr.test_type,
        TO_CHAR(tr.test_date, 'YYYY-MM-DD') as test_date_str,
        TO_CHAR(tr.result_date, 'YYYY-MM-DD"T"HH24:MI:SS') as result_date_str,
        tr.result_value,
        tr.normal_range,
        p.last_name || ' ' || p.first_name || ' ' || COALESCE(p.middle_name, '') as patient_name
    FROM admin.masked_test_results tr
    JOIN admin.masked_patients p ON tr.patient_id = p.patient_id
    WHERE (v_search_term IS NULL OR 
           UPPER(p.last_name || ' ' || p.first_name || ' ' || COALESCE(p.middle_name, '')) 
           LIKE '%' || UPPER(v_search_term) || '%')
    ORDER BY tr.test_date DESC, tr.result_id DESC;
    
EXCEPTION
    WHEN OTHERS THEN
        -- В случае ошибки открываем пустой курсор
        OPEN p_result_cursor FOR
        SELECT 
            NULL as result_id,
            NULL as patient_id,
            NULL as test_type,
            NULL as test_date_str,
            NULL as result_date_str,
            NULL as result_value,
            NULL as normal_range,
            NULL as patient_name
        FROM DUAL WHERE 1=0;
END find_test_results_by_patient_name;

END test_result_pkg_json;
/
CREATE OR REPLACE PROCEDURE export_medical_records_to_json(
    p_directory_name VARCHAR2,
    p_file_name VARCHAR2
)
AS
    l_file UTL_FILE.FILE_TYPE;
    l_json CLOB;
    l_first BOOLEAN := TRUE;
    
    CURSOR c_records IS
        SELECT 
            record_id,
            patient_id,
            doctor_id,
            diagnosis,
            prescription,
            notes,
            TO_CHAR(record_date, 'YYYY-MM-DD HH24:MI:SS') as record_date
        FROM medical_records
        ORDER BY record_id;
BEGIN
    -- Открываем файл для записи
    l_file := UTL_FILE.FOPEN(p_directory_name, p_file_name, 'W', 32767);
    
    -- Начало JSON массива
    UTL_FILE.PUT_LINE(l_file, '[');
    
    FOR record_rec IN c_records LOOP
        IF NOT l_first THEN
            UTL_FILE.PUT_LINE(l_file, ',');
        END IF;
        
        -- Формируем JSON объект для каждой записи
        l_json := '{' ||
                  '"record_id":' || record_rec.record_id || ',' ||
                  '"patient_id":' || record_rec.patient_id || ',' ||
                  '"doctor_id":' || record_rec.doctor_id || ',' ||
                  '"diagnosis":"' || REPLACE(NVL(record_rec.diagnosis, ''), '"', '\"') || '",' ||
                  '"prescription":"' || REPLACE(NVL(record_rec.prescription, ''), '"', '\"') || '",' ||
                  '"notes":"' || REPLACE(NVL(record_rec.notes, ''), '"', '\"') || '",' ||
                  '"record_date":"' || record_rec.record_date || '"' ||
                  '}';
        
        
        l_first := FALSE;
    END LOOP;
    
    -- Конец JSON массива
    UTL_FILE.PUT_LINE(l_file, ']');
    
    -- Закрываем файл
    UTL_FILE.FCLOSE(l_file);
    
    DBMS_OUTPUT.PUT_LINE('Экспорт завершен. Файл: ' || p_file_name);
EXCEPTION
    WHEN OTHERS THEN
        IF UTL_FILE.IS_OPEN(l_file) THEN
            UTL_FILE.FCLOSE(l_file);
        END IF;
        DBMS_OUTPUT.PUT_LINE('Ошибка: ' || SQLERRM);
        RAISE;
END export_medical_records_to_json;
/
CREATE OR REPLACE PROCEDURE import_medical_records_from_json(
    p_directory_name VARCHAR2,
    p_file_name VARCHAR2
)
AS
    l_file UTL_FILE.FILE_TYPE;
    l_json_text CLOB := '';
    l_buffer VARCHAR2(32767);
    l_count NUMBER;
BEGIN
    -- Читаем файл
    l_file := UTL_FILE.FOPEN(p_directory_name, p_file_name, 'R', 32767);
    
    BEGIN
        LOOP
            UTL_FILE.GET_LINE(l_file, l_buffer);
            l_json_text := l_json_text || l_buffer;
        END LOOP;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            NULL;
    END;
    
    UTL_FILE.FCLOSE(l_file);
    
    MERGE INTO medical_records mr
    USING (
        SELECT 
            jt.record_id,
            jt.patient_id,
            jt.doctor_id,
            TO_CLOB(jt.diagnosis) as diagnosis,
            TO_CLOB(jt.prescription) as prescription,
            TO_CLOB(jt.notes) as notes,
            TO_DATE(jt.record_date, 'YYYY-MM-DD HH24:MI:SS') as record_date
        FROM JSON_TABLE(
            l_json_text, '$[*]'
            COLUMNS (
                record_id NUMBER PATH '$.record_id',
                patient_id NUMBER PATH '$.patient_id',
                doctor_id NUMBER PATH '$.doctor_id',
                diagnosis VARCHAR2(4000) PATH '$.diagnosis',
                prescription VARCHAR2(4000) PATH '$.prescription',
                notes VARCHAR2(4000) PATH '$.notes',
                record_date VARCHAR2(20) PATH '$.record_date'
            )
        ) jt
    ) src
    ON (mr.record_id = src.record_id)
    WHEN MATCHED THEN UPDATE SET
        mr.patient_id = src.patient_id,
        mr.doctor_id = src.doctor_id,
        mr.diagnosis = src.diagnosis,
        mr.prescription = src.prescription,
        mr.notes = src.notes,
        mr.record_date = src.record_date
    WHEN NOT MATCHED THEN INSERT (
        record_id, patient_id, doctor_id, 
        diagnosis, prescription, notes, record_date
    ) VALUES (
        src.record_id, src.patient_id, src.doctor_id,
        src.diagnosis, src.prescription, src.notes, src.record_date
    );
    
    l_count := SQL%ROWCOUNT;
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('Импорт завершен. Обработано записей: ' || l_count);
EXCEPTION
    WHEN OTHERS THEN
        IF UTL_FILE.IS_OPEN(l_file) THEN
            UTL_FILE.FCLOSE(l_file);
        END IF;
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Ошибка: ' || SQLERRM);
        RAISE;
END import_medical_records_from_json;
/

grant execute on export_medical_records_to_json to app_head_doctor_role;
grant execute on import_medical_records_from_json to app_head_doctor_role;

GRANT EXECUTE ON auth_pkg TO app_guest_role;
GRANT EXECUTE ON auth_pkg TO app_doctor_role;
GRANT EXECUTE ON auth_pkg TO app_registrar_role;
GRANT EXECUTE ON auth_pkg TO app_head_doctor_role;

GRANT EXECUTE ON patient_pkg_json TO app_doctor_role;
GRANT EXECUTE ON patient_pkg_json TO app_head_doctor_role;
GRANT EXECUTE ON patient_pkg_json TO app_registrar_role;

GRANT EXECUTE ON appointment_pkg_json TO app_doctor_role;
GRANT EXECUTE ON appointment_pkg_json TO app_head_doctor_role;
GRANT EXECUTE ON appointment_pkg_json TO app_registrar_role;

GRANT EXECUTE ON doctor_management_pkg_json TO app_head_doctor_role;
GRANT EXECUTE ON doctor_management_pkg_json TO app_doctor_role;
GRANT EXECUTE ON doctor_management_pkg_json TO app_registrar_role;

GRANT EXECUTE ON medical_record_pkg_json TO app_doctor_role;
GRANT EXECUTE ON medical_record_pkg_json TO app_head_doctor_role;

GRANT EXECUTE ON test_result_pkg_json TO app_doctor_role;
GRANT EXECUTE ON test_result_pkg_json TO app_registrar_role;
GRANT EXECUTE ON test_result_pkg_json TO app_head_doctor_role;

GRANT EXECUTE ON admin.doctor_schedule_pkg_json to app_head_doctor_role;
GRANT EXECUTE ON admin.doctor_schedule_pkg_json to app_doctor_role;
GRANT EXECUTE ON admin.doctor_schedule_pkg_json to app_registrar_role;

GRANT EXECUTE ON auth_pkg TO app_guest_role;
/
