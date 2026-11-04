using Clinic.Models;
using Clinic.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;

namespace Clinic.Controllers
{
    [Authorize(Roles = "HEAD_DOCTOR,DOCTOR")]
    public class DoctorScheduleController : Controller
    {
        private readonly DatabaseService _databaseService;
        private readonly ILogger<DoctorScheduleController> _logger;

        public DoctorScheduleController(DatabaseService databaseService, ILogger<DoctorScheduleController> logger)
        {
            _databaseService = databaseService;
            _logger = logger;
        }

        // Главная страница - выбор врача для управления расписанием
        public async Task<IActionResult> Index()
        {
            var viewModel = new DoctorScheduleViewModel
            {
                DoctorInfo = new DoctorInfo(),
                ScheduleInput = new DoctorScheduleInputModel
                {
                    AvailableDays = GetAvailableDays(new List<int>())
                }
            };

            ViewBag.Doctors = await _databaseService.GetDoctorOptionsAsync();
            return View(viewModel);
        }

        // Просмотр и управление расписанием конкретного врача
        [HttpGet]
        public async Task<IActionResult> Manage(int doctorId)
        {
            try
            {
                // Проверка прав доступа
                if (User.IsInRole("DOCTOR"))
                {
                    var currentDoctorId = int.Parse(User.FindFirstValue("DoctorId") ?? "0");
                    if (doctorId != currentDoctorId)
                    {
                        return Forbid();
                    }
                }

                // Получаем информацию о враче
                var doctor = await GetDoctorInfoAsync(doctorId);
                if (doctor == null)
                {
                    TempData["ErrorMessage"] = "Врач не найден";
                    return RedirectToAction("Index");
                }

                // Получаем существующее расписание
                var existingSchedules = await _databaseService.GetDoctorSchedulesAsync(doctorId);

                // Создаем модель представления
                var viewModel = new DoctorScheduleViewModel
                {
                    DoctorInfo = doctor,
                    ExistingSchedules = existingSchedules.Select(s => new DoctorScheduleDisplayModel
                    {
                        ScheduleId = s.ScheduleId,
                        DayOfWeek = s.SelectedDays.First(),
                        DayName = GetDayOfWeekName(s.SelectedDays.First()),
                        StartTime = s.StartTime,
                        EndTime = s.EndTime,
                        TimeRange = $"{s.StartTime:hh\\:mm} - {s.EndTime:hh\\:mm}",
                        Duration = GetDurationString(s.StartTime, s.EndTime)
                    }).ToList(),
                    ShowDeleteAllButton = existingSchedules.Any(),
                    ScheduleInput = await GetScheduleInputModelAsync(doctorId, existingSchedules)
                };

                return View(viewModel);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error loading doctor schedule");
                TempData["ErrorMessage"] = "Ошибка при загрузке расписания";
                return RedirectToAction("Index");
            }
        }

        // Сохранение расписания (POST)
        [HttpPost]
        [Authorize(Roles = "HEAD_DOCTOR")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Save(DoctorScheduleViewModel viewModel)
        {
            if (!ModelState.IsValid)
            {
                // Перезагружаем данные для повторного отображения формы
                return await ReloadViewModelAndReturnView(viewModel.ScheduleInput.DoctorId);
            }

            if (!viewModel.ScheduleInput.SelectedDays.Any())
            {
                ModelState.AddModelError("ScheduleInput.SelectedDays", "Выберите хотя бы один день недели");
                return await ReloadViewModelAndReturnView(viewModel.ScheduleInput.DoctorId);
            }

            try
            {
                // Создаем модель для сохранения
                var scheduleModel = new DoctorScheduleModel
                {
                    DoctorId = viewModel.ScheduleInput.DoctorId,
                    SelectedDays = viewModel.ScheduleInput.SelectedDays,
                    StartTime = viewModel.ScheduleInput.StartTime,
                    EndTime = viewModel.ScheduleInput.EndTime
                };

                // Сохраняем расписание
                var scheduleIds = await _databaseService.SaveDoctorScheduleAsync(scheduleModel);
                _logger.LogInformation("Schedule saved with IDs: {ScheduleIds}", string.Join(", ", scheduleIds));

                TempData["SuccessMessage"] = $"Расписание успешно сохранено для {viewModel.ScheduleInput.SelectedDays.Count} дней";
                return RedirectToAction("Manage", new { doctorId = viewModel.ScheduleInput.DoctorId });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error saving schedule");
                TempData["ErrorMessage"] = $"Ошибка при сохранении расписания: {ex.Message}";
                return RedirectToAction("Manage", new { doctorId = viewModel.ScheduleInput.DoctorId });
            }
        }

        // Удаление всего расписания
        [HttpPost]
        [Authorize(Roles = "HEAD_DOCTOR")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteAll(int doctorId)
        {
            try
            {
                await _databaseService.DeleteAllDoctorScheduleAsync(doctorId);
                _logger.LogInformation("All schedules deleted for doctor ID: {DoctorId}", doctorId);

                TempData["SuccessMessage"] = "Все расписание врача успешно удалено";
                return RedirectToAction("Manage", new { doctorId });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting all schedules");
                TempData["ErrorMessage"] = $"Ошибка при удалении расписания: {ex.Message}";
                return RedirectToAction("Manage", new { doctorId });
            }
        }

        #region Вспомогательные методы

        private async Task<DoctorInfo> GetDoctorInfoAsync(int doctorId)
        {
            var doctors = await _databaseService.GetDoctorsAsync();
            var doctor = doctors.FirstOrDefault(d => d.DoctorId == doctorId);

            if (doctor == null) return null;

            return new DoctorInfo
            {
                DoctorId = doctor.DoctorId,
                FullName = $"{doctor.LastName} {doctor.FirstName} {doctor.MiddleName}".Trim(),
                Specialty = doctor.SpecialtyName,
                OfficeNumber = doctor.OfficeNumber,
                Phone = doctor.Phone
            };
        }

        private async Task<DoctorScheduleInputModel> GetScheduleInputModelAsync(
            int doctorId,
            List<DoctorScheduleModel> existingSchedules)
        {
            var inputModel = new DoctorScheduleInputModel
            {
                DoctorId = doctorId,
                AvailableDays = GetAvailableDays(new List<int>())
            };

            // Если есть существующее расписание, заполняем выбранные дни
            if (existingSchedules.Any())
            {
                inputModel.SelectedDays = existingSchedules
                    .Select(s => s.SelectedDays.First())
                    .Distinct()
                    .ToList();

                // Обновляем флаги выбранных дней
                foreach (var day in inputModel.AvailableDays)
                {
                    day.IsSelected = inputModel.SelectedDays.Contains(day.DayNumber);
                }
            }

            return inputModel;
        }

        private async Task<IActionResult> ReloadViewModelAndReturnView(int doctorId)
        {
            try
            {
                var doctor = await GetDoctorInfoAsync(doctorId);
                if (doctor == null)
                {
                    TempData["ErrorMessage"] = "Врач не найден";
                    return RedirectToAction("Index");
                }

                var existingSchedules = await _databaseService.GetDoctorSchedulesAsync(doctorId);

                var viewModel = new DoctorScheduleViewModel
                {
                    DoctorInfo = doctor,
                    ExistingSchedules = existingSchedules.Select(s => new DoctorScheduleDisplayModel
                    {
                        ScheduleId = s.ScheduleId,
                        DayOfWeek = s.SelectedDays.First(),
                        DayName = GetDayOfWeekName(s.SelectedDays.First()),
                        StartTime = s.StartTime,
                        EndTime = s.EndTime,
                        TimeRange = $"{s.StartTime:hh\\:mm} - {s.EndTime:hh\\:mm}",
                        Duration = GetDurationString(s.StartTime, s.EndTime)
                    }).ToList(),
                    ShowDeleteAllButton = existingSchedules.Any()
                };

                return View("Manage", viewModel);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error reloading view model");
                TempData["ErrorMessage"] = "Ошибка при загрузке данных";
                return RedirectToAction("Index");
            }
        }

        private List<DayOption> GetAvailableDays(List<int> selectedDays)
        {
            return new List<DayOption>
            {
                new DayOption { DayNumber = 1, DayName = "Понедельник", ShortName = "Пн", IsSelected = selectedDays.Contains(1) },
                new DayOption { DayNumber = 2, DayName = "Вторник", ShortName = "Вт", IsSelected = selectedDays.Contains(2) },
                new DayOption { DayNumber = 3, DayName = "Среда", ShortName = "Ср", IsSelected = selectedDays.Contains(3) },
                new DayOption { DayNumber = 4, DayName = "Четверг", ShortName = "Чт", IsSelected = selectedDays.Contains(4) },
                new DayOption { DayNumber = 5, DayName = "Пятница", ShortName = "Пт", IsSelected = selectedDays.Contains(5) },
                new DayOption { DayNumber = 6, DayName = "Суббота", ShortName = "Сб", IsSelected = selectedDays.Contains(6) },
                new DayOption { DayNumber = 7, DayName = "Воскресенье", ShortName = "Вс", IsSelected = selectedDays.Contains(7) }
            };
        }

        private string GetDayOfWeekName(int dayOfWeek)
        {
            return dayOfWeek switch
            {
                1 => "Понедельник",
                2 => "Вторник",
                3 => "Среда",
                4 => "Четверг",
                5 => "Пятница",
                6 => "Суббота",
                7 => "Воскресенье",
                _ => "Неизвестно"
            };
        }

        private string GetDurationString(TimeSpan start, TimeSpan end)
        {
            var duration = end - start;
            var hours = (int)duration.TotalHours;
            var minutes = duration.Minutes;

            return minutes > 0 ? $"{hours}ч {minutes}м" : $"{hours}ч";
        }

        #endregion
    }
}