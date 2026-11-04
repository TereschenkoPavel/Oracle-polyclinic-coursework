using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace Clinic.Models
{
    public class DoctorModel
    {
        public int DoctorId { get; set; }
        public string? SpecialtyName { get; set; }

        [Required(ErrorMessage = "Фамилия обязательна")]
        [Display(Name = "Фамилия")]
        public string LastName { get; set; }

        [Required(ErrorMessage = "Имя обязательно")]
        [Display(Name = "Имя")]
        public string FirstName { get; set; }

        [Display(Name = "Отчество")]
        public string MiddleName { get; set; }

        [Required(ErrorMessage = "Специальность обязательна")]
        [Display(Name = "Специальность")]
        public int SpecialtyId { get; set; }



        [Display(Name = "Номер кабинета")]
        public string OfficeNumber { get; set; }

        [Display(Name = "Телефон")]
        //[Phone(ErrorMessage = "Неверный формат телефона")]
        public string Phone { get; set; }

        [Display(Name = "Паспорт")]
        [RegularExpression(@"^[A-Z]{2}\d{7}$", ErrorMessage = "Формат: AA1234567")]
        public string PassportSeriesNumber { get; set; }

        [Display(Name = "Логин")]
        [StringLength(50, MinimumLength = 3, ErrorMessage = "Логин должен быть от 3 до 50 символов")]
        [RegularExpression(@"^[a-zA-Z0-9_]+$", ErrorMessage = "Логин может содержать только буквы, цифры и подчеркивания")]
        public string? Username { get; set; }

        [DataType(DataType.Password)]
        [Display(Name = "Новый пароль")]
        [StringLength(100, MinimumLength = 6, ErrorMessage = "Пароль должен быть от 6 до 100 символов")]
        public string? Password { get; set; }
        public List<Specialty> Specialties { get; set; } = new();
    }

    public class Specialty
    {
        public int SpecialtyId { get; set; }
        public string SpecialtyName { get; set; }
        public int AppointmentDurationMinutes { get; set; }
    }
}