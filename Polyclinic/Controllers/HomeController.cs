using Clinic.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Clinic.Controllers
{
    public class HomeController : Controller
    {
        private readonly DatabaseService _databaseService;
        private readonly ILogger<HomeController> _logger;

        public HomeController(DatabaseService databaseService, ILogger<HomeController> logger)
        {
            _databaseService = databaseService;
            _logger = logger;
        }

        [AllowAnonymous]
        public IActionResult Index()
        {
            if (User.Identity.IsAuthenticated)
            {
                return RedirectToAction("Dashboard");
            }
            return View();
        }

        [Authorize]
        public async Task<IActionResult> Dashboard()
        {
            var role = User.FindFirst("Role")?.Value;
            ViewBag.Role = role;
            ViewBag.UserName = User.Identity.Name;

            return role switch
            {
                "HEAD_DOCTOR" => await HeadDoctorDashboard(),
                "DOCTOR" => await DoctorDashboard(),
                "REGISTRAR" => await RegistrarDashboard(),
                _ => View()
            };
        }

        [Authorize(Roles = "HEAD_DOCTOR")]
        public async Task<IActionResult> HeadDoctorDashboard()
        {
            var doctors = await _databaseService.GetDoctorsAsync();
            var patients = await _databaseService.GetPatientsAsync();

            ViewBag.DoctorCount = doctors.Count;
            ViewBag.PatientCount = patients.Count;

            return View("HeadDoctorDashboard");
        }

        [Authorize(Roles = "DOCTOR")]
        public async Task<IActionResult> DoctorDashboard()
        {
            var doctorIdClaim = User.FindFirst("DoctorId")?.Value;
            if (int.TryParse(doctorIdClaim, out int doctorId))
            {
                var appointments = await _databaseService.GetAppointmentsAsync(doctorId);

                var today = DateTime.Today;
                var todayAppointments = appointments
                    .Where(a => a.AppointmentDate.Date == today && a.Status == "SCHEDULED")
                    .ToList();

                var upcomingAppointments = appointments
                    .Where(a => a.AppointmentDate > DateTime.Now && a.Status == "SCHEDULED")
                    .OrderBy(a => a.AppointmentDate)
                    .Take(10)
                    .ToList();

                ViewBag.TodayAppointments = todayAppointments;
                ViewBag.UpcomingAppointments = upcomingAppointments;
            }

            return View("DoctorDashboard");
        }
        [HttpPost]
        [Authorize(Roles = "HEAD_DOCTOR,DOCTOR")]
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

        public async Task<IActionResult> RegistrarDashboard()
        {
            var appointments = await _databaseService.GetAppointmentsAsync();
            var patients = await _databaseService.GetPatientsAsync();

            var today = DateTime.Today;
            var todayAppointments = appointments
                .Where(a => a.AppointmentDate.Date == today)
                .ToList();

            var weekAppointments = appointments
                .Where(a => a.AppointmentDate.Date >= today && a.AppointmentDate.Date <= today.AddDays(7))
                .ToList();

            var upcomingAppointments = appointments
                .Where(a => a.AppointmentDate > DateTime.Now)
                .OrderBy(a => a.AppointmentDate)
                .Take(10)
                .ToList();

            ViewBag.TodayAppointmentsCount = todayAppointments.Count;
            ViewBag.WeekAppointmentsCount = weekAppointments.Count;
            ViewBag.TotalPatients = patients.Count;
            ViewBag.UpcomingAppointments = upcomingAppointments;

            return View("RegistrarDashboard");
        }

        [AllowAnonymous]
        public IActionResult AccessDenied()
        {
            return View();
        }
    }
}