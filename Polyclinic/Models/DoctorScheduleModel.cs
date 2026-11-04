using System.ComponentModel.DataAnnotations;

namespace Clinic.Models
{
    public class DoctorScheduleViewModel
    {
        // Информация о враче (только для чтения)
        public DoctorInfo DoctorInfo { get; set; } = new();

        // Модель для ввода/редактирования расписания
        public DoctorScheduleInputModel ScheduleInput { get; set; } = new();

        // Существующее расписание (только для чтения)
        public List<DoctorScheduleDisplayModel> ExistingSchedules { get; set; } = new();

        // Флаги состояния
        public bool ShowDeleteAllButton { get; set; }
        public bool HasExistingSchedules => ExistingSchedules.Any();
        public string? Message { get; set; }
        public bool IsSuccess { get; set; }
    }

    public class DoctorInfo
    {
        public int DoctorId { get; set; }
        public string FullName { get; set; } = string.Empty;
        public string Specialty { get; set; } = string.Empty;
        public string OfficeNumber { get; set; } = string.Empty;
        public string Phone { get; set; } = string.Empty;
    }

    public class DoctorScheduleInputModel
    {
        public int DoctorId { get; set; }

        [Required(ErrorMessage = "Выберите хотя бы один день недели")]
        [Display(Name = "Дни недели")]
        public List<int> SelectedDays { get; set; } = new();

        [Required(ErrorMessage = "Время начала обязательно")]
        [Display(Name = "Время начала")]
        [DataType(DataType.Time)]
        public TimeSpan StartTime { get; set; } = new TimeSpan(9, 0, 0); // 09:00 по умолчанию

        [Required(ErrorMessage = "Время окончания обязательно")]
        [Display(Name = "Время окончания")]
        [DataType(DataType.Time)]
        public TimeSpan EndTime { get; set; } = new TimeSpan(18, 0, 0); // 18:00 по умолчанию

        public List<DayOption> AvailableDays { get; set; } = GetDefaultAvailableDays();

        private static List<DayOption> GetDefaultAvailableDays()
        {
            return new List<DayOption>
            {
                new DayOption { DayNumber = 1, DayName = "Понедельник", ShortName = "Пн", IsSelected = false },
                new DayOption { DayNumber = 2, DayName = "Вторник", ShortName = "Вт", IsSelected = false },
                new DayOption { DayNumber = 3, DayName = "Среда", ShortName = "Ср", IsSelected = false },
                new DayOption { DayNumber = 4, DayName = "Четверг", ShortName = "Чт", IsSelected = false },
                new DayOption { DayNumber = 5, DayName = "Пятница", ShortName = "Пт", IsSelected = false },
                new DayOption { DayNumber = 6, DayName = "Суббота", ShortName = "Сб", IsSelected = false },
                new DayOption { DayNumber = 7, DayName = "Воскресенье", ShortName = "Вс", IsSelected = false }
            };
        }
    }

    public class DoctorScheduleDisplayModel
    {
        public int ScheduleId { get; set; }
        public int DayOfWeek { get; set; }
        public string DayName { get; set; } = string.Empty;
        public TimeSpan StartTime { get; set; }
        public TimeSpan EndTime { get; set; }
        public string TimeRange { get; set; } = string.Empty;
        public string Duration { get; set; } = string.Empty;
    }

    public class DayOption
    {
        public int DayNumber { get; set; }
        public string DayName { get; set; } = string.Empty;
        public string ShortName { get; set; } = string.Empty;
        public bool IsSelected { get; set; }
    }

    public class DoctorScheduleModel
    {
        public DoctorScheduleModel()
        {
            SelectedDays = new List<int>();
            AvailableDays = GetDefaultAvailableDays();
            StartTime = new TimeSpan(9, 0, 0); // 09:00 по умолчанию
            EndTime = new TimeSpan(18, 0, 0);  // 18:00 по умолчанию
        }

        public int ScheduleId { get; set; }

        [Required(ErrorMessage = "Врач обязателен")]
        public int DoctorId { get; set; }

        [Display(Name = "Дни недели")]
        public List<int> SelectedDays { get; set; }

        [Required(ErrorMessage = "Время начала обязательно")]
        [Display(Name = "Время начала")]
        [DataType(DataType.Time)]
        public TimeSpan StartTime { get; set; }

        [Required(ErrorMessage = "Время окончания обязательно")]
        [Display(Name = "Время окончания")]
        [DataType(DataType.Time)]
        public TimeSpan EndTime { get; set; }

        [Display(Name = "ФИО врача")]
        public string DoctorFullName { get; set; }

        public List<DayOption> AvailableDays { get; set; }

        [Display(Name = "Расписание")]
        public string ScheduleDescription { get; set; }

        [Display(Name = "Действие")]
        public string Action { get; set; } = "save";

        private List<DayOption> GetDefaultAvailableDays()
        {
            return new List<DayOption>
            {
                new DayOption { DayNumber = 1, DayName = "Понедельник", ShortName = "Пн", IsSelected = false },
                new DayOption { DayNumber = 2, DayName = "Вторник", ShortName = "Вт", IsSelected = false },
                new DayOption { DayNumber = 3, DayName = "Среда", ShortName = "Ср", IsSelected = false },
                new DayOption { DayNumber = 4, DayName = "Четверг", ShortName = "Чт", IsSelected = false },
                new DayOption { DayNumber = 5, DayName = "Пятница", ShortName = "Пт", IsSelected = false },
                new DayOption { DayNumber = 6, DayName = "Суббота", ShortName = "Сб", IsSelected = false },
                new DayOption { DayNumber = 7, DayName = "Воскресенье", ShortName = "Вс", IsSelected = false }
            };
        }
    }



    public class AppointmentValidationResult
    {
        public bool IsValid { get; set; }
        public string Message { get; set; }
        public List<AvailableTimeSlot> AvailableSlots { get; set; } = new();
    }
    public class AvailableTimeSlot
    {
        public DateTime StartTime { get; set; }
        public DateTime EndTime { get; set; }
        public string DisplayTime { get; set; }
        public bool IsAvailable { get; set; }
    }
}