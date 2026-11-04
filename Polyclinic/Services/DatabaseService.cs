using System.Data;
using System.Text.Json;
using System.Text.Json.Serialization;
using Clinic.Models;
using Oracle.ManagedDataAccess.Client;

namespace Clinic.Services
{
    public static class OracleDataReaderExtensions
    {
        public static async Task<string> GetSafeStringAsync(this OracleDataReader reader, int ordinal)
        {
            if (await reader.IsDBNullAsync(ordinal))
                return null;

            return reader.GetString(ordinal);
        }
    }
    public class DatabaseService
    {
        private readonly ConnectionManager _connectionManager;
        private readonly ILogger<DatabaseService> _logger;

        public DatabaseService(ConnectionManager connectionManager, ILogger<DatabaseService> logger)
        {
            _connectionManager = connectionManager;
            _logger = logger;
        }
        public async Task<List<RegisterData>> GetUsersByRoleAsync(string roleName)
        {
            try
            {
                var inputJson = JsonSerializer.Serialize(new { role_name = roleName });
                var outputJson = await CallStoredProcedureAsync("auth_pkg.get_users_by_role_json", inputJson);

                using JsonDocument doc = JsonDocument.Parse(outputJson);
                var root = doc.RootElement;

                if (root.GetProperty("return_code").GetInt32() != 0)
                {
                    throw new Exception(root.GetProperty("message").GetString());
                }

                var users = new List<RegisterData>();
                var dataArray = root.GetProperty("data");

                foreach (var item in dataArray.EnumerateArray())
                {
                    var user = new RegisterData
                    {
                        UserId = item.GetProperty("user_id").GetInt32(),
                        Username = item.GetProperty("username").GetString(),
                        RoleName = item.GetProperty("role_name").GetString(),
                    };

                    if (item.TryGetProperty("doctor_id", out var doctorIdProp) && doctorIdProp.ValueKind != JsonValueKind.Null)
                    {
                        user.DoctorId = doctorIdProp.GetInt32();
                    }

                    users.Add(user);
                }

                return users;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting users by role");
                throw;
            }
        }
        public async Task UpdateUserPasswordAsync(int userId, string newPassword)
        {
            try
            {
                var inputJson = JsonSerializer.Serialize(new
                {
                    user_id = userId,
                    new_password = newPassword
                });

                var outputJson = await CallStoredProcedureAsync("auth_pkg.update_user_password_json", inputJson);

                using JsonDocument doc = JsonDocument.Parse(outputJson);
                var root = doc.RootElement;

                if (root.GetProperty("return_code").GetInt32() != 0)
                {
                    throw new Exception(root.GetProperty("message").GetString());
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating user password");
                throw;
            }
        }
        public async Task DeleteUserAsync(int userId)
        {
            try
            {
                var inputJson = JsonSerializer.Serialize(new { user_id = userId });
                var outputJson = await CallStoredProcedureAsync("auth_pkg.delete_user_json", inputJson);

                using JsonDocument doc = JsonDocument.Parse(outputJson);
                var root = doc.RootElement;

                if (root.GetProperty("return_code").GetInt32() != 0)
                {
                    throw new Exception(root.GetProperty("message").GetString());
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting user");
                throw;
            }
        }

        public async Task<List<DoctorScheduleModel>> GetDoctorSchedulesAsync(int? doctorId = null)
        {
            var schedules = new List<DoctorScheduleModel>();

            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                string outputJson;

                if (doctorId.HasValue)
                {
                    // Используем процедуру для получения расписания конкретного врача
                    using var command = new OracleCommand(
                        "BEGIN admin.doctor_schedule_pkg_json.get_doctor_schedule_json(:input_json, :output_json); END;",
                        connection);

                    command.Parameters.Add("input_json", OracleDbType.Int64).Value = doctorId;
                    command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                    await command.ExecuteNonQueryAsync();
                    outputJson = command.Parameters["output_json"].Value.ToString();
                }
                else
                {
                    // Если врач не указан, получаем список всех врачей и их расписаний
                    // Сначала получаем всех врачей
                    var doctors = await GetDoctorsAsync();
                    var allSchedules = new List<DoctorScheduleModel>();

                    foreach (var doctor in doctors)
                    {
                        try
                        {
                            // Получаем расписание для каждого врача
                            var doctorSchedules = await GetDoctorSchedulesAsync(doctor.DoctorId);
                            allSchedules.AddRange(doctorSchedules);
                        }
                        catch (Exception ex)
                        {
                            _logger.LogWarning(ex, "Error getting schedule for doctor ID {DoctorId}", doctor.DoctorId);
                            // Продолжаем для остальных врачей
                        }
                    }

                    return allSchedules;
                }

                // Десериализуем результат
                var result = JsonSerializer.Deserialize<JsonResponse<List<DoctorScheduleJsonModel>>>(outputJson);

                if (result?.ReturnCode == 0 && result.Data != null)
                {
                    schedules = result.Data.Select(s => new DoctorScheduleModel
                    {
                        ScheduleId = s.ScheduleId,
                        DoctorId = s.DoctorId,
                        SelectedDays = new List<int> { s.DayOfWeek },
                        StartTime = TimeSpan.Parse(s.StartTime),
                        EndTime = TimeSpan.Parse(s.EndTime)
                    }).ToList();
                }
                else
                {
                    _logger.LogWarning("Failed to get doctor schedules: {Message}", result?.Message);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting doctor schedules");
            }

            return schedules;
        }
        public async Task<List<int>> SaveDoctorScheduleAsync(DoctorScheduleModel model)
        {
            var savedScheduleIds = new List<int>();

            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                foreach (var day in model.SelectedDays)
                {
                    var inputJson = JsonSerializer.Serialize(new
                    {
                        doctor_id = model.DoctorId,
                        day_of_week = day,
                        start_time = model.StartTime.ToString(@"hh\:mm"),
                        end_time = model.EndTime.ToString(@"hh\:mm")
                    });

                    using var command = new OracleCommand(
                        "BEGIN admin.doctor_schedule_pkg_json.save_doctor_schedule_json(:input_json, :output_json); END;",
                        connection);

                    command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                    command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                    await command.ExecuteNonQueryAsync();
                    var outputJson = command.Parameters["output_json"].Value.ToString();
                    var result = JsonSerializer.Deserialize<JsonResponse<int>>(outputJson);

                    if (result?.ReturnCode == 0)
                    {
                        savedScheduleIds.Add(result.Data);
                    }
                    else if(result?.ReturnCode == -2)
                    {
                        continue;
                    }
                    else
                    {
                        throw new Exception($"Failed to save schedule for day {day}: {result?.Message}");
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error saving doctor schedule");
                throw;
            }

            return savedScheduleIds;
        }
        public async Task<bool> DeleteAllDoctorScheduleAsync(int doctorId)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new
                {
                    doctor_id = doctorId
                });

                using var command = new OracleCommand(
                    "BEGIN admin.doctor_schedule_pkg_json.delete_all_schedule_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<int>>(outputJson);

                return result?.ReturnCode == 0;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting doctor schedule");
                throw;
            }
        }

        public async Task<AppointmentValidationResult> ValidateAppointmentTime(int doctorId, DateTime proposedTime)
        {
            var result = new AppointmentValidationResult();

            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                // Получаем специальность врача и длительность приема
                var doctor = (await GetDoctorsAsync()).FirstOrDefault(d => d.DoctorId == doctorId);
                if (doctor == null)
                {
                    result.IsValid = false;
                    result.Message = "Врач не найден";
                    return result;
                }

                var specialty = (await GetSpecialtiesAsync()).FirstOrDefault(s => s.SpecialtyId == doctor.SpecialtyId);
                int appointmentDuration = specialty?.AppointmentDurationMinutes ?? 30;

                // Проверяем время через пакет
                var inputJson = JsonSerializer.Serialize(new
                {
                    doctor_id = doctorId,
                    appointment_date = proposedTime.ToString("yyyy-MM-dd HH:mm"),
                    duration_minutes = appointmentDuration
                });

                using var command = new OracleCommand(
                    "BEGIN admin.appointment_pkg_json.check_appointment_time_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();
                var validationResult = JsonSerializer.Deserialize<JsonResponse<int>>(outputJson);

                result.IsValid = validationResult?.ReturnCode == 0 && validationResult.Data == 1;
                result.Message = validationResult?.Message ?? "Ошибка проверки времени";
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error validating appointment time");
                result.IsValid = false;
                result.Message = "Ошибка при проверке времени";
            }

            return result;
        }
        public async Task<List<AvailableTimeSlot>> GetAvailableTimeSlots(int doctorId, DateTime date)
        {
            var slots = new List<AvailableTimeSlot>();

            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new
                {
                    doctor_id = doctorId,
                    appointment_date = date.ToString("yyyy-MM-dd")
                });

                using var command = new OracleCommand(
                    "BEGIN doctor_schedule_pkg_json.get_available_slots_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<List<string>>>(outputJson);

                if (result?.ReturnCode == 0 && result.Data != null)
                {
                    var doctor = (await GetDoctorsAsync()).FirstOrDefault(d => d.DoctorId == doctorId);
                    var specialty = doctor != null ?
                        (await GetSpecialtiesAsync()).FirstOrDefault(s => s.SpecialtyId == doctor.SpecialtyId) :
                        null;
                    int duration = specialty?.AppointmentDurationMinutes ?? 30;

                    foreach (var timeStr in result.Data)
                    {
                        var startTime = DateTime.Parse($"{date:yyyy-MM-dd} {timeStr}");
                        var endTime = startTime.AddMinutes(duration);

                        slots.Add(new AvailableTimeSlot
                        {
                            StartTime = startTime,
                            EndTime = endTime,
                            DisplayTime = startTime.ToString("HH:mm"),
                            IsAvailable = true
                        });
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting available time slots");
            }

            return slots;
        }

        public async Task<List<PatientModel>> GetPatientsAsync(string searchTerm = null)
        {
            var patients = new List<PatientModel>();

            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                using var command = new OracleCommand();
                command.Connection = connection;
                command.CommandType = CommandType.Text;

                string outputJson;

                if (string.IsNullOrEmpty(searchTerm))
                {
                    command.CommandText = "BEGIN patient_pkg_json.get_all_patients_json(:output_json); END;";
                    command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;
                }
                else
                {
                    var parts = searchTerm.Split(' ');
                    var lastName = parts.Length > 0 ? parts[0] : "";
                    var firstName = parts.Length > 1 ? parts[1] : "";
                    var middleName = parts.Length > 2 ? parts[2] : null;

                    var inputJson = JsonSerializer.Serialize(new
                    {
                        last_name = lastName,
                        first_name = firstName,
                        middle_name = middleName
                    });

                    command.CommandText = "BEGIN patient_pkg_json.find_patient_by_name_json(:input_json, :output_json); END;";
                    command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                    command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;
                }

                await command.ExecuteNonQueryAsync();
                outputJson = command.Parameters["output_json"].Value.ToString();

                var result = JsonSerializer.Deserialize<JsonResponse<List<PatientJsonModel>>>(outputJson);

                if (result?.ReturnCode == 0 && result.Data != null)
                {
                    patients = result.Data.Select(p => new PatientModel
                    {
                        PatientId = p.PatientId,
                        LastName = p.LastName,
                        FirstName = p.FirstName,
                        MiddleName = p.MiddleName,
                        BirthDate = DateTime.Parse(p.BirthDate),
                        Gender = p.Gender,
                        Address = p.Address,
                        Phone = p.Phone,
                        PassportSeriesNumber = p.PassportSeriesNumber
                    }).ToList();
                }
                else
                {
                    _logger.LogWarning("Failed to get patients: {Message}", result?.Message);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting patients");
            }

            return patients;
        }
        public async Task<PatientModel> GetPatientByIdAsync(int patientId)
        {
            try
            {
                var patients = await GetPatientsAsync();
                return patients.FirstOrDefault(p => p.PatientId == patientId);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting patient by ID");
                return null;
            }
        }
        public async Task<int> AddPatientAsync(PatientModel model)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new
                {
                    last_name = model.LastName,
                    first_name = model.FirstName,
                    middle_name = model.MiddleName,
                    birth_date = model.BirthDate.ToString("yyyy-MM-dd"),
                    gender = model.Gender,
                    address = model.Address,
                    phone = model.Phone,
                    passport_series_number = model.PassportSeriesNumber
                });

                using var command = new OracleCommand(
                    "BEGIN patient_pkg_json.add_patient_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();

                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<int>>(outputJson);

                if (result?.ReturnCode == 0)
                {
                    return result.Data;
                }
                else
                {
                    throw new Exception($"Failed to add patient: {result?.Message}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error adding patient");
                throw;
            }
        }
        public async Task<bool> UpdatePatientAsync(PatientModel model)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new
                {
                    patient_id = model.PatientId,
                    last_name = model.LastName,
                    first_name = model.FirstName,
                    middle_name = model.MiddleName,
                    birth_date = model.BirthDate.ToString("yyyy-MM-dd"),
                    gender = model.Gender,
                    address = model.Address,
                    phone = model.Phone,
                    passport_series_number = model.PassportSeriesNumber
                });

                using var command = new OracleCommand(
                    "BEGIN admin.patient_pkg_json.update_patient_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<object>>(outputJson);

                return result?.ReturnCode == 0;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating patient");
                throw;
            }
        }

        public async Task<bool> DeletePatientAsync(int patientId)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new { patient_id = patientId });

                using var command = new OracleCommand(
                    "BEGIN admin.patient_pkg_json.delete_patient_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<object>>(outputJson);

                return result?.ReturnCode == 0;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting patient");
                throw;
            }
        }

        public async Task<List<DoctorModel>> GetDoctorsAsync()
        {
            OracleConnection connection = null;
            OracleCommand command = null;
            OracleDataReader reader = null;

            try
            {
                // Создаем подключение
                connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                // Создаем команду для вызова хранимой процедуры
                command = new OracleCommand("doctor_management_pkg_json.get_doctors_list", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };

                // Добавляем выходной параметр курсора
                var cursorParam = command.Parameters.Add("p_result_cursor", OracleDbType.RefCursor);
                cursorParam.Direction = ParameterDirection.Output;

                // Выполняем процедуру и получаем DataReader
                reader = (OracleDataReader)await command.ExecuteReaderAsync();

                // Читаем данные из курсора
                var doctors = new List<DoctorModel>();

                while (await reader.ReadAsync())
                {
                    var doctor = new DoctorModel
                    {
                        DoctorId = Convert.ToInt32(reader.GetValue(0)),
                        LastName = await reader.GetSafeStringAsync( 1),
                        FirstName = await reader.GetSafeStringAsync(2),
                        MiddleName = await reader.GetSafeStringAsync(3),
                        SpecialtyId = Convert.ToInt32(reader.GetValue(4)),
                        SpecialtyName = await reader.GetSafeStringAsync(5),
                        OfficeNumber = await reader.GetSafeStringAsync(6),
                        Phone = await reader.GetSafeStringAsync(7),
                        PassportSeriesNumber = await reader.GetSafeStringAsync(8)
                    };

                    doctors.Add(doctor);
                }

                return doctors;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting doctors");
                throw; // Пробрасываем исключение дальше
            }
            finally
            {
                // Освобождаем ресурсы
                reader?.Close();
                reader?.Dispose();
                command?.Dispose();

                if (connection != null && connection.State == ConnectionState.Open)
                {
                    await connection.CloseAsync();
                }
                connection?.Dispose();
            }
        }



        public async Task<List<Specialty>> GetSpecialtiesAsync()
        {
            var specialties = new List<Specialty>();

            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                using var command = new OracleCommand(
                    "BEGIN doctor_management_pkg_json.get_specialties_json(:output_json); END;",
                    connection);

                command.CommandType = CommandType.Text;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;
                try
                {
                    await command.ExecuteNonQueryAsync();
                }
                catch (Exception e)
                {
                    Console.WriteLine(e.Message);
                }
                var outputJson = command.Parameters["output_json"].Value.ToString();

                var result = JsonSerializer.Deserialize<JsonResponse<List<SpecialtyJsonModel>>>(outputJson);

                if (result?.ReturnCode == 0 && result.Data != null)
                {
                    specialties = result.Data.Select(s => new Specialty
                    {
                        SpecialtyId = s.SpecialtyId,
                        SpecialtyName = s.SpecialtyName,
                        AppointmentDurationMinutes = s.AppointmentDurationMinutes
                    }).ToList();
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting specialties");
            }

            return specialties;
        }
        public async Task<int> AddDoctorAsync(DoctorModel model)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new
                {
                    last_name = model.LastName,
                    first_name = model.FirstName,
                    middle_name = model.MiddleName,
                    specialty_id = model.SpecialtyId,
                    office_number = model.OfficeNumber,
                    phone = model.Phone,
                    passport_series_number = model.PassportSeriesNumber,
                    username = model.Username,
                    password = model.Password
                });
                using var command = new OracleCommand(
                    "BEGIN doctor_management_pkg_json.add_doctor_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();

                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<int>>(outputJson);

                if (result?.ReturnCode == 0)
                {
                    return result.Data;
                }
                else
                {
                    throw new Exception($"Failed to add doctor: {result?.Message}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error adding doctor");
                throw;
            }
        }
        public async Task<DoctorModel> GetDoctorByIdAsync(int doctorId)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new { doctor_id = doctorId });
                using var command = new OracleCommand(
                    "BEGIN admin.doctor_management_pkg_json.get_doctor_by_id_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();

                var result = JsonSerializer.Deserialize<JsonResponse<Doctor>>(outputJson);

                if (result?.ReturnCode == 0 && result.Data != null)
                {
                    var doctor = result.Data;
                    return new DoctorModel
                    {
                        DoctorId = doctor.DoctorId,
                        LastName = doctor.LastName,
                        FirstName = doctor.FirstName,
                        MiddleName = doctor.MiddleName,
                        SpecialtyId = doctor.SpecialtyId,
                        SpecialtyName = doctor.SpecialtyName,
                        OfficeNumber = doctor.OfficeNumber,
                        Phone = doctor.Phone,
                        PassportSeriesNumber = doctor.PassportSeriesNumber
                    };
                }
                else
                {
                    _logger.LogWarning("Failed to get doctor by ID: {Message}", result?.Message);
                    return null;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting doctor by ID");
                return null;
            }
        }
        public async Task<bool> UpdateDoctorAsync(DoctorModel model)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new
                {
                    doctor_id = model.DoctorId,
                    last_name = model.LastName,
                    first_name = model.FirstName,
                    middle_name = model.MiddleName,
                    specialty_id = model.SpecialtyId,
                    office_number = model.OfficeNumber,
                    phone = model.Phone,
                    passport_series_number = model.PassportSeriesNumber
                });

                using var command = new OracleCommand(
                    "BEGIN admin.doctor_management_pkg_json.update_doctor_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<object>>(outputJson);

                return result?.ReturnCode == 0;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating doctor");
                throw;
            }
        }
        public async Task<bool> DeleteDoctorAsync(int doctorId)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new { doctor_id = doctorId });

                using var command = new OracleCommand(
                    "BEGIN admin.doctor_management_pkg_json.delete_doctor_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<object>>(outputJson);

                return result?.ReturnCode == 0;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting doctor");
                throw;
            }
        }
        public async Task<DoctorModel> GetDoctorCredentialsAsync(int doctorId)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new { doctor_id = doctorId });
                using var command = new OracleCommand(
                    "BEGIN admin.doctor_management_pkg_json.get_doctor_credentials_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();

                var result = JsonSerializer.Deserialize<JsonResponse<DoctorModel>>(outputJson);

                if (result?.ReturnCode == 0 && result.Data != null)
                {
                    return result.Data;
                }
                else
                {
                    _logger.LogWarning("Failed to get doctor credentials: {Message}", result?.Message);
                    return null;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting doctor credentials");
                return null;
            }
        }
        public async Task<bool> UpdateDoctorCredentialsAsync(int doctorId, string username, string password)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new
                {
                    doctor_id = doctorId,
                    username = username,
                    password = password
                });

                using var command = new OracleCommand(
                    "BEGIN admin.doctor_management_pkg_json.update_doctor_credentials_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<object>>(outputJson);

                return result?.ReturnCode == 0;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating doctor credentials");
                throw;
            }
        }
        public async Task<DoctorModel> GetDoctorForEditAsync(int doctorId)
        {
            var doctor = await GetDoctorByIdAsync(doctorId);
            if (doctor == null) return null;

            var credentials = await GetDoctorCredentialsAsync(doctorId);

            return new DoctorModel
            {
                DoctorId = doctor.DoctorId,
                LastName = doctor.LastName,
                FirstName = doctor.FirstName,
                MiddleName = doctor.MiddleName,
                SpecialtyId = doctor.SpecialtyId,
                SpecialtyName = doctor.SpecialtyName,
                OfficeNumber = doctor.OfficeNumber,
                Phone = doctor.Phone,
                PassportSeriesNumber = doctor.PassportSeriesNumber,
                Username = credentials?.Username,
                Specialties = await GetSpecialtiesAsync()
            };
        }

        public async Task<AppointmentModel> GetAppointmentByIdAsync(int appointmentId)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new { appointment_id = appointmentId });
                using var command = new OracleCommand(
                    "BEGIN admin.appointment_pkg_json.get_appointment_by_id_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<AppointmentModel>>(outputJson);

                if (result?.ReturnCode == 0 && result.Data != null)
                {
                    var appointment = result.Data;
                    return new AppointmentModel
                    {
                        AppointmentId = appointment.AppointmentId,
                        PatientId = appointment.PatientId,
                        DoctorId = appointment.DoctorId,
                        AppointmentDate = appointment.AppointmentDate,
                        Status = appointment.Status,
                        PatientName = appointment.PatientName,
                        DoctorName = appointment.DoctorName,
                        Phone = appointment.Phone,
                        OfficeNumber = appointment.OfficeNumber,
                        SpecialtyName = appointment.SpecialtyName,
                        DurationMinutes = appointment.DurationMinutes
                    };
                }
                else
                {
                    _logger.LogWarning("Failed to get appointment: {Message}", result?.Message);
                    return null;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting appointment by ID");
                return null;
            }
        }
        public async Task<bool> CancelAppointmentAsync(int appointmentId, string cancelReason = null)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new
                {
                    appointment_id = appointmentId,
                    cancel_reason = cancelReason
                });

                using var command = new OracleCommand(
                    "BEGIN admin.appointment_pkg_json.cancel_appointment_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<object>>(outputJson);

                return result?.ReturnCode == 0;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error canceling appointment");
                throw;
            }
        }
        public async Task<bool> RescheduleAppointmentAsync(int appointmentId, DateTime newAppointmentDate)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new
                {
                    appointment_id = appointmentId,
                    new_appointment_date = newAppointmentDate.ToString("yyyy-MM-ddTHH:mm:ss")
                });

                using var command = new OracleCommand(
                    "BEGIN admin.appointment_pkg_json.reschedule_appointment_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<object>>(outputJson);

                return result?.ReturnCode == 0;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error rescheduling appointment");
                throw;
            }
        }
        public async Task<bool> UpdateAppointmentStatusAsync(int appointmentId, string status)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new
                {
                    appointment_id = appointmentId,
                    status = status
                });

                using var command = new OracleCommand(
                    "BEGIN admin.appointment_pkg_json.update_appointment_status_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<object>>(outputJson);

                return result?.ReturnCode == 0;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating appointment status");
                throw;
            }
        }
        public async Task<List<AppointmentModel>> GetAppointmentsAsync(int? doctorId = null, int? patientId = null)
        {
            var appointments = new List<AppointmentModel>();

            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                OracleCommand command;
                string outputJson;

                if (doctorId.HasValue)
                {
                    var inputJson = JsonSerializer.Serialize(new
                    {
                        doctor_id = doctorId.Value,
                        start_date = DateTime.Today.ToString("yyyy-MM-dd"),
                        end_date = DateTime.Today.AddDays(30).ToString("yyyy-MM-dd") // увеличим период до 30 дней
                    });

                    command = new OracleCommand(
                        "BEGIN admin.appointment_pkg_json.get_doctor_appointments_json(:input_json, :output_json); END;",
                        connection);
                    command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                    command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                    await command.ExecuteNonQueryAsync();
                    outputJson = command.Parameters["output_json"].Value.ToString();
                    var result = JsonSerializer.Deserialize<JsonResponse<List<AppointmentModel>>>(outputJson);
                    if (result?.ReturnCode == 0 && result.Data != null)
                    {
                        appointments = result.Data.Select(a => new AppointmentModel
                        {
                            AppointmentId = a.AppointmentId,
                            PatientId = a.PatientId,
                            DoctorId = a.DoctorId,
                            AppointmentDate = a.AppointmentDate,
                            Status = a.Status,
                            PatientName = a.PatientName,
                            DoctorName = a.DoctorName,
                            Phone = a.Phone,
                            OfficeNumber = a.OfficeNumber
                        }).ToList();
                        if (patientId.HasValue)
                        {
                            appointments = appointments
                                .Where(a => a.PatientId == patientId.Value)
                                .ToList();
                        }

                    }
                    else
                    {
                        _logger.LogWarning("Failed to get appointments: {Message}", result?.Message);
                    }
                }
                else if (patientId.HasValue)
                {
                    var allAppointments = await GetAllAppointmentsJsonAsync(connection);
                    appointments = allAppointments
                        .Where(a => a.PatientId == patientId.Value)
                        .ToList();
                    return appointments;
                }
                else
                {
                    appointments = await GetAllAppointmentsJsonAsync(connection);
                    return appointments;
                }
                
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting appointments");
            }
            return appointments;
        }
        private async Task<List<AppointmentModel>> GetAllAppointmentsJsonAsync(OracleConnection connection)
        {
            var appointments = new List<AppointmentModel>();

            try
            {
                using var command = new OracleCommand(
                    "BEGIN admin.appointment_pkg_json.get_all_appointments_json(:output_json); END;",
                    connection);

                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();

                var result = JsonSerializer.Deserialize<JsonResponse<List<AppointmentModel>>>(outputJson);

                if (result?.ReturnCode == 0 && result.Data != null)
                {
                    appointments = result.Data.Select(a => new AppointmentModel
                    {
                        AppointmentId = a.AppointmentId,
                        PatientId = a.PatientId,
                        DoctorId = a.DoctorId,
                        AppointmentDate = a.AppointmentDate,
                        Status = a.Status,
                        PatientName = a.PatientName,
                        DoctorName = a.DoctorName,
                        Phone = a.Phone,
                        OfficeNumber = a.OfficeNumber
                    }).ToList();
                }
                else
                {
                    _logger.LogWarning("Failed to get all appointments: {Message}", result?.Message);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting all appointments");
            }

            return appointments;
        }
        public async Task<List<AppointmentSlot>> GetAppointmentSlotsAsync(int doctorId, DateTime date)
        {
            var slots = new List<AppointmentSlot>();

            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new
                {
                    doctor_id = doctorId,
                    appointment_date = date.ToString("yyyy-MM-dd")
                });

                using var command = new OracleCommand(
                    "BEGIN admin.appointment_pkg_json.get_appointment_slots_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();
                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<List<string>>>(outputJson);

                if (result?.ReturnCode == 0 && result.Data != null)
                {
                    // Проверяем занятые слоты
                    var appointments = await GetAppointmentsAsync(doctorId);
                    var bookedSlots = appointments
                        .Where(a => a.AppointmentDate.Date == date.Date && a.Status != "CANCELLED")
                        .Select(a => a.AppointmentDate.ToString("HH:mm"))
                        .ToList();

                    foreach (var timeStr in result.Data)
                    {
                        slots.Add(new AppointmentSlot
                        {
                            Time = timeStr,
                            IsAvailable = !bookedSlots.Contains(timeStr),
                            Status = bookedSlots.Contains(timeStr) ? "Занято" : "Доступно"
                        });
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting appointment slots");
            }

            return slots;
        }
        public async Task<int> AddAppointmentAsync(AppointmentModel model)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new
                {
                    patient_id = model.PatientId,
                    doctor_id = model.DoctorId,
                    appointment_date = model.AppointmentDate.ToString("yyyy-MM-ddTHH:mm:ss")
                });

                using var command = new OracleCommand(
                    "BEGIN admin.appointment_pkg_json.create_appointment_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();

                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<int>>(outputJson);

                if (result?.ReturnCode == 0)
                {
                    return result.Data;
                }
                else
                {
                    throw new Exception($"Failed to add appointment: {result?.Message}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error adding appointment");
                throw;
            }
        }

        public async Task<MedicalRecordModel> GetMedicalRecordByIdAsync(int recordId)
        {
            try
            {
                var inputJson = JsonSerializer.Serialize(new { record_id = recordId });
                var outputJson = await CallStoredProcedureAsync("medical_record_pkg_json.get_medical_record_by_id_json", inputJson);

                using JsonDocument doc = JsonDocument.Parse(outputJson);
                var root = doc.RootElement;

                if (root.GetProperty("return_code").GetInt32() != 0)
                {
                    throw new Exception(root.GetProperty("message").GetString());
                }

                var data = root.GetProperty("data");
                return new MedicalRecordModel
                {
                    RecordId = data.GetProperty("record_id").GetInt32(),
                    PatientId = data.GetProperty("patient_id").GetInt32(),
                    PatientName = data.GetProperty("patient_name").GetString(),
                    DoctorId = data.GetProperty("doctor_id").GetInt32(),
                    DoctorName = data.GetProperty("doctor_name").GetString(),
                    Diagnosis = data.GetProperty("diagnosis").GetString(),
                    Prescription = data.GetProperty("prescription").GetString(),
                    Notes = data.GetProperty("notes").GetString(),
                    RecordDate = DateTime.Parse(data.GetProperty("record_date").GetString())
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting medical record by ID");
                throw;
            }
        }
        public async Task<List<MedicalRecordModel>> GetAllMedicalRecordsAsync()
        {
            OracleConnection connection = null;
            OracleCommand command = null;
            OracleDataReader reader = null;
            
            try
            {
                // Создаем подключение
                connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                // Создаем команду для вызова хранимой процедуры
                command = new OracleCommand("medical_record_pkg_json.get_all_medical_records", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };

                // Добавляем выходной параметр курсора
                var cursorParam = command.Parameters.Add("p_result_cursor", OracleDbType.RefCursor);
                cursorParam.Direction = ParameterDirection.Output;

                // Выполняем процедуру и получаем DataReader
                reader = (OracleDataReader)await command.ExecuteReaderAsync();

                // Читаем данные из курсора
                var records = new List<MedicalRecordModel>();
                
                while (await reader.ReadAsync())
                {
                    var record = new MedicalRecordModel
                    {
                        RecordId = (int) reader.GetDecimal(0),
                        Diagnosis = await GetStringOrDefaultAsync(reader, 1),
                        Prescription = await GetStringOrDefaultAsync(reader, 2),
                        Notes = await GetStringOrDefaultAsync(reader, 3),
                        PatientId = (int) reader.GetDecimal(5),
                        PatientName = await GetStringOrDefaultAsync(reader, 6),
                        DoctorId = (int) reader.GetDecimal(7),
                        DoctorName = await GetStringOrDefaultAsync(reader, 8)
                    };

                    // Обрабатываем дату
                    var recordDateValue = reader.GetValue(4);
                    if (recordDateValue != DBNull.Value && recordDateValue is DateTime)
                    {
                        record.RecordDate = (DateTime)recordDateValue;
                    }
                    else if (recordDateValue != DBNull.Value)
                    {
                        // Пытаемся распарсить строку, если дата возвращается как строка
                        if (DateTime.TryParse(recordDateValue.ToString(), out var parsedDate))
                        {
                            record.RecordDate = parsedDate;
                        }
                    }

                    records.Add(record);
                }

                return records;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting all medical records");
                throw;
            }
            finally
            {
                // Освобождаем ресурсы
                reader?.Close();
                reader?.Dispose();
                command?.Dispose();
                
                if (connection != null && connection.State == ConnectionState.Open)
                {
                    await connection.CloseAsync();
                }
                connection?.Dispose();
            }
        }
        private async Task<string> GetStringOrDefaultAsync(OracleDataReader reader, int ordinal)
        {
            if (await reader.IsDBNullAsync(ordinal))
                return null;

            try
            {
                return reader.GetString(ordinal);
            }
            catch
            {
                // Если не удается получить как строку, преобразуем значение в строку
                var value = reader.GetValue(ordinal);
                return value?.ToString();
            }
        }
        // Вспомогательные методы расширения для безопасного чтения строк

        public async Task UpdateMedicalRecordAsync(MedicalRecordModel model)
        {
            try
            {
                var inputJson = JsonSerializer.Serialize(new
                {
                    record_id = model.RecordId,
                    diagnosis = model.Diagnosis,
                    prescription = model.Prescription,
                    notes = model.Notes
                });

                var outputJson = await CallStoredProcedureAsync("medical_record_pkg_json.update_medical_record_json", inputJson);

                using JsonDocument doc = JsonDocument.Parse(outputJson);
                var root = doc.RootElement;

                if (root.GetProperty("return_code").GetInt32() != 0)
                {
                    throw new Exception(root.GetProperty("message").GetString());
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating medical record");
                throw;
            }
        }
        public async Task DeleteMedicalRecordAsync(int recordId)
        {
            try
            {
                var inputJson = JsonSerializer.Serialize(new { record_id = recordId });
                var outputJson = await CallStoredProcedureAsync("medical_record_pkg_json.delete_medical_record_json", inputJson);

                using JsonDocument doc = JsonDocument.Parse(outputJson);
                var root = doc.RootElement;

                if (root.GetProperty("return_code").GetInt32() != 0)
                {
                    throw new Exception(root.GetProperty("message").GetString());
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting medical record");
                throw;
            }
        }
        public async Task<int> AddMedicalRecordAsync(MedicalRecordModel model)
        {
            try
            {
                var inputJson = JsonSerializer.Serialize(new
                {
                    patient_id = model.PatientId,
                    doctor_id = model.DoctorId,
                    diagnosis = model.Diagnosis,
                    prescription = model.Prescription,
                    notes = model.Notes
                });

                var outputJson = await CallStoredProcedureAsync("medical_record_pkg_json.create_medical_record_json", inputJson);

                using JsonDocument doc = JsonDocument.Parse(outputJson);
                var root = doc.RootElement;

                if (root.GetProperty("return_code").GetInt32() != 0)
                {
                    throw new Exception(root.GetProperty("message").GetString());
                }

                return root.GetProperty("record_id").GetInt32();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error adding medical record");
                throw;
            }
        }
        public async Task<List<MedicalRecordModel>> GetMedicalRecordsAsync(int? doctorId = null, int? patientId = null)
        {
            var records = new List<MedicalRecordModel>();

            try
            {
                if (patientId.HasValue)
                {
                    var inputJson = JsonSerializer.Serialize(new { patient_id = patientId.Value });
                    var outputJson = await CallStoredProcedureAsync("medical_record_pkg_json.get_patient_records_json", inputJson);

                    using JsonDocument doc = JsonDocument.Parse(outputJson);
                    var root = doc.RootElement;

                    if (root.GetProperty("return_code").GetInt32() == 0)
                    {
                        var dataArray = root.GetProperty("data");
                        foreach (var item in dataArray.EnumerateArray())
                        {

                            var record = new MedicalRecordModel
                            {
                            
                                RecordId = item.GetProperty("record_id").GetInt32(),
                                Diagnosis = item.GetProperty("diagnosis").GetString(),
                                Prescription = item.GetProperty("prescription").GetString(),
                                Notes = item.GetProperty("notes").GetString(),
                                RecordDate = DateTime.Parse(item.GetProperty("record_date").GetString()),
                                DoctorId = item.GetProperty("doctor_id").GetInt32(),
                                DoctorName = item.GetProperty("doctor_name").GetString(),
                                PatientId = patientId.Value
                            };
                            records.Add(record);
                        }
                    }
                }
                else if (doctorId.HasValue)
                {
                    var inputJson = JsonSerializer.Serialize(new { doctor_id = doctorId.Value });
                    var outputJson = await CallStoredProcedureAsync("medical_record_pkg_json.get_doctor_records_json", inputJson);

                    using JsonDocument doc = JsonDocument.Parse(outputJson);
                    var root = doc.RootElement;

                    if (root.GetProperty("return_code").GetInt32() == 0)
                    {
                        var dataArray = root.GetProperty("data");
                        foreach (var item in dataArray.EnumerateArray())
                        {
                            var record = new MedicalRecordModel
                            {
                                RecordId = item.GetProperty("record_id").GetInt32(),
                                Diagnosis = item.GetProperty("diagnosis").GetString(),
                                Prescription = item.GetProperty("prescription").GetString(),
                                Notes = item.GetProperty("notes").GetString(),
                                RecordDate = DateTime.Parse(item.GetProperty("record_date").GetString()),
                                PatientId = item.GetProperty("patient_id").GetInt32(),
                                PatientName = item.GetProperty("patient_name").GetString(),
                                DoctorId = item.GetProperty("doctor_id").GetInt32(),
                                DoctorName = item.GetProperty("doctor_name").GetString()
                            };
                            records.Add(record);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting medical records");
            }

            return records;
        }

        public async Task<int> AddTestResultAsync(TestResultModel model)
        {
            try
            {
                using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                var inputJson = JsonSerializer.Serialize(new
                {
                    patient_id = model.PatientId,
                    test_type = model.TestType,
                    test_date = model.TestDate.ToString("yyyy-MM-dd"),
                    result_value = model.ResultValue,
                    normal_range = model.NormalRange
                });

                using var command = new OracleCommand(
                    "BEGIN test_result_pkg_json.add_test_result_json(:input_json, :output_json); END;",
                    connection);

                command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
                command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

                await command.ExecuteNonQueryAsync();

                var outputJson = command.Parameters["output_json"].Value.ToString();
                var result = JsonSerializer.Deserialize<JsonResponse<int>>(outputJson);

                if (result?.ReturnCode == 0)
                {
                    return result.Data;
                }
                else
                {
                    throw new Exception($"Failed to add test result: {result?.Message}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error adding test result");
                throw;
            }
        }

        
        public async Task<List<PatientOption>> GetPatientOptionsAsync()
        {
            var options = new List<PatientOption>();

            try
            {
                var patients = await GetPatientsAsync();
                foreach (var patient in patients)
                {
                    options.Add(new PatientOption
                    {
                        PatientId = patient.PatientId,
                        FullName = $"{patient.LastName} {patient.FirstName} {patient.MiddleName}"
                    });
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting patient options");
            }

            return options;
        }

        public async Task<List<DoctorOption>> GetDoctorOptionsAsync()
        {
            var options = new List<DoctorOption>();

            try
            {
                var doctors = await GetDoctorsAsync();
                foreach (var doctor in doctors)
                {
                    options.Add(new DoctorOption
                    {
                        DoctorId = doctor.DoctorId,
                        FullName = $"{doctor.LastName} {doctor.FirstName} {doctor.MiddleName}",
                        Specialty = doctor.SpecialtyName
                    });
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting doctor options");
            }

            return options;
        }

        public async Task<List<AppointmentOption>> GetAppointmentOptionsAsync(int doctorId)
        {
            var options = new List<AppointmentOption>();

            try
            {
                var appointments = await GetAppointmentsAsync(doctorId);
                foreach (var appointment in appointments)
                {
                    options.Add(new AppointmentOption
                    {
                        AppointmentId = appointment.AppointmentId,
                        AppointmentDate = appointment.AppointmentDate,
                        PatientName = appointment.PatientName,
                        DoctorName = appointment.DoctorName
                    });
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting appointment options");
            }

            return options;
        }

        public async Task<TestResultModel> GetTestResultByIdAsync(int resultId)
        {
            try
            {
                var inputJson = JsonSerializer.Serialize(new { result_id = resultId });
                var outputJson = await CallStoredProcedureAsync("test_result_pkg_json.get_test_result_by_id_json", inputJson);

                using JsonDocument doc = JsonDocument.Parse(outputJson);
                var root = doc.RootElement;

                if (root.GetProperty("return_code").GetInt32() != 0)
                {
                    throw new Exception(root.GetProperty("message").GetString());
                }

                var data = root.GetProperty("data");
                return new TestResultModel
                {
                    ResultId = data.GetProperty("result_id").GetInt32(),
                    PatientId = data.GetProperty("patient_id").GetInt32(),
                    TestType = data.GetProperty("test_type").GetString(),
                    TestDate = DateTime.Parse(data.GetProperty("test_date").GetString()),
                    ResultDate = DateTime.Parse(data.GetProperty("result_date").GetString()),
                    ResultValue = data.GetProperty("result_value").GetString(),
                    NormalRange = data.GetProperty("normal_range").GetString()
                };
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting test result by ID");
                throw;
            }
        }

        
        public async Task UpdateTestResultAsync(TestResultModel model)
        {
            try
            {
                var inputJson = JsonSerializer.Serialize(new
                {
                    result_id = model.ResultId,
                    test_type = model.TestType,
                    test_date = model.TestDate.ToString("yyyy-MM-dd"),
                    result_value = model.ResultValue,
                    normal_range = model.NormalRange
                });

                var outputJson = await CallStoredProcedureAsync("test_result_pkg_json.update_test_result_json", inputJson);

                using JsonDocument doc = JsonDocument.Parse(outputJson);
                var root = doc.RootElement;

                if (root.GetProperty("return_code").GetInt32() != 0)
                {
                    throw new Exception(root.GetProperty("message").GetString());
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating test result");
                throw;
            }
        }

        public async Task DeleteTestResultAsync(int resultId)
        {
            try
            {
                var inputJson = JsonSerializer.Serialize(new { result_id = resultId });
                var outputJson = await CallStoredProcedureAsync("test_result_pkg_json.delete_test_result_json", inputJson);

                using JsonDocument doc = JsonDocument.Parse(outputJson);
                var root = doc.RootElement;

                if (root.GetProperty("return_code").GetInt32() != 0)
                {
                    throw new Exception(root.GetProperty("message").GetString());
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting test result");
                throw;
            }
        }

        public async Task<List<TestResultModel>> SearchTestResultsAsync(string searchTerm)
{
    OracleConnection connection = null;
    OracleCommand command = null;
    OracleDataReader reader = null;
    
    try
    {
        // Создаем подключение
        connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
        await connection.OpenAsync();

        // Создаем команду для вызова хранимой процедуры
        command = new OracleCommand("test_result_pkg_json.find_test_results_by_patient_name", connection)
        {
            CommandType = CommandType.StoredProcedure
        };

        // Входной параметр JSON
        var inputJson = JsonSerializer.Serialize(new { search_term = searchTerm });
        var inputParam = command.Parameters.Add("p_input_json", OracleDbType.Varchar2);
        inputParam.Direction = ParameterDirection.Input;
        inputParam.Value = inputJson;

        // Выходной параметр курсора
        var cursorParam = command.Parameters.Add("p_result_cursor", OracleDbType.RefCursor);
        cursorParam.Direction = ParameterDirection.Output;

        // Выполняем процедуру
        reader = (OracleDataReader)await command.ExecuteReaderAsync();

        // Читаем данные из курсора
        var results = new List<TestResultModel>();
        
        while (await reader.ReadAsync())
        {
            var model = new TestResultModel
            {
                ResultId = await reader.GetFieldValueAsync<int>(0),
                PatientId = await reader.GetFieldValueAsync<int>(1),
                TestType = await reader.GetFieldValueAsync<string>(2),
                ResultValue = await reader.GetFieldValueAsync<string>(5),
                NormalRange = await reader.GetFieldValueAsync<string>(6),
                PatientFullName = await reader.GetFieldValueAsync<string>(7)
            };

            var testDate = reader.GetValue(3);
            if (testDate != DBNull.Value)
            {
                model.TestDate = Convert.ToDateTime(testDate);
            }

            var resultDate = reader.GetValue(4);
            if (resultDate != DBNull.Value)
            {
                model.ResultDate = Convert.ToDateTime(resultDate);
            }


            results.Add(model);
        }

        return results;
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Error searching test results");
        throw;
    }
    finally
    {
        // Освобождаем ресурсы
        reader?.Close();
        reader?.Dispose();
        command?.Dispose();
        
        if (connection != null && connection.State == ConnectionState.Open)
        {
            await connection.CloseAsync();
        }
        connection?.Dispose();
    }
}
        public async Task<List<TestResultModel>> GetTestResultsAsync(string searchTerm = null)
        {
            if (!string.IsNullOrWhiteSpace(searchTerm))
            {
                return await SearchTestResultsAsync(searchTerm);
            }

            OracleConnection connection = null;
            OracleCommand command = null;
            OracleDataReader reader = null;

            try
            {
                // Создаем подключение
                connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
                await connection.OpenAsync();

                // Создаем команду для вызова хранимой процедуры с курсором
                command = new OracleCommand("test_result_pkg_json.get_all_test_results", connection)
                {
                    CommandType = CommandType.StoredProcedure
                };

                // Добавляем выходной параметр курсора
                var cursorParam = command.Parameters.Add("p_result_cursor", OracleDbType.RefCursor);
                cursorParam.Direction = ParameterDirection.Output;

                // Выполняем процедуру и получаем DataReader
                reader = (OracleDataReader)await command.ExecuteReaderAsync();

                // Читаем данные из курсора
                var results = new List<TestResultModel>();

                while (await reader.ReadAsync())
                {
                    var model = new TestResultModel
                    {
                        // Используем Convert.ToInt32 для числовых полей
                        ResultId = Convert.ToInt32(reader.GetValue(0)),
                        PatientId = Convert.ToInt32(reader.GetValue(1)),
                        TestType = reader.IsDBNull(2) ? null : reader.GetString(2),
                        ResultValue = reader.IsDBNull(5) ? null : reader.GetString(5),
                        NormalRange = reader.IsDBNull(6) ? null : reader.GetString(6)
                    };

                    // Обрабатываем даты
                    if (!reader.IsDBNull(3))
                    {
                        var testDateValue = reader.GetValue(3);
                        if (testDateValue is DateTime dateTime)
                        {
                            model.TestDate = dateTime;
                        }
                        else if (DateTime.TryParse(testDateValue.ToString(), out var parsedDate))
                        {
                            model.TestDate = parsedDate;
                        }
                    }

                    if (!reader.IsDBNull(4))
                    {
                        var resultDateValue = reader.GetValue(4);
                        if (resultDateValue is DateTime dateTime)
                        {
                            model.ResultDate = dateTime;
                        }
                        else if (DateTime.TryParse(resultDateValue.ToString(), out var parsedDate))
                        {
                            model.ResultDate = parsedDate;
                        }
                    }

                    // Получаем информацию о пациенте
                    var patient = await GetPatientByIdAsync(model.PatientId);
                    if (patient != null)
                    {
                        model.PatientFullName = $"{patient.LastName} {patient.FirstName} {patient.MiddleName}";
                    }

                    results.Add(model);
                }

                return results;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting test results");
                throw;
            }
            finally
            {
                // Освобождаем ресурсы
                reader?.Close();
                reader?.Dispose();
                command?.Dispose();

                if (connection != null && connection.State == ConnectionState.Open)
                {
                    await connection.CloseAsync();
                }
                connection?.Dispose();
            }
        }
        private async Task<string> CallStoredProcedureAsync(string procedureName, string inputJson)
        {
            using var connection = new OracleConnection(_connectionManager.GetCurrentConnectionString());
            await connection.OpenAsync();

            using var command = new OracleCommand(procedureName, connection)
            {
                CommandType = CommandType.StoredProcedure
            };

            // Добавляем параметры
            if(inputJson != "")
            command.Parameters.Add("p_input_json", OracleDbType.Varchar2).Value = inputJson;
            command.Parameters.Add("p_output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;

            await command.ExecuteNonQueryAsync();

            var outputJson = command.Parameters["p_output_json"].Value.ToString();
            return outputJson;
        }
    }

    // JSON модели для десериализации
    public class JsonResponse<T>
    {
        [JsonPropertyName("return_code")]
        public int ReturnCode { get; set; }
        [JsonPropertyName("message")]
        public string Message { get; set; }
        [JsonPropertyName("data")]
        public T Data { get; set; }
    }
}

