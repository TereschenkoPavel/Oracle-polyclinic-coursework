-- Скрипт заполнения базы данных тестовыми данными
SET SERVEROUTPUT ON;
DECLARE
    v_output_json VARCHAR2(4000);
    v_input_json VARCHAR2(4000);
    
    -- Переменные для хранения ID специальностей
    v_spec_therapist NUMBER;
    v_spec_cardio NUMBER;
    v_spec_neurologist NUMBER;
    v_spec_surgeon NUMBER;
    v_spec_ophthalmologist NUMBER;
    v_spec_ent NUMBER;
    v_spec_gastroenterologist NUMBER;
    v_spec_dermatologist NUMBER;
    v_spec_endocrinologist NUMBER;
    v_spec_pediatrician NUMBER;
    
    -- Счётчики для итогов
    v_specialties_count NUMBER := 0;
    v_doctor_count NUMBER := 0;
    v_patient_count NUMBER := 0;
    v_appointment_count NUMBER := 0;
    v_schedule_count NUMBER := 0;
    v_record_count NUMBER := 0;
    v_test_count NUMBER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('Начало заполнения базы данных тестовыми данными...');
    
    -- ================================================
    -- 1. Заполняем таблицу specialties
    -- ================================================
    BEGIN
        DBMS_OUTPUT.PUT_LINE('1. Заполняем таблицу specialties...');
        
        INSERT INTO specialties (specialty_name, appointment_duration_minutes) VALUES ('Терапевт', 30);
        INSERT INTO specialties (specialty_name, appointment_duration_minutes) VALUES ('Кардиолог', 40);
        INSERT INTO specialties (specialty_name, appointment_duration_minutes) VALUES ('Невролог', 45);
        INSERT INTO specialties (specialty_name, appointment_duration_minutes) VALUES ('Хирург', 60);
        INSERT INTO specialties (specialty_name, appointment_duration_minutes) VALUES ('Офтальмолог', 25);
        INSERT INTO specialties (specialty_name, appointment_duration_minutes) VALUES ('Отоларинголог', 30);
        INSERT INTO specialties (specialty_name, appointment_duration_minutes) VALUES ('Гастроэнтеролог', 40);
        INSERT INTO specialties (specialty_name, appointment_duration_minutes) VALUES ('Дерматолог', 20);
        INSERT INTO specialties (specialty_name, appointment_duration_minutes) VALUES ('Эндокринолог', 35);
        INSERT INTO specialties (specialty_name, appointment_duration_minutes) VALUES ('Педиатр', 30);
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('   Успешно: создано 10 специальностей');
        v_specialties_count := 10;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('   Ошибка при заполнении specialties: ' || SQLERRM);
            DBMS_OUTPUT.PUT_LINE('   Продолжаем выполнение...');
            ROLLBACK;
    END;
    
    -- Получаем ID специальностей для дальнейшего использования
    BEGIN
        SELECT specialty_id INTO v_spec_therapist FROM specialties WHERE specialty_name = 'Терапевт' AND ROWNUM = 1;
        SELECT specialty_id INTO v_spec_cardio FROM specialties WHERE specialty_name = 'Кардиолог' AND ROWNUM = 1;
        SELECT specialty_id INTO v_spec_neurologist FROM specialties WHERE specialty_name = 'Невролог' AND ROWNUM = 1;
        SELECT specialty_id INTO v_spec_surgeon FROM specialties WHERE specialty_name = 'Хирург' AND ROWNUM = 1;
        SELECT specialty_id INTO v_spec_ophthalmologist FROM specialties WHERE specialty_name = 'Офтальмолог' AND ROWNUM = 1;
        SELECT specialty_id INTO v_spec_ent FROM specialties WHERE specialty_name = 'Отоларинголог' AND ROWNUM = 1;
        SELECT specialty_id INTO v_spec_gastroenterologist FROM specialties WHERE specialty_name = 'Гастроэнтеролог' AND ROWNUM = 1;
        SELECT specialty_id INTO v_spec_dermatologist FROM specialties WHERE specialty_name = 'Дерматолог' AND ROWNUM = 1;
        SELECT specialty_id INTO v_spec_endocrinologist FROM specialties WHERE specialty_name = 'Эндокринолог' AND ROWNUM = 1;
        SELECT specialty_id INTO v_spec_pediatrician FROM specialties WHERE specialty_name = 'Педиатр' AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('   Предупреждение: не все специальности найдены, создание врачей может быть невозможно');
    END;
    
    -- ================================================
    -- 2. Создаем пользователей HEAD_DOCTOR и REGISTRAR
    -- ================================================
    BEGIN
        DBMS_OUTPUT.PUT_LINE('2. Создаем пользователей HEAD_DOCTOR и REGISTRAR...');
        
        -- HEAD_DOCTOR
        v_input_json := '{
            "username": "HeadDoc",
            "password": "jfPjrW96DKGK4bc",
            "role": "HEAD_DOCTOR"
        }';
        
        auth_pkg.register_user(v_input_json, v_output_json);
        DBMS_OUTPUT.PUT_LINE('   HEAD_DOCTOR создан: HeadDoc');
        
        -- REGISTRAR 1
        v_input_json := '{
            "username": "Reg",
            "password": "jfPjrW96DKGK4bc",
            "role": "REGISTRAR"
        }';
        
        auth_pkg.register_user(v_input_json, v_output_json);
        DBMS_OUTPUT.PUT_LINE('   REGISTRAR создан: Reg');
        
        -- REGISTRAR 2
        v_input_json := '{
            "username": "reg2",
            "password": "Reg67890!",
            "role": "REGISTRAR"
        }';
        
        auth_pkg.register_user(v_input_json, v_output_json);
        DBMS_OUTPUT.PUT_LINE('   REGISTRAR создан: reg2');
        
        -- REGISTRAR 3
        v_input_json := '{
            "username": "reg3",
            "password": "RegPass111!",
            "role": "REGISTRAR"
        }';
        
        auth_pkg.register_user(v_input_json, v_output_json);
        DBMS_OUTPUT.PUT_LINE('   REGISTRAR создан: reg3');
        
        DBMS_OUTPUT.PUT_LINE('   Успешно: создано 4 административных пользователя');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('   Ошибка при создании пользователей: ' || SQLERRM);
            DBMS_OUTPUT.PUT_LINE('   Продолжаем выполнение...');
    END;
    
    -- ================================================
    -- 3. Создаем врачей через процедуру add_doctor_json
    -- ================================================
    BEGIN
        DBMS_OUTPUT.PUT_LINE('3. Создаем врачей...');
        
        -- Проверяем, что у нас есть ID специальностей
        IF v_spec_therapist IS NOT NULL THEN
            -- Врач 1 (Терапевт)
            v_input_json := '{
                "last_name": "Терещенко",
                "first_name": "Павел",
                "middle_name": "Александрович",
                "specialty_id": ' || v_spec_therapist || ',
                "office_number": "101",
                "phone": "+79161234567",
                "passport_series_number": "AB1234567",
                "username": "Doc",
                "password": "jfPjrW96DKGK4bc"
            }';
            
            doctor_management_pkg_json.add_doctor_json(v_input_json, v_output_json);
            v_doctor_count := v_doctor_count + 1;
            DBMS_OUTPUT.PUT_LINE('   Врач создан: Терещенко П.А. (Терапевт)');
        END IF;
        
        IF v_spec_cardio IS NOT NULL THEN
            -- Врач 2 (Кардиолог)
            v_input_json := '{
                "last_name": "Петрова",
                "first_name": "Елена",
                "middle_name": "Владимировна",
                "specialty_id": ' || v_spec_cardio || ',
                "office_number": "205",
                "phone": "+79162345678",
                "passport_series_number": "CD2345678",
                "username": "doctor_petrova",
                "password": "CardioPass456!"
            }';
            
            doctor_management_pkg_json.add_doctor_json(v_input_json, v_output_json);
            v_doctor_count := v_doctor_count + 1;
            DBMS_OUTPUT.PUT_LINE('   Врач создан: Петрова Е.В. (Кардиолог)');
        END IF;
        
        IF v_spec_neurologist IS NOT NULL THEN
            -- Врач 3 (Невролог)
            v_input_json := '{
                "last_name": "Сидоров",
                "first_name": "Дмитрий",
                "middle_name": "Александрович",
                "specialty_id": ' || v_spec_neurologist || ',
                "office_number": "312",
                "phone": "+79163456789",
                "passport_series_number": "EF3456789",
                "username": "doctor_sidorov",
                "password": "NeuroPass789!"
            }';
            
            doctor_management_pkg_json.add_doctor_json(v_input_json, v_output_json);
            v_doctor_count := v_doctor_count + 1;
            DBMS_OUTPUT.PUT_LINE('   Врач создан: Сидоров Д.А. (Невролог)');
        END IF;
        
        IF v_spec_surgeon IS NOT NULL THEN
            -- Врач 4 (Хирург)
            v_input_json := '{
                "last_name": "Кузнецов",
                "first_name": "Михаил",
                "middle_name": "Игоревич",
                "specialty_id": ' || v_spec_surgeon || ',
                "office_number": "415",
                "phone": "+79164567890",
                "passport_series_number": "GH4567890",
                "username": "doctor_kuznetsov",
                "password": "SurgPass012!"
            }';
            
            doctor_management_pkg_json.add_doctor_json(v_input_json, v_output_json);
            v_doctor_count := v_doctor_count + 1;
            DBMS_OUTPUT.PUT_LINE('   Врач создан: Кузнецов М.И. (Хирург)');
        END IF;
        
        IF v_spec_ophthalmologist IS NOT NULL THEN
            -- Врач 5 (Офтальмолог)
            v_input_json := '{
                "last_name": "Морозова",
                "first_name": "Ольга",
                "middle_name": "Петровна",
                "specialty_id": ' || v_spec_ophthalmologist || ',
                "office_number": "508",
                "phone": "+79165678901",
                "passport_series_number": "IJ5678901",
                "username": "doctor_morozova",
                "password": "OphthalmPass345!"
            }';
            
            doctor_management_pkg_json.add_doctor_json(v_input_json, v_output_json);
            v_doctor_count := v_doctor_count + 1;
            DBMS_OUTPUT.PUT_LINE('   Врач создан: Морозова О.П. (Офтальмолог)');
        END IF;
        
        IF v_spec_ent IS NOT NULL THEN
            -- Врач 6 (Отоларинголог)
            v_input_json := '{
                "last_name": "Васильев",
                "first_name": "Андрей",
                "middle_name": "Николаевич",
                "specialty_id": ' || v_spec_ent || ',
                "office_number": "603",
                "phone": "+79166789012",
                "passport_series_number": "KL6789012",
                "username": "doctor_vasilev",
                "password": "EntPass678!"
            }';
            
            doctor_management_pkg_json.add_doctor_json(v_input_json, v_output_json);
            v_doctor_count := v_doctor_count + 1;
            DBMS_OUTPUT.PUT_LINE('   Врач создан: Васильев А.Н. (Отоларинголог)');
        END IF;
        
        IF v_spec_gastroenterologist IS NOT NULL THEN
            -- Врач 7 (Гастроэнтеролог)
            v_input_json := '{
                "last_name": "Николаева",
                "first_name": "Татьяна",
                "middle_name": "Сергеевна",
                "specialty_id": ' || v_spec_gastroenterologist || ',
                "office_number": "710",
                "phone": "+79167890123",
                "passport_series_number": "MN7890123",
                "username": "doctor_nikolaeva",
                "password": "GastroPass901!"
            }';
            
            doctor_management_pkg_json.add_doctor_json(v_input_json, v_output_json);
            v_doctor_count := v_doctor_count + 1;
            DBMS_OUTPUT.PUT_LINE('   Врач создан: Николаева Т.С. (Гастроэнтеролог)');
        END IF;
        
        IF v_spec_dermatologist IS NOT NULL THEN
            -- Врач 8 (Дерматолог)
            v_input_json := '{
                "last_name": "Федоров",
                "first_name": "Сергей",
                "middle_name": "Викторович",
                "specialty_id": ' || v_spec_dermatologist || ',
                "office_number": "825",
                "phone": "+79168901234",
                "passport_series_number": "OP8901234",
                "username": "doctor_fedorov",
                "password": "DermPass234!"
            }';
            
            doctor_management_pkg_json.add_doctor_json(v_input_json, v_output_json);
            v_doctor_count := v_doctor_count + 1;
            DBMS_OUTPUT.PUT_LINE('   Врач создан: Федоров С.В. (Дерматолог)');
        END IF;
        
        IF v_spec_endocrinologist IS NOT NULL THEN
            -- Врач 9 (Эндокринолог)
            v_input_json := '{
                "last_name": "Ковалева",
                "first_name": "Ирина",
                "middle_name": "Алексеевна",
                "specialty_id": ' || v_spec_endocrinologist || ',
                "office_number": "902",
                "phone": "+79169012345",
                "passport_series_number": "QR9012345",
                "username": "doctor_kovaleva",
                "password": "EndoPass567!"
            }';
            
            doctor_management_pkg_json.add_doctor_json(v_input_json, v_output_json);
            v_doctor_count := v_doctor_count + 1;
            DBMS_OUTPUT.PUT_LINE('   Врач создан: Ковалева И.А. (Эндокринолог)');
        END IF;
        
        IF v_spec_pediatrician IS NOT NULL THEN
            -- Врач 10 (Педиатр)
            v_input_json := '{
                "last_name": "Александрова",
                "first_name": "Мария",
                "middle_name": "Дмитриевна",
                "specialty_id": ' || v_spec_pediatrician || ',
                "office_number": "1015",
                "phone": "+79160123456",
                "passport_series_number": "ST0123456",
                "username": "doctor_alexandrova",
                "password": "PediatrPass890!"
            }';
            
            doctor_management_pkg_json.add_doctor_json(v_input_json, v_output_json);
            v_doctor_count := v_doctor_count + 1;
            DBMS_OUTPUT.PUT_LINE('   Врач создан: Александрова М.Д. (Педиатр)');
        END IF;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('   Успешно: создано ' || v_doctor_count || ' врачей');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('   Ошибка при создании врачей: ' || SQLERRM);
            DBMS_OUTPUT.PUT_LINE('   Продолжаем выполнение...');
            ROLLBACK;
    END;
    
    -- ================================================
    -- 4. Заполняем таблицу patients
    -- ================================================
    BEGIN
        DBMS_OUTPUT.PUT_LINE('4. Заполняем таблицу patients...');
        
        INSERT INTO patients (last_name, first_name, middle_name, birth_date, gender, address, phone, passport_series_number) 
        VALUES ('Смирнов', 'Иван', 'Петрович', TO_DATE('1985-03-15', 'YYYY-MM-DD'), 'M', 'ул. Ленина, д. 10, кв. 5', '+79161111111', 'AA1111111');
        v_patient_count := v_patient_count + 1;
        
        INSERT INTO patients (last_name, first_name, middle_name, birth_date, gender, address, phone, passport_series_number) 
        VALUES ('Козлова', 'Анна', 'Сергеевна', TO_DATE('1990-07-22', 'YYYY-MM-DD'), 'F', 'ул. Пушкина, д. 25, кв. 12', '+79162222222', 'BB2222222');
        v_patient_count := v_patient_count + 1;
        
        INSERT INTO patients (last_name, first_name, middle_name, birth_date, gender, address, phone, passport_series_number) 
        VALUES ('Попов', 'Алексей', 'Иванович', TO_DATE('1978-11-05', 'YYYY-MM-DD'), 'M', 'ул. Гагарина, д. 8, кв. 3', '+79163333333', 'CC3333333');
        v_patient_count := v_patient_count + 1;
        
        INSERT INTO patients (last_name, first_name, middle_name, birth_date, gender, address, phone, passport_series_number) 
        VALUES ('Волкова', 'Екатерина', 'Андреевна', TO_DATE('1995-02-18', 'YYYY-MM-DD'), 'F', 'ул. Мира, д. 15, кв. 7', '+79164444444', 'DD4444444');
        v_patient_count := v_patient_count + 1;
        
        INSERT INTO patients (last_name, first_name, middle_name, birth_date, gender, address, phone, passport_series_number) 
        VALUES ('Лебедев', 'Дмитрий', 'Николаевич', TO_DATE('1982-09-30', 'YYYY-MM-DD'), 'M', 'ул. Садовая, д. 3, кв. 9', '+79165555555', 'EE5555555');
        v_patient_count := v_patient_count + 1;
        
        INSERT INTO patients (last_name, first_name, middle_name, birth_date, gender, address, phone, passport_series_number) 
        VALUES ('Новикова', 'Ольга', 'Владимировна', TO_DATE('1988-12-10', 'YYYY-MM-DD'), 'F', 'ул. Центральная, д. 1, кв. 15', '+79166666666', 'FF6666666');
        v_patient_count := v_patient_count + 1;
        
        INSERT INTO patients (last_name, first_name, middle_name, birth_date, gender, address, phone, passport_series_number) 
        VALUES ('Морозов', 'Павел', 'Александрович', TO_DATE('1975-06-25', 'YYYY-MM-DD'), 'M', 'ул. Лесная, д. 7, кв. 4', '+79167777777', 'GG7777777');
        v_patient_count := v_patient_count + 1;
        
        INSERT INTO patients (last_name, first_name, middle_name, birth_date, gender, address, phone, passport_series_number) 
        VALUES ('Захарова', 'Наталья', 'Игоревна', TO_DATE('1992-04-08', 'YYYY-MM-DD'), 'F', 'ул. Школьная, д. 12, кв. 6', '+79168888888', 'HH8888888');
        v_patient_count := v_patient_count + 1;
        
        INSERT INTO patients (last_name, first_name, middle_name, birth_date, gender, address, phone, passport_series_number) 
        VALUES ('Белов', 'Артем', 'Сергеевич', TO_DATE('1980-01-20', 'YYYY-MM-DD'), 'M', 'ул. Парковая, д. 5, кв. 11', '+79169999999', 'II9999999');
        v_patient_count := v_patient_count + 1;
        
        INSERT INTO patients (last_name, first_name, middle_name, birth_date, gender, address, phone, passport_series_number) 
        VALUES ('Антонова', 'Виктория', 'Петровна', TO_DATE('1998-08-14', 'YYYY-MM-DD'), 'F', 'ул. Солнечная, д. 9, кв. 8', '+79161010101', 'JJ1010101');
        v_patient_count := v_patient_count + 1;
        
        -- Еще несколько пациентов для разнообразия
        INSERT INTO patients (last_name, first_name, middle_name, birth_date, gender, address, phone, passport_series_number) 
        VALUES ('Григорьев', 'Максим', 'Викторович', TO_DATE('1993-05-12', 'YYYY-MM-DD'), 'M', 'ул. Весенняя, д. 14, кв. 2', '+79161231234', 'KK1234567');
        v_patient_count := v_patient_count + 1;
        
        INSERT INTO patients (last_name, first_name, middle_name, birth_date, gender, address, phone, passport_series_number) 
        VALUES ('Тихонова', 'Юлия', 'Анатольевна', TO_DATE('1987-10-03', 'YYYY-MM-DD'), 'F', 'ул. Осенняя, д. 6, кв. 10', '+79162342345', 'LL2345678');
        v_patient_count := v_patient_count + 1;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('   Успешно: создано ' || v_patient_count || ' пациентов');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('   Ошибка при создании пациентов: ' || SQLERRM);
            DBMS_OUTPUT.PUT_LINE('   Продолжаем выполнение...');
            ROLLBACK;
    END;
    
    -- ================================================
    -- 5. Заполняем таблицу doctor_schedules
    -- ================================================
    BEGIN
        DBMS_OUTPUT.PUT_LINE('5. Заполняем таблицу doctor_schedules...');
        
        -- Для каждого врача создаем расписание на 2 дня
        FOR doc_rec IN (SELECT doctor_id FROM doctors ORDER BY doctor_id) LOOP
            -- Понедельник: 9:00-13:00
            INSERT INTO doctor_schedules (doctor_id, day_of_week, start_time, end_time)
            VALUES (
                doc_rec.doctor_id,
                1,
                TO_TIMESTAMP('2025-01-01 09:00:00', 'YYYY-MM-DD HH24:MI:SS'),
                TO_TIMESTAMP('2025-01-01 13:00:00', 'YYYY-MM-DD HH24:MI:SS')
            );
            v_schedule_count := v_schedule_count + 1;
            
            -- Понедельник: 14:00-18:00
            INSERT INTO doctor_schedules (doctor_id, day_of_week, start_time, end_time)
            VALUES (
                doc_rec.doctor_id,
                1,
                TO_TIMESTAMP('2025-01-01 14:00:00', 'YYYY-MM-DD HH24:MI:SS'),
                TO_TIMESTAMP('2025-01-01 18:00:00', 'YYYY-MM-DD HH24:MI:SS')
            );
            v_schedule_count := v_schedule_count + 1;
            
            -- Четверг: 9:00-13:00
            INSERT INTO doctor_schedules (doctor_id, day_of_week, start_time, end_time)
            VALUES (
                doc_rec.doctor_id,
                4,
                TO_TIMESTAMP('2025-01-01 09:00:00', 'YYYY-MM-DD HH24:MI:SS'),
                TO_TIMESTAMP('2025-01-01 13:00:00', 'YYYY-MM-DD HH24:MI:SS')
            );
            v_schedule_count := v_schedule_count + 1;
        END LOOP;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('   Успешно: создано ' || v_schedule_count || ' записей в расписании');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('   Ошибка при создании расписаний: ' || SQLERRM);
            DBMS_OUTPUT.PUT_LINE('   Продолжаем выполнение...');
            ROLLBACK;
    END;

      -- ================================================
-- 6. Заполняем таблицу appointments
-- ================================================
BEGIN
    DBMS_OUTPUT.PUT_LINE('6. Заполняем таблицу appointments...');
    
    -- Временные переменные
    v_appointment_count := 0;
    
    -- Для каждого врача создаем несколько записей на прием
    FOR doc_rec IN (SELECT d.doctor_id, s.appointment_duration_minutes 
                    FROM doctors d 
                    JOIN specialties s ON d.specialty_id = s.specialty_id 
                    ORDER BY d.doctor_id) LOOP
        
        FOR sched_rec IN (SELECT DISTINCT day_of_week 
                          FROM doctor_schedules 
                          WHERE doctor_id = doc_rec.doctor_id) LOOP
            DECLARE
                v_target_date DATE;
                v_current_date DATE := SYSDATE;
                v_day_diff NUMBER;
                v_input_json VARCHAR2(1000);
                v_output_json VARCHAR2(4000);
                v_slots_obj JSON_OBJECT_T;
                v_available_slots JSON_ARRAY_T;
                v_slot_count NUMBER;
                v_slots_created NUMBER := 0;
                v_max_slots_per_day NUMBER := 2; -- Максимальное количество записей в день для демонстрации
                v_patient_index NUMBER := 1;
                v_patient_id NUMBER;
                v_total_patients NUMBER;
                v_slot_time VARCHAR2(5);
                v_appt_date TIMESTAMP;
                v_status VARCHAR2(20);
                v_appt_input VARCHAR2(1000);
                v_appointment_id NUMBER;
                v_update_input VARCHAR2(1000);
            BEGIN
                -- Вычисляем ближайшую дату с нужным днем недели
                v_day_diff := sched_rec.day_of_week - (1 + TRUNC (v_current_date) - TRUNC (v_current_date, 'IW'));
                IF v_day_diff = 0 THEN
                    v_day_diff := 7; -- Если сегодня нужный день, берем следующий такой же день
                ELSE IF v_day_diff < 0 THEN
                  v_day_diff := 7 + v_day_diff;
                END IF;
                END IF;
                v_target_date := TRUNC(v_current_date) + v_day_diff;
                -- Получаем доступные слоты на эту дату
                v_input_json := JSON_OBJECT(
                    'doctor_id' VALUE doc_rec.doctor_id,
                    'appointment_date' VALUE TO_CHAR(v_target_date, 'YYYY-MM-DD')
                );
                appointment_pkg_json.get_appointment_slots_json(v_input_json, v_output_json);
                
                -- Парсим результат
                v_slots_obj := JSON_OBJECT_T.parse(v_output_json);
                
                -- Проверяем успешность выполнения и наличие слотов
                IF v_slots_obj.get_number('return_code') = 0 THEN
                    v_available_slots := v_slots_obj.get_array('data');

                    IF v_available_slots IS NOT NULL THEN
                        v_slot_count := v_available_slots.get_size();
                        
                        DBMS_OUTPUT.PUT_LINE('   Врач ' || doc_rec.doctor_id || 
                                           ', день ' || TO_CHAR(v_target_date, 'DD.MM.YYYY') || 
                                           ', доступно слотов: ' || v_slot_count);
                        
                        IF v_slot_count > 0 THEN
                            -- Получаем общее количество пациентов
                            SELECT COUNT(*) INTO v_total_patients FROM patients;
                            
                            -- Создаем записи для первых доступных слотов
                            FOR i IN 0..LEAST(v_slot_count - 1, v_max_slots_per_day - 1) LOOP
                                BEGIN
                                    -- Получаем время слота
                                    v_slot_time := v_available_slots.get_string(i);
                                    DBMS_OUTPUT.PUT_LINE('время слота: '||v_slot_time);
                                    -- Получаем пациента по кругу
                                    SELECT patient_id INTO v_patient_id
                                    FROM (
                                        SELECT patient_id, ROWNUM rn
                                        FROM patients
                                        ORDER BY patient_id
                                    )
                                    WHERE rn = MOD(v_patient_index, v_total_patients) + 1;
                                    -- Формируем полную дату и время
                                    v_appt_date := TO_TIMESTAMP(
                                        TO_CHAR(v_target_date, 'YYYY-MM-DD') || ' ' || v_slot_time,
                                        'YYYY-MM-DD HH24:MI'
                                    );
                                    
                                    -- Определяем статус записи (разные статусы для демонстрации)
                                    v_status := CASE 
                                        WHEN MOD(v_appointment_count, 2) = 0 THEN 'SCHEDULED'
                                        ELSE 'CANCELLED'
                                    END;
                                    
                                    -- Создаем запись на прием
                                    v_appt_input := JSON_OBJECT(
                                        'patient_id' VALUE v_patient_id,
                                        'doctor_id' VALUE doc_rec.doctor_id,
                                        'appointment_date' VALUE TO_CHAR(v_appt_date, 'YYYY-MM-DD"T"HH24:MI:SS')
                                    );
                                    
                                    appointment_pkg_json.create_appointment_json(v_appt_input, v_output_json);
                                    IF JSON_VALUE(v_output_json, '$.return_code') = 0 THEN
                                        v_appointment_id := JSON_VALUE(v_output_json, '$.data');
                                        v_appointment_count := v_appointment_count + 1;
                                        v_slots_created := v_slots_created + 1;
                                        
                                        -- Если статус не SCHEDULED, обновляем его
                                        IF v_status != 'SCHEDULED' THEN
                                            v_update_input := JSON_OBJECT(
                                                'appointment_id' VALUE v_appointment_id,
                                                'status' VALUE v_status
                                            );
                                            appointment_pkg_json.update_appointment_status_json(v_update_input, v_output_json);
                                        END IF;
                                        
                                        DBMS_OUTPUT.PUT_LINE('     Создана запись: Пациент ' || v_patient_id || 
                                                           ', время ' || v_slot_time || 
                                                           ', статус ' || v_status);
                                        ELSE
                                        DBMS_OUTPUT.PUT_LINE(' Ошибка при создании записи: '||JSON_VALUE(v_output_json, '$.message'));
                                    END IF;
                                    
                                    v_patient_index := v_patient_index + 1;
                                    
                                EXCEPTION
                                    WHEN OTHERS THEN
                                        DBMS_OUTPUT.PUT_LINE('     Ошибка при создании записи: ' || SQLERRM);
                                END;
                            END LOOP;
                        ELSE
                            DBMS_OUTPUT.PUT_LINE('     Нет доступных слотов для записи');
                        END IF;
                    ELSE
                        DBMS_OUTPUT.PUT_LINE('     Нет доступных слотов (массив NULL)');
                    END IF;
                ELSE
                    DBMS_OUTPUT.PUT_LINE('     Ошибка при получении слотов: ' || v_slots_obj.get_string('message'));
                END IF;
                
            EXCEPTION
                WHEN OTHERS THEN
                    DBMS_OUTPUT.PUT_LINE('   Ошибка: ' || SQLERRM);
            END;
        END LOOP;
    END LOOP;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('   Успешно: создано ' || v_appointment_count || ' записей на прием');
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('   Ошибка при создании записей на прием: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('   Продолжаем выполнение...');
        ROLLBACK;
END;

    -- ================================================
    -- 7. Заполняем таблицу medical_records
    -- ================================================
    BEGIN
        DBMS_OUTPUT.PUT_LINE('7. Заполняем таблицу medical_records...');
        
        FOR i IN 1..12 LOOP
            INSERT INTO medical_records (patient_id, doctor_id, diagnosis, prescription, notes, record_date)
            SELECT 
                p.patient_id,
                d.doctor_id,
                CASE MOD(i, 5)
                    WHEN 0 THEN 'Гипертоническая болезнь II стадии'
                    WHEN 1 THEN 'Острый бронхит'
                    WHEN 2 THEN 'Гастрит хронический'
                    WHEN 3 THEN 'Остеохондроз шейного отдела'
                    WHEN 4 THEN 'Сахарный диабет 2 типа'
                    ELSE 'ОРВИ' END,
                CASE MOD(i, 5)
                    WHEN 0 THEN 'Амлодипин 5 мг 1 раз в день, контроль АД ежедневно'
                    WHEN 1 THEN 'Амоксициллин 500 мг 3 раза в день, обильное питье'
                    WHEN 2 THEN 'Омепразол 20 мг 2 раза в день, диета №1'
                    WHEN 3 THEN 'Диклофенак мазь 3 раза в день, ЛФК'
                    WHEN 4 THEN 'Метформин 500 мг 2 раза в день, контроль сахара'
                    ELSE 'Парацетамол при температуре, витамин С' END,
                CASE MOD(i, 3)
                    WHEN 0 THEN 'Пациент жалуется на головную боль и головокружение'
                    WHEN 1 THEN 'Состояние удовлетворительное, рекомендован повторный прием'
                    WHEN 2 THEN 'Пациенту рекомендовано пройти дополнительное обследование' END,
                SYSDATE - i * 7
            FROM 
                (SELECT patient_id, ROWNUM rn FROM patients ORDER BY patient_id) p,
                (SELECT doctor_id, ROWNUM rn FROM doctors ORDER BY doctor_id) d
            WHERE p.rn = MOD(i, (SELECT COUNT(*) FROM patients)) + 1
              AND d.rn = MOD(i, (SELECT COUNT(*) FROM doctors)) + 1;
            
            v_record_count := v_record_count + 1;
        END LOOP;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('   Успешно: создано ' || v_record_count || ' медицинских записей');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('   Ошибка при создании медицинских записей: ' || SQLERRM);
            DBMS_OUTPUT.PUT_LINE('   Продолжаем выполнение...');
            ROLLBACK;
    END;
    
    -- ================================================
    -- 8. Заполняем таблицу test_results
    -- ================================================
    BEGIN
        DBMS_OUTPUT.PUT_LINE('8. Заполняем таблицу test_results...');
        
        -- Анализы крови для первых 5 пациентов
        FOR i IN 1..5 LOOP
            INSERT INTO test_results (patient_id, test_type, test_date, result_date, result_value, normal_range)
            SELECT 
                patient_id,
                'Общий анализ крови',
                SYSDATE - 30,
                SYSDATE - 29,
                'Лейкоциты: 6.5, Гемоглобин: 135, Тромбоциты: 250',
                'Лейкоциты: 4-9, Гемоглобин: 120-160, Тромбоциты: 180-320'
            FROM (SELECT patient_id, ROWNUM rn FROM patients ORDER BY patient_id)
            WHERE rn = i;
            
            v_test_count := v_test_count + 1;
            
            INSERT INTO test_results (patient_id, test_type, test_date, result_date, result_value, normal_range)
            SELECT 
                patient_id,
                'Биохимический анализ крови',
                SYSDATE - 25,
                SYSDATE - 24,
                'Глюкоза: 5.2, Холестерин: 4.8, АЛТ: 25',
                'Глюкоза: 3.3-6.1, Холестерин: <5.2, АЛТ: <41'
            FROM (SELECT patient_id, ROWNUM rn FROM patients ORDER BY patient_id)
            WHERE rn = i;
            
            v_test_count := v_test_count + 1;
        END LOOP;
        
        -- Дополнительные анализы
        INSERT INTO test_results (patient_id, test_type, test_date, result_date, result_value, normal_range)
        SELECT 
            patient_id,
            'ЭКГ',
            SYSDATE - 15,
            SYSDATE - 14,
            'Ритм синусовый, ЧСС: 72 уд/мин, Патологий не выявлено',
            'Ритм синусовый, ЧСС: 60-90 уд/мин'
        FROM (SELECT patient_id, ROWNUM rn FROM patients ORDER BY patient_id)
        WHERE rn = 6;
        v_test_count := v_test_count + 1;
        
        INSERT INTO test_results (patient_id, test_type, test_date, result_date, result_value, normal_range)
        SELECT 
            patient_id,
            'УЗИ брюшной полости',
            SYSDATE - 10,
            SYSDATE - 9,
            'Печень: размеры нормальные, эхогенность умеренно повышена. Желчный пузырь: без конкрементов.',
            'Органы брюшной полости без патологий'
        FROM (SELECT patient_id, ROWNUM rn FROM patients ORDER BY patient_id)
        WHERE rn = 8;
        v_test_count := v_test_count + 1;
        
        INSERT INTO test_results (patient_id, test_type, test_date, result_date, result_value, normal_range)
        SELECT 
            patient_id,
            'Флюорография',
            SYSDATE - 5,
            SYSDATE - 4,
            'Легочные поля чистые, корни структурны, синусы свободны',
            'Патологий не выявлено'
        FROM (SELECT patient_id, ROWNUM rn FROM patients ORDER BY patient_id)
        WHERE rn = 10;
        v_test_count := v_test_count + 1;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('   Успешно: создано ' || v_test_count || ' результатов анализов');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('   Ошибка при создании результатов анализов: ' || SQLERRM);
            DBMS_OUTPUT.PUT_LINE('   Продолжаем выполнение...');
            ROLLBACK;
    END;
    
    -- ================================================
    -- Итоги выполнения
    -- ================================================
    DBMS_OUTPUT.PUT_LINE('=========================================');
    DBMS_OUTPUT.PUT_LINE('Заполнение базы данных завершено!');
    DBMS_OUTPUT.PUT_LINE('Итоги:');
    DBMS_OUTPUT.PUT_LINE('- ' || v_specialties_count || ' специальностей врачей');
    DBMS_OUTPUT.PUT_LINE('- 4 административных пользователя (1 HEAD_DOCTOR, 3 REGISTRAR)');
    DBMS_OUTPUT.PUT_LINE('- ' || v_doctor_count || ' врачей (с пользователями DOCTOR)');
    DBMS_OUTPUT.PUT_LINE('- ' || v_patient_count || ' пациентов');
    DBMS_OUTPUT.PUT_LINE('- ' || v_schedule_count || ' записей в расписании врачей');
    DBMS_OUTPUT.PUT_LINE('- ' || v_appointment_count || ' записей на прием');
    DBMS_OUTPUT.PUT_LINE('- ' || v_record_count || ' медицинских записей');
    DBMS_OUTPUT.PUT_LINE('- ' || v_test_count || ' результатов анализов');
    DBMS_OUTPUT.PUT_LINE('=========================================');
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Критическая ошибка в основном блоке: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('Backtrace: ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/