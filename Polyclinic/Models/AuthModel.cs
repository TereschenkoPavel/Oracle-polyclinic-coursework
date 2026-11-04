using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace Clinic.Models
{
    public class LoginModel
    {
        [Required(ErrorMessage = "Введите логин")]
        [Display(Name = "Логин")]
        public string Login { get; set; }

        [Required(ErrorMessage = "Введите пароль")]
        [DataType(DataType.Password)]
        [Display(Name = "Пароль")]
        public string Password { get; set; }

    }

    public class UserModel
    {
        [JsonPropertyName("username")]
        public string? Username { get; set; }
        [JsonPropertyName("role_name")]
        public string? Role { get; set; } = "REGISTRAR";
        [JsonPropertyName("user_id")]
        public int UserId { get; set; }


        [Required(ErrorMessage = "Пароль обязателен")]
        [DataType(DataType.Password)]
        [Display(Name = "Пароль")]
        [StringLength(100, MinimumLength = 6, ErrorMessage = "Пароль должен быть от 6 до 100 символов")]
        public string Password { get; set; }

        [DataType(DataType.Password)]
        [Display(Name = "Подтвердите пароль")]
        [Compare("Password", ErrorMessage = "Пароли не совпадают")]
        public string ConfirmPassword { get; set; }

    }
    public class RegisterModel
    {
        public int UserId { get; set; }
        [Required(ErrorMessage = "Введите логин")]
        [StringLength(50, MinimumLength = 3, ErrorMessage = "Логин должен быть от 3 до 50 символов")]
        [Display(Name = "Логин")]
        [RegularExpression(@"^[a-zA-Z0-9_]+$", ErrorMessage = "Логин может содержать только буквы, цифры и подчеркивания")]
        public string Username { get; set; }

        [Required(ErrorMessage = "Введите пароль")]
        [DataType(DataType.Password)]
        [StringLength(100, MinimumLength = 6, ErrorMessage = "Пароль должен быть от 6 до 100 символов")]
        [Display(Name = "Пароль")]
        public string Password { get; set; }

        [DataType(DataType.Password)]
        [Display(Name = "Подтвердите пароль")]
        [Compare("Password", ErrorMessage = "Пароли не совпадают")]
        public string ConfirmPassword { get; set; }

        [Required(ErrorMessage = "Выберите роль")]
        [Display(Name = "Роль")]
        public string Role { get; set; }


        public List<DoctorOption> AvailableDoctors { get; set; } = new();
    }
    public class RegisterResult
    {
        public int ReturnCode { get; set; }
        public string Message { get; set; }
        public RegisterData Data { get; set; }
    }
    public class RegisterData
    {
        [JsonPropertyName("user_id")]
        public int UserId { get; set; }
        [JsonPropertyName("username")]
        public string Username { get; set; }
        [JsonPropertyName("role_name")]
        public string RoleName { get; set; }
        [JsonPropertyName("doctor_id")]
        public int? DoctorId { get; set; }
    }
    public class AuthResult
    {
        [JsonPropertyName("return_code")]
        public int ReturnCode { get; set; }
        [JsonPropertyName("message")]
        public string Message { get; set; }
        [JsonPropertyName("user_id")]
        public int UserId { get; set; }

        [JsonPropertyName("role_name")]
        public string RoleName { get; set; }

        [JsonPropertyName("doctor_id")]
        public int? DoctorId { get; set; }

        [JsonPropertyName("db_connection")]
        public string DbConnection { get; set; }

        [JsonPropertyName("db_connection_pass")]
        public string DbConnectionPass { get; set; }
    }
}