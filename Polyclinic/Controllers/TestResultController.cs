using Clinic.Models;
using Clinic.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Clinic.Controllers
{
    [Authorize(Roles = "DOCTOR,HEAD_DOCTOR")]
    public class TestResultController : Controller
    {
        private readonly DatabaseService _databaseService;
        private readonly ILogger<TestResultController> _logger;

        public TestResultController(DatabaseService databaseService, ILogger<TestResultController> logger)
        {
            _databaseService = databaseService;
            _logger = logger;
        }

        public async Task<IActionResult> Index(string? searchTerm)
        {
            var results = await _databaseService.GetTestResultsAsync();
            if(searchTerm != null)
            {

            results = results.Where(
                res => res.PatientFullName.ToLower()
                .Contains(searchTerm.ToLower())
                )
                .ToList();
                ViewBag.SearchTerm = searchTerm;
            }
            return View(results);
        }
        public async Task<IActionResult> Create()
        {
            var model = new TestResultModel
            {
                ResultDate = DateTime.Now,
                Patients = await _databaseService.GetPatientOptionsAsync() 
            };

            return View(model);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(TestResultModel model)
        {
            if (!ModelState.IsValid)
            {
                model.Patients = await _databaseService.GetPatientOptionsAsync(); 
                return View(model);
            }

            try
            {
                var resultId = await _databaseService.AddTestResultAsync(model);
                _logger.LogInformation("Test result created with ID: {ResultId}", resultId);
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                ModelState.AddModelError(string.Empty, $"Ошибка при создании результата анализа: {ex.Message}");
                model.Patients = await _databaseService.GetPatientOptionsAsync(); 
                return View(model);
            }
        }
        public async Task<IActionResult> Edit(int id)
        {
            try
            {
                var result = await _databaseService.GetTestResultByIdAsync(id);
                if (result == null)
                {
                    return NotFound();
                }
                return View(result);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting test result for edit");
                TempData["ErrorMessage"] = $"Ошибка при загрузке результата анализа: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }
        [HttpPost]
        [ValidateAntiForgeryToken]
        [Authorize(Roles = "HEAD_DOCTOR")]
        public async Task<IActionResult> Edit(int id, TestResultModel model)
        {
            if (id != model.ResultId)
            {
                return NotFound();
            }

            if (!ModelState.IsValid)
            {
                return View(model);
            }

            try
            {
                await _databaseService.UpdateTestResultAsync(model);
                _logger.LogInformation("Test result updated with ID: {ResultId}", model.ResultId);
                TempData["SuccessMessage"] = "Результат анализа успешно обновлен";
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                ModelState.AddModelError(string.Empty, $"Ошибка при обновлении результата анализа: {ex.Message}");
                return View(model);
            }
        }
        [Authorize(Roles = "HEAD_DOCTOR")]
        public async Task<IActionResult> Delete(int id)
        {
            try
            {
                var result = await _databaseService.GetTestResultByIdAsync(id);
                if (result == null)
                {
                    return NotFound();
                }
                return View(result);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting test result for delete");
                TempData["ErrorMessage"] = $"Ошибка при загрузке результата анализа: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }
        [HttpPost, ActionName("Delete")]
        [ValidateAntiForgeryToken]
        [Authorize(Roles = "HEAD_DOCTOR")]
        public async Task<IActionResult> DeleteConfirmed(int id)
        {
            try
            {
                await _databaseService.DeleteTestResultAsync(id);
                _logger.LogInformation("Test result deleted with ID: {ResultId}", id);
                TempData["SuccessMessage"] = "Результат анализа успешно удален";
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting test result");
                TempData["ErrorMessage"] = $"Ошибка при удалении результата анализа: {ex.Message}";
                return RedirectToAction(nameof(Delete), new { id });
            }
        }
        [HttpGet]
        public async Task<IActionResult> GetPatientInfo(int id)
        {
            try
            {
                var patient = await _databaseService.GetPatientByIdAsync(id);
                if (patient == null)
                {
                    return Json(new { success = false, message = "Пациент не найден" });
                }

                return Json(new
                {
                    success = true,
                    fullName = $"{patient.LastName} {patient.FirstName} {patient.MiddleName}"
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting patient info");
                return Json(new { success = false, message = "Ошибка сервера" });
            }
        }
    }
}