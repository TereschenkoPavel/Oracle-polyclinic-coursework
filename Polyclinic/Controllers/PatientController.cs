using Clinic.Models;
using Clinic.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Clinic.Controllers
{

    public class PatientController : Controller
    {
        private readonly DatabaseService _databaseService;
        private readonly ILogger<PatientController> _logger;

        public PatientController(DatabaseService databaseService, ILogger<PatientController> logger)
        {
            _databaseService = databaseService;
            _logger = logger;
        }

        public async Task<IActionResult> Index(string searchTerm = null)
        {
            var patients = await _databaseService.GetPatientsAsync(searchTerm);
            ViewBag.SearchTerm = searchTerm;
            return View(patients);
        }
        [HttpGet]
        [Authorize(Roles = "HEAD_DOCTOR,REGISTRAR")]
        public IActionResult Create()
        {
            return View();
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        [Authorize(Roles = "HEAD_DOCTOR,REGISTRAR")]
        public async Task<IActionResult> Create(PatientModel model)
        {
            if (!ModelState.IsValid)
            {
                return View(model);
            }

            try
            {
                var patientId = await _databaseService.AddPatientAsync(model);
                _logger.LogInformation("Patient created with ID: {PatientId}", patientId);
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                ModelState.AddModelError(string.Empty, $"Ошибка при создании пациента: {ex.Message}");
                return View(model);
            }
        }

        public async Task<IActionResult> Details(int id)
        {
            try
            {
                var patient = await _databaseService.GetPatientByIdAsync(id);
                if (patient == null)
                {
                    return NotFound();
                }
                var appointments = await _databaseService.GetAppointmentsAsync(patientId: id);
                var medicalRecords = await _databaseService.GetMedicalRecordsAsync(patientId: id);

                ViewBag.UpcomingAppointments = appointments
                    .Where(a => a.AppointmentDate >= DateTime.Now)
                    .OrderBy(a => a.AppointmentDate)
                    .ToList();

                ViewBag.MedicalRecords = medicalRecords
                    .OrderByDescending(mr => mr.RecordDate)
                    .ToList();

                return View(patient);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting patient details");
                return View("Error");
            }
        }
        [Authorize(Roles = "HEAD_DOCTOR,REGISTRAR")]
        public async Task<IActionResult> Edit(int id)
        {
            try
            {
                var patient = await _databaseService.GetPatientByIdAsync(id);
                if (patient == null)
                {
                    return NotFound();
                }
                return View(patient);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting patient for edit");
                TempData["ErrorMessage"] = $"Ошибка при загрузке пациента: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        [Authorize(Roles = "HEAD_DOCTOR,REGISTRAR")]
        public async Task<IActionResult> Edit(PatientModel model)
        {
            if (!ModelState.IsValid)
            {
                return View(model);
            }

            try
            {
                var success = await _databaseService.UpdatePatientAsync(model);
                if (success)
                {
                    _logger.LogInformation("Patient updated with ID: {PatientId}", model.PatientId);
                    return RedirectToAction(nameof(Details), new { id = model.PatientId });
                }
                else
                {
                    ModelState.AddModelError(string.Empty, "Ошибка при обновлении пациента");
                    return View(model);
                }
            }
            catch (Exception ex)
            {
                ModelState.AddModelError(string.Empty, $"Ошибка при обновлении пациента: {ex.Message}");
                return View(model);
            }
        }

        [Authorize(Roles = "HEAD_DOCTOR,REGISTRAR")]
        public async Task<IActionResult> Delete(int id)
        {
            try
            {
                var patient = await _databaseService.GetPatientByIdAsync(id);
                if (patient == null)
                {
                    return NotFound();
                }

                var appointments = await _databaseService.GetAppointmentsAsync(patientId: id);
                var medicalRecords = await _databaseService.GetMedicalRecordsAsync(patientId: id);
                var testResults = await _databaseService.GetTestResultsAsync();

                ViewBag.HasAppointments = appointments?.Any() ?? false;
                ViewBag.HasMedicalRecords = medicalRecords?.Any() ?? false;
                ViewBag.HasTestResults = testResults?.Any(r => r.PatientId == id) ?? false;

                return View(patient);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting patient for delete");
                TempData["ErrorMessage"] = $"Ошибка при загрузке пациента: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }

        [HttpPost, ActionName("Delete")]
        [ValidateAntiForgeryToken]
        [Authorize(Roles = "HEAD_DOCTOR,REGISTRAR")]
        public async Task<IActionResult> DeleteConfirmed(int id)
        {
            try
            {
                var success = await _databaseService.DeletePatientAsync(id);
                if (success)
                {
                    _logger.LogInformation("Patient deleted with ID: {PatientId}", id);
                    TempData["SuccessMessage"] = "Пациент успешно удален";
                    return RedirectToAction(nameof(Index));
                }
                else
                {
                    TempData["ErrorMessage"] = "Ошибка при удалении пациента. Возможно, есть связанные записи.";
                    return RedirectToAction(nameof(Delete), new { id });
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting patient");
                TempData["ErrorMessage"] = $"Ошибка при удалении пациента: {ex.Message}";
                return RedirectToAction(nameof(Delete), new { id });
            }
        }
    }
}