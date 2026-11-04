using System.Text.Json.Serialization;

namespace Clinic.Models
{
    public class Patient
    {
        public int PatientId { get; set; }
        public string LastName { get; set; }
        public string FirstName { get; set; }
        public string MiddleName { get; set; }
        public DateTime BirthDate { get; set; }
        public string Gender { get; set; }
        public string Address { get; set; }
        public string Phone { get; set; }
        public string PassportSeriesNumber { get; set; }
        public DateTime CreatedAt { get; set; }
    }

    public class Doctor
    {
        [JsonPropertyName("doctor_id")]

        public int DoctorId { get; set; }
        [JsonPropertyName("last_name")]

        public string LastName { get; set; }
        [JsonPropertyName("first_name")]

        public string FirstName { get; set; }
        [JsonPropertyName("middle_name")]

        public string MiddleName { get; set; }
        [JsonPropertyName("specialty_id")]

        public int SpecialtyId { get; set; }
        [JsonPropertyName("specialty_name")]

        public string SpecialtyName { get; set; }
        [JsonPropertyName("office_number")]

        public string OfficeNumber { get; set; }
        [JsonPropertyName("phone")]

        public string Phone { get; set; }
        [JsonPropertyName("passport_series_number")]

        public string PassportSeriesNumber { get; set; }
    }

    public class Appointment
    {
        public int AppointmentId { get; set; }
        public int PatientId { get; set; }
        public int DoctorId { get; set; }
        public DateTime AppointmentDate { get; set; }
        public string Status { get; set; }
        public string PatientName { get; set; }
        public string DoctorName { get; set; }
    }

    public class MedicalRecord
    {
        public int RecordId { get; set; }
        public int AppointmentId { get; set; }
        public int PatientId { get; set; }
        public int DoctorId { get; set; }
        public string Diagnosis { get; set; }
        public string Prescription { get; set; }
        public string Notes { get; set; }
        public DateTime RecordDate { get; set; }
    }

    public class PatientJsonModel
    {
        [JsonPropertyName("patient_id")]
        public int PatientId { get; set; }
        [JsonPropertyName("last_name")]
        public string LastName { get; set; }
        [JsonPropertyName("first_name")]
        public string FirstName { get; set; }
        [JsonPropertyName("middle_name")]
        public string MiddleName { get; set; }
        [JsonPropertyName("birth_date")]
        public string BirthDate { get; set; }
        [JsonPropertyName("gender")]
        public string Gender { get; set; }
        [JsonPropertyName("address")]
        public string Address { get; set; }
        [JsonPropertyName("phone")]
        public string Phone { get; set; }
        [JsonPropertyName("passport_series_number")]
        public string PassportSeriesNumber { get; set; }
        [JsonPropertyName("created_at")]
        public string CreatedAt { get; set; }
    }
    public class DoctorScheduleJsonModel
    {
        [JsonPropertyName("schedule_id")]
        public int ScheduleId { get; set; }
        [JsonPropertyName("doctor_id")]
        public int DoctorId { get; set; }
        [JsonPropertyName("day_of_week")]
        public int DayOfWeek { get; set; }
        [JsonPropertyName("start_time")]
        public string StartTime { get; set; }
        [JsonPropertyName("end_time")]
        public string EndTime { get; set; }
    }

    public class ValidationResultJson
    {
        [JsonPropertyName("is_valid")]
        public int IsValid { get; set; }
        [JsonPropertyName("message")]
        public string Message { get; set; }
    }

    public class SpecialtyJsonModel
    {
        [JsonPropertyName("specialty_id")]
        public int SpecialtyId { get; set; }
        [JsonPropertyName("specialty_name")]
        public string SpecialtyName { get; set; }
        [JsonPropertyName("appointment_duration_minutes")]
        public int AppointmentDurationMinutes { get; set; }
    }


    public class MedicalRecordJsonModel
    {
        public int RecordId { get; set; }
        public int AppointmentId { get; set; }
        public string Diagnosis { get; set; }
        public string Prescription { get; set; }
        public string Notes { get; set; }
        public string RecordDate { get; set; }
        public int PatientId { get; set; }
        public string PatientName { get; set; }
        public int DoctorId { get; set; }
        public string DoctorName { get; set; }
        public string AppointmentDate { get; set; }
    }

}