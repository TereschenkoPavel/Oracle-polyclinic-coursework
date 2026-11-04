using System.ComponentModel.DataAnnotations;

namespace Clinic.Models
{
    public class PatientModel
    {
        public int PatientId { get; set; }

        [Required(ErrorMessage = "Фамилия обязательна")]
        [Display(Name = "Фамилия")]
        public string LastName { get; set; }

        [Required(ErrorMessage = "Имя обязательно")]
        [Display(Name = "Имя")]
        public string FirstName { get; set; }

        [Display(Name = "Отчество")]
        public string MiddleName { get; set; }

        [Required(ErrorMessage = "Дата рождения обязательна")]
        [Display(Name = "Дата рождения")]
        [DataType(DataType.Date)]
        public DateTime BirthDate { get; set; }

        [Required(ErrorMessage = "Пол обязателен")]
        [Display(Name = "Пол")]
        public string Gender { get; set; }

        [Display(Name = "Адрес")]
        public string Address { get; set; }

        [Required(ErrorMessage = "Телефон обязателен")]
        [Display(Name = "Телефон")]
        [Phone(ErrorMessage = "Неверный формат телефона")]
        public string Phone { get; set; }

        [Required(ErrorMessage = "Паспорт обязателен")]
        [Display(Name = "Серия и номер паспорта")]
        [RegularExpression(@"^[A-Z]{2}\d{7}$", ErrorMessage = "Формат: AA1234567")]
        public string PassportSeriesNumber { get; set; }

    }
}