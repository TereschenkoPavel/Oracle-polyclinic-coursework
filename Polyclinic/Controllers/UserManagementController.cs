// UserManagementController.cs
using Clinic.Models;
using Clinic.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Clinic.Controllers
{
    [Authorize(Roles = "HEAD_DOCTOR")]
    public class UserManagementController : Controller
    {
        private readonly DatabaseService _databaseService;
        private readonly AuthService _authService;
        private readonly ILogger<UserManagementController> _logger;

        public UserManagementController(
            DatabaseService databaseService,
            AuthService authService,
            ILogger<UserManagementController> logger)
        {
            _databaseService = databaseService;
            _authService = authService;
            _logger = logger;
        }

        // GET: UserManagement/Index (только регистраторы)
        public async Task<IActionResult> Index()
        {
            try
            {
                var registrars = await _databaseService.GetUsersByRoleAsync("REGISTRAR");
                return View(registrars);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting registrars");
                TempData["ErrorMessage"] = $"Ошибка при загрузке списка регистраторов: {ex.Message}";
                return View(new List<RegisterData>());
            }
        }

        // GET: UserManagement/Create (только для регистраторов)
        public IActionResult Create()
        {
            var model = new RegisterModel
            {
                Role = "REGISTRAR" // Фиксируем роль регистратора
            };
            return View(model);
        }

        // POST: UserManagement/Create (создание регистратора)
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Create(UserModel model)
        {
            if (!ModelState.IsValid)
            {
                return View(model);
            }

            try
            {
                // Используем AuthService для регистрации пользователя
                var registerModel = new UserModel
                {
                    Username = model.Username,
                    Password = model.Password,
                    ConfirmPassword = model.ConfirmPassword,
                    Role = "REGISTRAR" // Фиксируем роль регистратора
                };

                var result = await _authService.RegisterUserAsync(registerModel);
                
                if (result)
                {
                    TempData["SuccessMessage"] = "Регистратор успешно добавлен";
                    return RedirectToAction(nameof(Index));
                }
                else
                {
                    ModelState.AddModelError(string.Empty, "Ошибка при создании регистратора");
                    return View(model);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating registrar");
                ModelState.AddModelError(string.Empty, $"Ошибка при создании регистратора: {ex.Message}");
                return View(model);
            }
        }

        // GET: UserManagement/EditPassword/5 (изменение пароля)
        public async Task<IActionResult> EditPassword(int id)
        {
            try
            {
                var registrars = await _databaseService.GetUsersByRoleAsync("REGISTRAR");
                var registrar = registrars.FirstOrDefault(r => r.UserId == id);
                
                if (registrar == null)
                {
                    return NotFound();
                }

                var model = new UserModel
                {
                    UserId = registrar.UserId,
                    Username = registrar.Username,
                    Role = registrar.RoleName
                };

                return View(model);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting registrar for password edit");
                TempData["ErrorMessage"] = $"Ошибка при загрузке регистратора: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }

        // POST: UserManagement/EditPassword/5
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> EditPassword(int id, UserModel model)
        {
            if (id != model.UserId)
            {
                return NotFound();
            }

            if (!ModelState.IsValid)
            {
                return View(model);
            }

            try
            {
                await _databaseService.UpdateUserPasswordAsync(model.UserId, model.Password);
                _logger.LogInformation("Password updated for user ID: {UserId}", model.UserId);
                TempData["SuccessMessage"] = "Пароль успешно обновлен";
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating password");
                ModelState.AddModelError(string.Empty, $"Ошибка при обновлении пароля: {ex.Message}");
                return View(model);
            }
        }

        // GET: UserManagement/Delete/5
        public async Task<IActionResult> Delete(int id)
        {
            try
            {
                var registrars = await _databaseService.GetUsersByRoleAsync("REGISTRAR");
                var registrar = registrars.FirstOrDefault(r => r.UserId == id);
                
                if (registrar == null)
                {
                    return NotFound();
                }

                return View(registrar);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting registrar for delete");
                TempData["ErrorMessage"] = $"Ошибка при загрузке регистратора: {ex.Message}";
                return RedirectToAction(nameof(Index));
            }
        }

        // POST: UserManagement/Delete/5
        [HttpPost, ActionName("Delete")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> DeleteConfirmed(int id)
        {
            try
            {
                await _databaseService.DeleteUserAsync(id);
                _logger.LogInformation("Registrar deleted with ID: {UserId}", id);
                TempData["SuccessMessage"] = "Регистратор успешно удален";
                return RedirectToAction(nameof(Index));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting registrar");
                TempData["ErrorMessage"] = $"Ошибка при удалении регистратора: {ex.Message}";
                return RedirectToAction(nameof(Delete), new { id });
            }
        }
    }
}