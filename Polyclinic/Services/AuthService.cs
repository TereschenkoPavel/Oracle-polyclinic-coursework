using System.Data;
using System.Text.Json;
using Clinic.Models;
using Clinic.Services;
using Clinic.Models;
using Oracle.ManagedDataAccess.Client;
using Microsoft.Extensions.Logging;

namespace Clinic.Services
{
    public class AuthService
    {
        private readonly ConnectionManager _connectionManager;
        private readonly DatabaseService _databaseService;
        private readonly ILogger<DatabaseService> _logger;
        public AuthService(ConnectionManager connectionManager, DatabaseService databaseService, ILogger<DatabaseService> logger)
        {
            _connectionManager = connectionManager;
            _databaseService = databaseService;
            _logger = logger;
        }

        public async Task<AuthResult> AuthenticateAsync(string login, string password)
        {
            try
            {
                // First, authenticate using guest connection
                var authResult = await AuthenticateWithProcedure(login, password);

                if (authResult.ReturnCode == 0)
                {
                    // Set user-specific connection
                    _connectionManager.SetUserConnection(
                        authResult.DbConnection,
                        authResult.DbConnectionPass
                    );
                }

                return authResult;
            }
            catch (Exception ex)
            {
                return new AuthResult
                {
                    ReturnCode = -1,
                    Message = $"Ошибка аутентификации: {ex.Message}"
                };
            }
        }

        private async Task<AuthResult> AuthenticateWithProcedure(string login, string password)
        {
            using var connection = new OracleConnection(_connectionManager.GetGuestConnectionString());
            try
            {

            await connection.OpenAsync();
            }
            catch(Exception e)
            {
                _logger.LogError(e, e.Message);
            }

            using var command = new OracleCommand("BEGIN auth_pkg.authenticate_user(:input_json, :output_json); END;", connection);

            var inputJson = JsonSerializer.Serialize(new { login, password });

            command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
            command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;
            
            try
            {
            await command.ExecuteNonQueryAsync();
            var outputJson = command.Parameters["output_json"].Value.ToString();
            return JsonSerializer.Deserialize<AuthResult>(outputJson);
            }
            catch(Exception e) 
            {
                _logger.LogError(e, e.Message);
            }
            return new AuthResult { ReturnCode = -1 };

        }

        public async Task<bool> RegisterUserAsync(UserModel model)
        {
            try
            {
                var result = await RegisterWithProcedure(model);
                return result.ReturnCode == 0;
            }
            catch
            {
                return false;
            }
        }
        private async Task<JsonResponse<RegisterData>> RegisterWithProcedure(UserModel model)
        {
            using var connection = new OracleConnection(_connectionManager.GetGuestConnectionString());
            try
            {
            await connection.OpenAsync();
            }
            catch(OracleException e)
            {
                Console.WriteLine(e.Message);
            }
            using var command = new OracleCommand("BEGIN auth_pkg.register_user(:input_json, :output_json); END;", connection);

            var inputJson = JsonSerializer.Serialize(new
            {
                username = model.Username,
                password = model.Password,
                role = model.Role
            });

            command.Parameters.Add("input_json", OracleDbType.Varchar2).Value = inputJson;
            command.Parameters.Add("output_json", OracleDbType.Varchar2, 4000).Direction = ParameterDirection.Output;
            try
            {
                await command.ExecuteNonQueryAsync();
            }
            catch (Exception e)
            {
                Console.WriteLine(e.Message);
            }
            var outputJson = command.Parameters["output_json"].Value.ToString();
            return JsonSerializer.Deserialize<JsonResponse<RegisterData>>(outputJson);
        }

        public void Logout()
        {
            _connectionManager.ClearUserConnection();
        }
    }
}