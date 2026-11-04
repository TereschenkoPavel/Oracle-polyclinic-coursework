using System.ComponentModel.DataAnnotations;

namespace Clinic.Models
{
    public class MedicalRecordModel
    {
        public int RecordId { get; set; }

        [Required(ErrorMessage = "Пациент обязателен")]
        [Display(Name = "Пациент")]
        public int PatientId { get; set; }

        [Required(ErrorMessage = "Врач обязателен")]
        [Display(Name = "Врач")]
        public int DoctorId { get; set; }

        [Required(ErrorMessage = "Диагноз обязателен")]
        [Display(Name = "Диагноз")]
        public string Diagnosis { get; set; }

        [Display(Name = "Назначение")]
        public string Prescription { get; set; }

        [Display(Name = "Заметки")]
        public string Notes { get; set; }

        public DateTime RecordDate { get; set; }
        public string? PatientName { get; set; }
        public string? DoctorName { get; set; }

        // Списки для выпадающих списков
        public List<PatientOption> Patients { get; set; } = new();
        public List<DoctorOption> Doctors { get; set; } = new();
    }

    public class DoctorOption
    {
        public int DoctorId { get; set; }
        public string FullName { get; set; }
        public string Specialty { get; set; }
    }

    public class AppointmentOption
    {
        public int AppointmentId { get; set; }
        public DateTime AppointmentDate { get; set; }
        public string PatientName { get; set; }
        public string DoctorName { get; set; }
    }
}