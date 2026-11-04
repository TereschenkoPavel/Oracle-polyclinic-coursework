using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace Clinic.Models
{
    public class TestResultModel
    {
        [JsonPropertyName("result_id")]
        public int ResultId { get; set; }
        [JsonPropertyName("patient_id")]
        [Required(ErrorMessage = "Пациент обязателен")]
        [Display(Name = "Пациент")]
        public int PatientId { get; set; }
        [JsonPropertyName("test_type")]

        [Required(ErrorMessage = "Тип анализа обязателен")]
        [Display(Name = "Тип анализа")]
        public string TestType { get; set; }
        [JsonPropertyName("test_date")]
        [Required(ErrorMessage = "Дата анализа обязательна")]
        [Display(Name = "Дата анализа")]
        [DataType(DataType.Date)]
        public DateTime TestDate { get; set; }
        [Display(Name = "Результат")]
        [JsonPropertyName("result_value")]
        public string ResultValue { get; set; }
        [Display(Name = "Нормальные значения")]
        [JsonPropertyName("normal_range")]
        public string NormalRange { get; set; }
        [Display(Name = "Дата результата")]
        [DataType(DataType.Date)]
        [JsonPropertyName("result_date")]
        public DateTime ResultDate { get; internal set; }
        [Display(Name = "ФИО пациента")]
        public List<PatientOption>? Patients { get; set; }
        public string? PatientFullName { get; set; }
    }

}