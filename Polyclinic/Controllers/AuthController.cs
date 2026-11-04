using System.Security.Claims;
using Clinic.Models;
using Clinic.Services;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Clinic.Controllers
{
    public class AuthController : Controller
    {
        private readonly AuthService _authService;

        public AuthController(AuthService authService)
        {
            _authService = authService;
        }

        [AllowAnonymous]
        public IActionResult Login(string returnUrl = null)
        {
            ViewData["ReturnUrl"] = returnUrl;
            return View();
        }

        [HttpPost]
        [AllowAnonymous]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Login(LoginModel model, string returnUrl = null)
        {
            if (!ModelState.IsValid)
            {
                return View(model);
            }

            var result = await _authService.AuthenticateAsync(model.Login, model.Password);

            if (result.ReturnCode == 0)
            {
                var claims = new List<Claim>
                {
                    new Claim(ClaimTypes.Name, model.Login),
                    new Claim(ClaimTypes.Role, result.RoleName),
                    new Claim("UserId", result.UserId.ToString()),
                    new Claim("Role", result.RoleName),
                    new Claim("DoctorId", result.DoctorId.ToString())
                };

                var claimsIdentity = new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme);
                var authProperties = new AuthenticationProperties
                {
                    ExpiresUtc = DateTimeOffset.UtcNow.AddMinutes(30)
                };

                await HttpContext.SignInAsync(
                    CookieAuthenticationDefaults.AuthenticationScheme,
                    new ClaimsPrincipal(claimsIdentity),
                    authProperties);

                if (!string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl))
                {
                    return Redirect(returnUrl);
                }

                // Redirect based on role
                return result.RoleName switch
                {
                    "DOCTOR" => RedirectToAction("DoctorDashboard", "Home"),
                    "HEAD_DOCTOR" => RedirectToAction("HeadDoctorDashboard", "Home"),
                    "REGISTRAR" => RedirectToAction("RegistrarDashboard", "Home"),
                    _ => RedirectToAction("Dashboard", "Home")
                };
            }

            ModelState.AddModelError("Ошибка при попытке авторизации:", result.Message);
            return View(model);
        }

        [Authorize(Roles = "HEAD_DOCTOR")]
        public IActionResult Register()
        {
            return View();
        }

        [HttpPost]
        [Authorize(Roles = "HEAD_DOCTOR")]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Register(UserModel model)
        {
            if (!ModelState.IsValid)
            {
                return View(model);
            }

            var success = await _authService.RegisterUserAsync(model);

            if (success)
            {
                // Auto login after registration
                return await Login(new LoginModel
                {
                    Login = model.Username,
                    Password = model.Password,
                });
            }

            ModelState.AddModelError(string.Empty, "Ошибка регистрации");
            return View(model);
        }

        [Authorize]
        [HttpPost]
        [ValidateAntiForgeryToken]
        public async Task<IActionResult> Logout()
        {
            _authService.Logout();
            await HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
            HttpContext.Session.Clear();
            return RedirectToAction("Index", "Home");
        }
        [Authorize]
        [HttpGet]
        public IActionResult LogoutConfirmation()
        {
            return View();
        }
    }
}