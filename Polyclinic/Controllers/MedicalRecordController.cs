using Clinic.Models;
using Clinic.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Clinic.Controllers
{
    [Authorize(Roles = "DOCTOR,HEAD_DOCTOR")]
    public class MedicalRecordController : Controller
    {
        private readonly DatabaseService _databaseService;
        private readonly ILogger<MedicalRecordController> _logger;

        public MedicalRecordController(DatabaseService databaseService, ILogger<MedicalRecordController> logger)
        {
            _databaseService = databaseService;
            _logger = logger;
        }

        public async Task<IActionResult> Index()
        {
            List<MedicalRecordModel> records;

            if (User.IsInRole("HEAD_DOCTOR"))
            {
                // Заведующий видит все записи
                records = await _databaseService.GetAllMedicalRecordsAsync();
            }
            else if (User.IsInRole("DOCTOR"))
            {
                // Врач видит только свои записи
                var doctorIdClaim = User.FindFirst("DoctorId")?.Value;
                if (int.TryParse(doctorIdClaim, out int doctorId))
                {
                    records = await _databaseService.GetMedicalRecordsAsync(doctorId);
                }
                else
                {
                    records = new List<MedicalRecordModel>();
                }
            }
            else
            {
                records = new List<MedicalRecordModel>();
            }

            return View(records);
        }

        public async Task<IActionResult> Details(int id)
        {
            try
            {
                var record = await _databaseService.GetMedicalRecordByIdAsync(id);
                if (record == null)
                {
                    return NotFound();
                }
                return View(record);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting medical record details");
                TempData["ErrorMessage"] = $"Ошибка при загрузке медицинской записи: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }

        public async Task<IActionResult> Create()
        {
            var model = new MedicalRecordModel
            {
                Patients = await _databaseService.GetPatientOptionsAsync(),
                Doctors = await _databaseService.GetDoctorOptionsAsync()
            };
            return View(model);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(MedicalRecordModel model)
        {
            if (!ModelState.IsValid)
            {
                model.Patients = await _databaseService.GetPatientOptionsAsync();
                model.Doctors = await _databaseService.GetDoctorOptionsAsync();
                return View(model);
            }

            try
            {
                var recordId = await _databaseService.AddMedicalRecordAsync(model);
                _logger.LogInformation("Medical record created with ID: {RecordId}", recordId);
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                ModelState.AddModelError(string.Empty, $"Ошибка при создании медицинской записи: {ex.Message}");
                model.Patients = await _databaseService.GetPatientOptionsAsync();
                model.Doctors = await _databaseService.GetDoctorOptionsAsync();
                return View(model);
            }
        }

        [Authorize(Roles = "HEAD_DOCTOR,DOCTOR")]
        public async Task<IActionResult> Edit(int id)
        {
            try
            {
                var record = await _databaseService.GetMedicalRecordByIdAsync(id);
                if (record == null)
                {
                    return NotFound();
                }

                // Заполняем списки для выпадающих списков
                record.Patients = await _databaseService.GetPatientOptionsAsync();
                record.Doctors = await _databaseService.GetDoctorOptionsAsync();

                return View(record);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting medical record for edit");
                TempData["ErrorMessage"] = $"Ошибка при загрузке медицинской записи: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        [Authorize(Roles = "HEAD_DOCTOR,DOCTOR")]
        public async Task<IActionResult> Edit(int id, MedicalRecordModel model)
        {
            if (id != model.RecordId)
            {
                return NotFound();
            }

            if (!ModelState.IsValid)
            {
                model.Patients = await _databaseService.GetPatientOptionsAsync();
                model.Doctors = await _databaseService.GetDoctorOptionsAsync();
                return View(model);
            }

            try
            {
                await _databaseService.UpdateMedicalRecordAsync(model);
                _logger.LogInformation("Medical record updated with ID: {RecordId}", model.RecordId);
                TempData["SuccessMessage"] = "Медицинская запись успешно обновлена";
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                ModelState.AddModelError(string.Empty, $"Ошибка при обновлении медицинской записи: {ex.Message}");
                model.Patients = await _databaseService.GetPatientOptionsAsync();
                model.Doctors = await _databaseService.GetDoctorOptionsAsync();
                return View(model);
            }
        }

        [Authorize(Roles = "HEAD_DOCTOR,DOCTOR")]
        public async Task<IActionResult> Delete(int id)
        {
            try
            {
                var record = await _databaseService.GetMedicalRecordByIdAsync(id);
                if (record == null)
                {
                    return NotFound();
                }
                return View(record);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting medical record for delete");
                TempData["ErrorMessage"] = $"Ошибка при загрузке медицинской записи: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }

        [HttpPost, ActionName("Delete")]
        [ValidateAntiForgeryToken]
        [Authorize(Roles = "HEAD_DOCTOR,DOCTOR")]
        public async Task<IActionResult> DeleteConfirmed(int id)
        {
            try
            {
                await _databaseService.DeleteMedicalRecordAsync(id);
                _logger.LogInformation("Medical record deleted with ID: {RecordId}", id);
                TempData["SuccessMessage"] = "Медицинская запись успешно удалена";
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting medical record");
                TempData["ErrorMessage"] = $"Ошибка при удалении медицинской записи: {ex.Message}";
                return RedirectToAction(nameof(Delete), new { id });
            }
        }
    }
}