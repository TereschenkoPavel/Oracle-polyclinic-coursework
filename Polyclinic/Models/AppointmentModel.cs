using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace Clinic.Models
{
    public class AppointmentModel
    {
        [JsonPropertyName("appointment_id")]
        public int AppointmentId { get; set; }
        [JsonPropertyName("patient_id")]
        [Required(ErrorMessage = "Пациент обязателен")]
        [Display(Name = "Пациент")]
        public int PatientId { get; set; }
        [JsonPropertyName("doctor_id")]
        [Required(ErrorMessage = "Врач обязателен")]
        [Display(Name = "Врач")]
        public int DoctorId { get; set; }
        [JsonPropertyName("appointment_date")]
        [Required(ErrorMessage = "Дата и время приема обязательны")]
        [Display(Name = "Дата и время приема")]
        [DataType(DataType.DateTime)]
        public DateTime AppointmentDate { get; set; }
        [JsonPropertyName("status")]
        [Display(Name = "Статус")]
        public string Status { get; set; } = "SCHEDULED";
        [JsonPropertyName("patient_name")]
        public string? PatientName { get; set; }
        [JsonPropertyName("doctor_name")]
        public string? DoctorName { get; set; }
        [JsonPropertyName("phone")]
        public string? Phone { get; set; }
        [JsonPropertyName("office_number")]
        public string? OfficeNumber { get; set; }
        public string? SpecialtyName { get; set; }
        public int? DurationMinutes { get; set; }

        public List<PatientOption> Patients { get; set; } = new();
        public List<DoctorOption> Doctors { get; set; } = new();
        public List<AvailableTimeSlot> AvailableSlots { get; set; } = new();

        public string? SearchDate { get; set; }
    }
    public class PatientOption
    {
        [JsonPropertyName("patient_id")]
        public int PatientId { get; set; }
        [JsonPropertyName("full_name")]
        public string FullName { get; set; }
    }
    public class AppointmentSlot
    {
        public string Time { get; set; }
        public bool IsAvailable { get; set; }
        public string Status { get; set; }
    }
}