using Clinic.Models;
using Clinic.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Clinic.Controllers
{
    [Authorize(Roles = "REGISTRAR,HEAD_DOCTOR")]
    public class AppointmentController : Controller
    {
        private readonly DatabaseService _databaseService;
        private readonly ILogger<AppointmentController> _logger;

        public AppointmentController(DatabaseService databaseService, ILogger<AppointmentController> logger)
        {
            _databaseService = databaseService;
            _logger = logger;
        }

        public async Task<IActionResult> Index(int? doctorId = null, string searchDate = null)
        {
            try
            {
                DateTime searchDateTime;
                if (string.IsNullOrEmpty(searchDate))
                {
                    searchDateTime = DateTime.Today;
                }
                else
                {
                    searchDateTime = DateTime.Parse(searchDate);
                }

                ViewBag.SearchDate = searchDateTime.ToString("yyyy-MM-dd");
                ViewBag.DoctorId = doctorId;

                var appointments = await _databaseService.GetAppointmentsAsync(doctorId);
                appointments = appointments.Where(a => a.AppointmentDate.Date == searchDateTime.Date).ToList();

                var model = new AppointmentModel
                {
                    Doctors = await _databaseService.GetDoctorOptionsAsync()
                };

                ViewBag.Appointments = appointments;
                return View(model);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error loading appointments");
                return View(new AppointmentModel());
            }
        }

        public async Task<IActionResult> Create(int? patientId = null)
        {
            var model = new AppointmentModel
            {
                Patients = await _databaseService.GetPatientOptionsAsync(),
                Doctors = await _databaseService.GetDoctorOptionsAsync(),
                AppointmentDate = DateTime.Now.Date.AddHours(9) // 9:00 по умолчанию
            };

            if (patientId.HasValue)
            {
                model.PatientId = patientId.Value;
            }

            return View(model);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(AppointmentModel model)
        {
            if (!ModelState.IsValid)
            {
                model.Patients = await _databaseService.GetPatientOptionsAsync();
                model.Doctors = await _databaseService.GetDoctorOptionsAsync();
                return View(model);
            }

            try
            {
                // Получаем отдельно дату и время из формы
                var appointmentDate = Request.Form["appointmentDate"];
                var appointmentTime = Request.Form["appointmentTime"];

                if (!string.IsNullOrEmpty(appointmentDate) && !string.IsNullOrEmpty(appointmentTime))
                {
                    // Объединяем дату и время
                    var date = DateTime.Parse(appointmentDate[1]);
                    model.AppointmentDate = date;
                }

                // Валидация времени
                var validationResult = await _databaseService.ValidateAppointmentTime(
                    model.DoctorId, model.AppointmentDate);

                if (!validationResult.IsValid)
                {
                    ModelState.AddModelError("AppointmentDate", validationResult.Message);
                    model.Patients = await _databaseService.GetPatientOptionsAsync();
                    model.Doctors = await _databaseService.GetDoctorOptionsAsync();
                    return View(model);
                }

                var appointmentId = await _databaseService.AddAppointmentAsync(model);
                _logger.LogInformation("Appointment created with ID: {AppointmentId}", appointmentId);

                TempData["SuccessMessage"] = "Запись на прием успешно создана";
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                ModelState.AddModelError(string.Empty, $"Ошибка при создании записи: {ex.Message}");
                model.Patients = await _databaseService.GetPatientOptionsAsync();
                model.Doctors = await _databaseService.GetDoctorOptionsAsync();
                return View(model);
            }
        }


        public async Task<IActionResult> Delete(int id)
        {
            try
            {
                var appointment = await _databaseService.GetAppointmentByIdAsync(id);
                if (appointment == null)
                {
                    return NotFound();
                }

                return View(appointment);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting appointment for delete");
                TempData["ErrorMessage"] = $"Ошибка при загрузке записи: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }

        [HttpPost, ActionName("Delete")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteConfirmed(int id)
        {
            try
            {
                var success = await _databaseService.CancelAppointmentAsync(id);
                if (success)
                {
                    _logger.LogInformation("Appointment cancelled with ID: {AppointmentId}", id);
                    TempData["SuccessMessage"] = "Запись успешно отменена";
                    return RedirectToAction(nameof(Index));
                }
                else
                {
                    TempData["ErrorMessage"] = "Ошибка при отмене записи";
                    return RedirectToAction(nameof(Delete), new { id });
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting appointment");
                TempData["ErrorMessage"] = $"Ошибка при отмене записи: {ex.Message}";
                return RedirectToAction(nameof(Delete), new { id });
            }
        }

        [HttpGet]
        public async Task<IActionResult> GetDoctorSchedule(int doctorId, DateTime date)
        {
            try
            {
                var slots = await _databaseService.GetAppointmentSlotsAsync(doctorId, date);
                return Json(new { success = true, slots });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting doctor schedule");
                return Json(new { success = false, message = ex.Message });
            }
        }

        [HttpGet]
        public async Task<IActionResult> GetAvailableSlots(int doctorId, DateTime date)
        {
            try
            {
                var slots = await _databaseService.GetAvailableTimeSlots(doctorId, date);
                return Json(new { success = true, slots });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting available slots");
                return Json(new { success = false, message = ex.Message });
            }
        }

        [HttpGet]
        public async Task<IActionResult> Details(int id)
        {
            try
            {
                var appointment = await _databaseService.GetAppointmentByIdAsync(id);
                if (appointment == null)
                {
                    return NotFound();
                }

                return View(appointment);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting appointment details");
                TempData["ErrorMessage"] = $"Ошибка при загрузке деталей записи: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }

        [HttpPost]
        public async Task<IActionResult> Update
            
            (int id, string status)
        {
            try
            {
                var success = await _databaseService.UpdateAppointmentStatusAsync(id, status);
                if (success)
                {
                    TempData["SuccessMessage"] = $"Статус записи изменен на: {status}";
                }
                else
                {
                    TempData["ErrorMessage"] = "Ошибка при изменении статуса";
                }
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating appointment status");
                TempData["ErrorMessage"] = $"Ошибка при изменении статуса: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }
    }
}