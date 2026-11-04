using System.Text;
using System.Text.Json;
using Clinic.Models;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Caching.Memory;

namespace Clinic.Services
{
    public class ConnectionManager
    {
        private readonly IConfiguration _configuration;
        private readonly IHttpContextAccessor _httpContextAccessor;
        private readonly IDataProtector _dataProtector;

        private const string ConnectionCookieName = ".Clinic.Connection";
        private const string CacheKeyPrefix = "ConnectionString_";

        public ConnectionManager(
            IConfiguration configuration,
            IHttpContextAccessor httpContextAccessor,
            IDataProtectionProvider dataProtectionProvider)
        {
            _configuration = configuration;
            _httpContextAccessor = httpContextAccessor;
            _dataProtector = dataProtectionProvider.CreateProtector("ConnectionManager.Cookie");
        }

        public string GetCurrentConnectionString()
        {
            var context = _httpContextAccessor.HttpContext;
            if (context == null || context.User.Identity?.IsAuthenticated == false )
            {
                return GetGuestConnectionString();
            }

            var userId = context.User.FindFirst("UserId")?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return GetGuestConnectionString();
            }


            // Если нет в кэше, попробуем получить из cookie
            var connectionInfo = GetConnectionInfoFromCookie();
            if (connectionInfo == null)
            {
                return GetGuestConnectionString();
            }

            var connectionString = BuildConnectionString(connectionInfo.DbUser, connectionInfo.DbPassword);
            return connectionString;
        }

        public void SetUserConnection(string dbUser, string dbPassword)
        {
            var context = _httpContextAccessor.HttpContext;
            if (context == null) return;

            var connectionInfo = new ConnectionCookieInfo
            {
                DbUser = dbUser,
                DbPassword = dbPassword,
                Expires = DateTime.UtcNow.AddDays(30) // Cookie будет храниться 30 дней
            };

            // Сохраняем в cookie
            SaveConnectionInfoToCookie(connectionInfo);
        }

        public void ClearUserConnection()
        {
            var context = _httpContextAccessor.HttpContext;
            if (context == null) return;

            ClearConnectionCookie();

        }

        public string GetGuestConnectionString()
        {
            return _configuration.GetConnectionString("DefaultConnection");
        }

        private string BuildConnectionString(string userId, string password)
        {
            var baseConnection = GetGuestConnectionString();
            return baseConnection
                .Replace("User Id=APP_GUEST_USER", $"User Id={userId}")
                .Replace("Password=GuestPass123!", $"Password={password}");
        }

        public string GetConnectionForRole(string roleName)
        {
            return roleName switch
            {
                "DOCTOR" => BuildConnectionString("app_doctor_user", "DoctorPass123!"),
                "HEAD_DOCTOR" => BuildConnectionString("app_head_user", "HeadPass123!"),
                "REGISTRAR" => BuildConnectionString("app_registrar_user", "RegistrarPass123!"),
                _ => BuildConnectionString("app_guest_user", "GuestPass123!")
            };
        }

        #region Cookie Methods

        private void SaveConnectionInfoToCookie(ConnectionCookieInfo info)
        {
            var context = _httpContextAccessor.HttpContext;
            if (context == null || context.Response == null) return;

            // Сериализуем данные
            var json = JsonSerializer.Serialize(info);

            // Шифруем данные
            var encryptedData = _dataProtector.Protect(Encoding.UTF8.GetBytes(json));
            var base64Data = Convert.ToBase64String(encryptedData);

            // Устанавливаем cookie
            context.Response.Cookies.Append(
                ConnectionCookieName,
                base64Data,
                new CookieOptions
                {
                    HttpOnly = true, 
                    Secure = true, 
                    SameSite = SameSiteMode.Strict, 
                    Expires = info.Expires,
                    IsEssential = true
                });
        }

        private ConnectionCookieInfo? GetConnectionInfoFromCookie()
        {
            var context = _httpContextAccessor.HttpContext;
            if (context == null || context.Request == null) return null;

            var cookieValue = context.Request.Cookies[ConnectionCookieName];
            if (string.IsNullOrEmpty(cookieValue)) return null;

            try
            {
                // Декодируем из base64
                var encryptedData = Convert.FromBase64String(cookieValue);

                // Расшифровываем
                var decryptedData = _dataProtector.Unprotect(encryptedData);
                var json = Encoding.UTF8.GetString(decryptedData);

                // Десериализуем
                var info = JsonSerializer.Deserialize<ConnectionCookieInfo>(json);

                // Проверяем срок действия
                if (info?.Expires < DateTime.UtcNow)
                {
                    ClearConnectionCookie();
                    return null;
                }

                return info;
            }
            catch
            {
                // Если cookie повреждена, удаляем её
                ClearConnectionCookie();
                return null;
            }
        }

        private void ClearConnectionCookie()
        {
            var context = _httpContextAccessor.HttpContext;
            if (context == null || context.Response == null) return;

            context.Response.Cookies.Delete(
                ConnectionCookieName,
                new CookieOptions
                {
                    HttpOnly = true,
                    Secure = true,
                    SameSite = SameSiteMode.Strict
                });
        }

        #endregion
    }

    public class ConnectionCookieInfo
    {
        public string DbUser { get; set; } = string.Empty;
        public string DbPassword { get; set; } = string.Empty;
        public DateTime Expires { get; set; }
    }
}