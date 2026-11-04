using Clinic.Models;
using Clinic.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Clinic.Controllers
{
    [Authorize(Roles = "HEAD_DOCTOR")]
    public class DoctorController : Controller
    {
        private readonly DatabaseService _databaseService;
        private readonly ILogger<DoctorController> _logger;

        public DoctorController(DatabaseService databaseService, ILogger<DoctorController> logger)
        {
            _databaseService = databaseService;
            _logger = logger;
        }

        public async Task<IActionResult> Index()
        {
            var doctors = await _databaseService.GetDoctorsAsync();
            return View(doctors);
        }

        public async Task<IActionResult> Create()
        {
            var model = new DoctorModel
            {
                Specialties = await _databaseService.GetSpecialtiesAsync()
            };
            return View(model);
        }

        [HttpPost]
        public async Task<IActionResult> Create(DoctorModel model)
        {
            if (!ModelState.IsValid)
            {
                model.Specialties = await _databaseService.GetSpecialtiesAsync();
                return View(model);
            }
            else {
                foreach (var error in ModelState.Values.SelectMany(v => v.Errors))
                {
                    _logger.LogWarning("Validation error: {ErrorMessage}", error.ErrorMessage);
                }
            }
            try
            {
                var doctorId = await _databaseService.AddDoctorAsync(model);
                _logger.LogInformation("Doctor created with ID: {DoctorId}", doctorId);
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                ModelState.AddModelError(string.Empty, $"Ошибка при создании врача: {ex.Message}");
                model.Specialties = await _databaseService.GetSpecialtiesAsync();
                return View(model);
            }
        }
        public async Task<IActionResult> Edit(int id)
        {
            var doctor = await _databaseService.GetDoctorForEditAsync(id);
            if (doctor == null)
            {
                return NotFound();
            }

            return View(doctor);
        }

        [HttpPost]
        public async Task<IActionResult> Edit(DoctorModel model)
        {
            if (!ModelState.IsValid)
            {
                model.Specialties = await _databaseService.GetSpecialtiesAsync();
                return View(model);
            }

            try
            {
                // Обновляем основные данные врача
                var success = await _databaseService.UpdateDoctorAsync(new DoctorModel
                {
                    DoctorId = model.DoctorId,
                    LastName = model.LastName,
                    FirstName = model.FirstName,
                    MiddleName = model.MiddleName,
                    SpecialtyId = model.SpecialtyId,
                    OfficeNumber = model.OfficeNumber,
                    Phone = model.Phone,
                    PassportSeriesNumber = model.PassportSeriesNumber
                });

                if (!success)
                {
                    ModelState.AddModelError(string.Empty, "Ошибка при обновлении врача");
                    model.Specialties = await _databaseService.GetSpecialtiesAsync();
                    return View(model);
                }

                if (!string.IsNullOrEmpty(model.Username) || !string.IsNullOrEmpty(model.Password))
                {

                    var credSuccess = await _databaseService.UpdateDoctorCredentialsAsync(
                        model.DoctorId,
                        model.Username,
                        model.Password);

                    if (!credSuccess)
                    {
                        ModelState.AddModelError(string.Empty, "Ошибка при обновлении учетных данных. Возможно, логин уже занят.");
                        model.Specialties = await _databaseService.GetSpecialtiesAsync();
                        return View(model);
                    }
                }

                _logger.LogInformation("Doctor updated with ID: {DoctorId}", model.DoctorId);
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                ModelState.AddModelError(string.Empty, $"Ошибка при обновлении врача: {ex.Message}");
                model.Specialties = await _databaseService.GetSpecialtiesAsync();
                return View(model);
            }
        }

        public async Task<IActionResult> Delete(int id)
        {
            var doctor = await _databaseService.GetDoctorByIdAsync(id);
            if (doctor == null)
            {
                return NotFound();
            }

            return View(doctor);
        }

        [HttpPost, ActionName("Delete")]
        public async Task<IActionResult> DeleteConfirmed(int id)
        {
            try
            {
                var success = await _databaseService.DeleteDoctorAsync(id);
                if (success)
                {
                    _logger.LogInformation("Doctor deleted with ID: {DoctorId}", id);
                    return RedirectToAction(nameof(Index));
                }
                else
                {
                    TempData["ErrorMessage"] = "Ошибка при удалении врача";
                    return RedirectToAction(nameof(Delete), new { id });
                }
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = $"Ошибка при удалении врача: {ex.Message}";
                return RedirectToAction(nameof(Delete), new { id });
            }
        }
    }
}