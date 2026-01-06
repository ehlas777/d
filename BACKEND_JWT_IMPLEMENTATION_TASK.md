# Backend Task: JWT + Refresh Token Implementation

## 📋 Жалпы ақпарат

**Приоритет:** 🔴 Жоғары  
**Бағалау:** 2-3 күн  
**Мақсат:** SESSION_NOT_FOUND қатесін шешу және scalable authentication енгізу

---

## 🎯 Мәселе

Ағымдағы session-based authentication video translation processing кезінде (10+ минут) SESSION_NOT_FOUND қатесін туғызады:

```
PlatformException(SESSION_NOT_FOUND, Session not found., null, null)
```

**Себептер:**
1. Session timeout қысқа (5-10 минут)
2. Long-running operations кезінде session expire болады
3. App inactive болса session жоғалады
4. Session-based auth scalable емес

**Қазіргі нәтиже:**
- ❌ 29 сегменттен 2-4 сегмент SESSION қатесімен fail болады
- ❌ User қайта login жасауы керек
- ❌ Processing үзіліп қалады

---

## ✅ Ұсынылатын шешім

**JWT + Refresh Token** authentication mechanism енгізу:

### Негізгі компоненттер:

1. **Access Token (JWT)** - 15 минут
   - API requests үшін қолданылады
   - Stateless (server memory жоқ)
   - Claims: userId, username, role, т.б.

2. **Refresh Token** - 300 күн
   - Access token жаңарту үшін
   - Database-те сақталады
   - Sliding expiration (activity болса ұзарады)

3. **Token Revocation**
   - Logout кезінде
   - Security events (password change, т.б.)
   - Suspicious activity

---

## 🔧 Техникалық Implementation

### 1. Database Schema

```sql
-- RefreshTokens table
CREATE TABLE RefreshTokens (
    Id INT PRIMARY KEY IDENTITY(1,1),
    UserId INT NOT NULL,
    Token NVARCHAR(256) UNIQUE NOT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    ExpiresAt DATETIME2 NOT NULL,
    IsRevoked BIT NOT NULL DEFAULT 0,
    RevokedAt DATETIME2 NULL,
    RevokedReason NVARCHAR(500) NULL,
    
    CONSTRAINT FK_RefreshTokens_Users FOREIGN KEY (UserId) 
        REFERENCES Users(Id) ON DELETE CASCADE
);

-- Indices for performance
CREATE INDEX IX_RefreshTokens_Token ON RefreshTokens(Token);
CREATE INDEX IX_RefreshTokens_UserId ON RefreshTokens(UserId);
CREATE INDEX IX_RefreshTokens_ExpiresAt ON RefreshTokens(ExpiresAt);
```

### 2. Configuration

#### `appsettings.json`

```json
{
  "Jwt": {
    "Key": "your-secret-key-minimum-32-characters-long-for-security",
    "Issuer": "qaznat-api",
    "Audience": "qaznat-client",
    "AccessTokenExpireMinutes": 15,
    "RefreshTokenExpireDays": 300,
    "RefreshTokenSlidingWindow": true
  }
}
```

> ⚠️ **МАҢЫЗДЫ:** Production-да `Jwt:Key` environment variable-дан оқылуы керек!

#### `Program.cs`

```csharp
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using System.Text;

// JWT Authentication
builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    var key = Encoding.UTF8.GetBytes(builder.Configuration["Jwt:Key"]);
    
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = builder.Configuration["Jwt:Issuer"],
        ValidAudience = builder.Configuration["Jwt:Audience"],
        IssuerSigningKey = new SymmetricSecurityKey(key),
        ClockSkew = TimeSpan.Zero // Дәл expiration
    };
    
    options.Events = new JwtBearerEvents
    {
        OnAuthenticationFailed = context =>
        {
            if (context.Exception.GetType() == typeof(SecurityTokenExpiredException))
            {
                context.Response.Headers.Add("Token-Expired", "true");
            }
            return Task.CompletedTask;
        }
    };
});

// Services
builder.Services.AddScoped<ITokenService, TokenService>();
builder.Services.AddScoped<IRefreshTokenService, RefreshTokenService>();
```

### 3. Models

#### `Models/Auth/TokenResponse.cs`

```csharp
namespace YourNamespace.Models.Auth
{
    public class TokenResponse
    {
        public string AccessToken { get; set; }
        public string RefreshToken { get; set; }
        public int ExpiresIn { get; set; }  // seconds
        public string TokenType { get; set; } = "Bearer";
        public int UserId { get; set; }
        public string Username { get; set; }
    }
}
```

#### `Models/Auth/RefreshTokenRequest.cs`

```csharp
namespace YourNamespace.Models.Auth
{
    public class RefreshTokenRequest
    {
        public string RefreshToken { get; set; }
    }
}
```

#### `Models/Entities/RefreshToken.cs`

```csharp
namespace YourNamespace.Models.Entities
{
    public class RefreshToken
    {
        public int Id { get; set; }
        public int UserId { get; set; }
        public string Token { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime ExpiresAt { get; set; }
        public bool IsRevoked { get; set; }
        public DateTime? RevokedAt { get; set; }
        public string? RevokedReason { get; set; }
        
        // Navigation property
        public User User { get; set; }
    }
}
```

### 4. Services

#### `Services/ITokenService.cs`

```csharp
namespace YourNamespace.Services
{
    public interface ITokenService
    {
        string GenerateAccessToken(User user);
        Task<string> GenerateRefreshToken(int userId);
        Task<RefreshToken?> ValidateRefreshToken(string token);
        Task RevokeRefreshToken(string token, string reason = null);
        Task RevokeAllUserTokens(int userId, string reason = null);
    }
}
```

#### `Services/TokenService.cs`

```csharp
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;

namespace YourNamespace.Services
{
    public class TokenService : ITokenService
    {
        private readonly IConfiguration _configuration;
        private readonly ApplicationDbContext _context;

        public TokenService(IConfiguration configuration, ApplicationDbContext context)
        {
            _configuration = configuration;
            _context = context;
        }

        public string GenerateAccessToken(User user)
        {
            var securityKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(_configuration["Jwt:Key"])
            );
            var credentials = new SigningCredentials(securityKey, SecurityAlgorithms.HmacSha256);

            var claims = new[]
            {
                new Claim(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
                new Claim(JwtRegisteredClaimNames.UniqueName, user.Username),
                new Claim(JwtRegisteredClaimNames.Email, user.Email ?? ""),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
                new Claim(ClaimTypes.Role, user.Role ?? "user"),
                new Claim("userId", user.Id.ToString())
            };

            var expireMinutes = int.Parse(_configuration["Jwt:AccessTokenExpireMinutes"]);
            var token = new JwtSecurityToken(
                issuer: _configuration["Jwt:Issuer"],
                audience: _configuration["Jwt:Audience"],
                claims: claims,
                expires: DateTime.UtcNow.AddMinutes(expireMinutes),
                signingCredentials: credentials
            );

            return new JwtSecurityTokenHandler().WriteToken(token);
        }

        public async Task<string> GenerateRefreshToken(int userId)
        {
            // Generate cryptographically secure random token
            var randomBytes = new byte[64];
            using var rng = RandomNumberGenerator.Create();
            rng.GetBytes(randomBytes);
            var token = Convert.ToBase64String(randomBytes);

            var expireDays = int.Parse(_configuration["Jwt:RefreshTokenExpireDays"]);
            var refreshToken = new RefreshToken
            {
                UserId = userId,
                Token = token,
                CreatedAt = DateTime.UtcNow,
                ExpiresAt = DateTime.UtcNow.AddDays(expireDays),
                IsRevoked = false
            };

            _context.RefreshTokens.Add(refreshToken);
            await _context.SaveChangesAsync();

            return token;
        }

        public async Task<RefreshToken?> ValidateRefreshToken(string token)
        {
            var refreshToken = await _context.RefreshTokens
                .Include(rt => rt.User)
                .FirstOrDefaultAsync(rt => rt.Token == token);

            if (refreshToken == null ||
                refreshToken.IsRevoked ||
                refreshToken.ExpiresAt < DateTime.UtcNow)
            {
                return null;
            }

            // Sliding expiration: Activity болса ұзарту
            var slidingWindow = bool.Parse(_configuration["Jwt:RefreshTokenSlidingWindow"] ?? "true");
            if (slidingWindow)
            {
                var expireDays = int.Parse(_configuration["Jwt:RefreshTokenExpireDays"]);
                refreshToken.ExpiresAt = DateTime.UtcNow.AddDays(expireDays);
                await _context.SaveChangesAsync();
            }

            return refreshToken;
        }

        public async Task RevokeRefreshToken(string token, string reason = null)
        {
            var refreshToken = await _context.RefreshTokens
                .FirstOrDefaultAsync(rt => rt.Token == token);

            if (refreshToken != null && !refreshToken.IsRevoked)
            {
                refreshToken.IsRevoked = true;
                refreshToken.RevokedAt = DateTime.UtcNow;
                refreshToken.RevokedReason = reason;
                await _context.SaveChangesAsync();
            }
        }

        public async Task RevokeAllUserTokens(int userId, string reason = null)
        {
            var userTokens = await _context.RefreshTokens
                .Where(rt => rt.UserId == userId && !rt.IsRevoked)
                .ToListAsync();

            foreach (var token in userTokens)
            {
                token.IsRevoked = true;
                token.RevokedAt = DateTime.UtcNow;
                token.RevokedReason = reason ?? "All tokens revoked";
            }

            await _context.SaveChangesAsync();
        }
    }
}
```

### 5. Controller Updates

#### `Controllers/AuthController.cs`

```csharp
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace YourNamespace.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AuthController : ControllerBase
    {
        private readonly IUserService _userService;
        private readonly ITokenService _tokenService;

        public AuthController(IUserService userService, ITokenService tokenService)
        {
            _userService = userService;
            _tokenService = tokenService;
        }

        [HttpPost("login")]
        public async Task<IActionResult> Login([FromBody] LoginRequest request)
        {
            // Validate credentials
            var user = await _userService.ValidateCredentials(request.Username, request.Password);
            if (user == null)
            {
                return Unauthorized(new { message = "Invalid username or password" });
            }

            // Generate tokens
            var accessToken = _tokenService.GenerateAccessToken(user);
            var refreshToken = await _tokenService.GenerateRefreshToken(user.Id);

            var response = new TokenResponse
            {
                AccessToken = accessToken,
                RefreshToken = refreshToken,
                ExpiresIn = 900, // 15 minutes in seconds
                UserId = user.Id,
                Username = user.Username
            };

            return Ok(response);
        }

        [HttpPost("refresh")]
        public async Task<IActionResult> RefreshToken([FromBody] RefreshTokenRequest request)
        {
            var refreshToken = await _tokenService.ValidateRefreshToken(request.RefreshToken);
            
            if (refreshToken == null)
            {
                return Unauthorized(new { message = "Invalid or expired refresh token" });
            }

            // Generate new access token
            var accessToken = _tokenService.GenerateAccessToken(refreshToken.User);

            var response = new TokenResponse
            {
                AccessToken = accessToken,
                RefreshToken = refreshToken.Token, // Same refresh token (already extended)
                ExpiresIn = 900,
                UserId = refreshToken.UserId,
                Username = refreshToken.User.Username
            };

            return Ok(response);
        }

        [Authorize]
        [HttpPost("logout")]
        public async Task<IActionResult> Logout([FromBody] RefreshTokenRequest request)
        {
            await _tokenService.RevokeRefreshToken(request.RefreshToken, "User logout");
            return Ok(new { message = "Logged out successfully" });
        }

        [Authorize]
        [HttpPost("logout-all")]
        public async Task<IActionResult> LogoutAll()
        {
            var userId = int.Parse(User.FindFirst("userId")?.Value ?? "0");
            await _tokenService.RevokeAllUserTokens(userId, "User logout from all devices");
            return Ok(new { message = "Logged out from all devices" });
        }
    }
}
```

#### Protected Endpoints жаңарту

```csharp
// Translation, TTS, және басқа endpoints-тарда
[Authorize] // ⬅️ Session емес, JWT қолданады
[HttpPost("api/translation/translate-segments")]
public async Task<IActionResult> TranslateSegments([FromBody] TranslateSegmentsRequest request)
{
    // Get user from JWT claims
    var userId = int.Parse(User.FindFirst("userId")?.Value ?? "0");
    
    // Process translation...
    
    return Ok(result);
}
```

### 6. Background Services (Optional but Recommended)

#### Expired tokens cleanup

```csharp
// Services/TokenCleanupService.cs
public class TokenCleanupService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<TokenCleanupService> _logger;

    public TokenCleanupService(IServiceProvider serviceProvider, ILogger<TokenCleanupService> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Token Cleanup Service started");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await CleanupExpiredTokens();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error cleaning up expired tokens");
            }

            // Run every 24 hours
            await Task.Delay(TimeSpan.FromHours(24), stoppingToken);
        }
    }

    private async Task CleanupExpiredTokens()
    {
        using var scope = _serviceProvider.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();

        var expiredTokens = await context.RefreshTokens
            .Where(rt => rt.ExpiresAt < DateTime.UtcNow || rt.IsRevoked)
            .ToListAsync();

        if (expiredTokens.Any())
        {
            context.RefreshTokens.RemoveRange(expiredTokens);
            await context.SaveChangesAsync();
            _logger.LogInformation($"Cleaned up {expiredTokens.Count} expired/revoked tokens");
        }
    }
}

// Program.cs-те тіркеу
builder.Services.AddHostedService<TokenCleanupService>();
```

---

## 📊 API Changes Summary

### Жаңа Endpoints

| Method | Endpoint | Auth | Сипаттама |
|--------|----------|------|-----------|
| POST | `/api/auth/login` | ❌ No | Username/password → JWT tokens |
| POST | `/api/auth/refresh` | ❌ No | Refresh token → New access token |
| POST | `/api/auth/logout` | ✅ Yes | Revoke refresh token |
| POST | `/api/auth/logout-all` | ✅ Yes | Revoke all user tokens |

### Request/Response Formats

#### Login Request
```json
{
  "username": "user@example.com",
  "password": "password123"
}
```

#### Login/Refresh Response
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIs...",
  "refreshToken": "base64-encoded-random-token",
  "expiresIn": 900,
  "tokenType": "Bearer",
  "userId": 123,
  "username": "user@example.com"
}
```

---

## 🧪 Testing Plan

### 1. Unit Tests

```csharp
// TokenServiceTests.cs
[Fact]
public async Task GenerateAccessToken_ShouldContainCorrectClaims()
{
    // Arrange
    var user = new User { Id = 1, Username = "test", Role = "user" };
    
    // Act
    var token = _tokenService.GenerateAccessToken(user);
    var handler = new JwtSecurityTokenHandler();
    var jwtToken = handler.ReadJwtToken(token);
    
    // Assert
    Assert.Equal("1", jwtToken.Claims.First(c => c.Type == "sub").Value);
    Assert.Equal("test", jwtToken.Claims.First(c => c.Type == "unique_name").Value);
}

[Fact]
public async Task ValidateRefreshToken_WhenExpired_ShouldReturnNull()
{
    // Arrange
    var expiredToken = await CreateExpiredRefreshToken();
    
    // Act
    var result = await _tokenService.ValidateRefreshToken(expiredToken.Token);
    
    // Assert
    Assert.Null(result);
}
```

### 2. Integration Tests

```csharp
// AuthIntegrationTests.cs
[Fact]
public async Task Login_WithValidCredentials_ShouldReturnTokens()
{
    // Arrange
    var client = _factory.CreateClient();
    var loginRequest = new { username = "test", password = "password" };
    
    // Act
    var response = await client.PostAsJsonAsync("/api/auth/login", loginRequest);
    
    // Assert
    response.EnsureSuccessStatusCode();
    var tokenResponse = await response.Content.ReadFromJsonAsync<TokenResponse>();
    Assert.NotNull(tokenResponse.AccessToken);
    Assert.NotNull(tokenResponse.RefreshToken);
}

[Fact]
public async Task ProtectedEndpoint_WithValidToken_ShouldReturn200()
{
    // Arrange
    var client = await GetAuthenticatedClient();
    
    // Act
    var response = await client.PostAsJsonAsync("/api/translation/translate-segments", request);
    
    // Assert
    Assert.Equal(HttpStatusCode.OK, response.StatusCode);
}
```

### 3. Manual Testing Scenarios

- [ ] Login жаңа user
- [ ] Access token-мен protected endpoint-қа қолданыс
- [ ] Access token expire болғаннан кейін refresh
- [ ] Logout кезінде token revoke
- [ ] 300 күннен кейін expire тексеру (simulation)
- [ ] Multiple devices-тан login
- [ ] Password change кезінде auto-revoke

---

## 🚀 Deployment Plan

### Phase 1: Preparation (Day 1)
- [ ] Database migration жасау (RefreshTokens table)
- [ ] Configuration қосу (appsettings.json)
- [ ] JWT Key generation (production secret)

### Phase 2: Implementation (Day 2)
- [ ] TokenService енгізу
- [ ] AuthController endpoints жасау
- [ ] Protected endpoints жаңарту
- [ ] Unit tests жазу

### Phase 3: Testing (Day 2-3)
- [ ] Integration tests іске қосу
- [ ] Manual testing
- [ ] Performance testing (token generation speed)

### Phase 4: Migration (Day 3)
- [ ] Session-based endpoints-ты JWT-ға migrate
- [ ] Backward compatibility (temporary)
- [ ] Documentation жаңарту

### Phase 5: Production Deployment
- [ ] Staging deploy және test
- [ ] Production deploy
- [ ] Monitoring орнату
- [ ] Frontend integration тексеру

---

## 📝 Security Checklist

- [ ] JWT Key 32+ characters, environment variable
- [ ] HTTPS only (production)
- [ ] Refresh token secure storage (database)
- [ ] Token revocation mechanism
- [ ] Rate limiting on auth endpoints
- [ ] CORS дұрыс орнатылған
- [ ] Password change → revoke all tokens
- [ ] Suspicious activity detection

---

## 📈 Monitoring & Logging

### Metrics to track:
- Token generation rate
- Refresh token usage rate
- Failed authentication attempts
- Average token lifetime
- Revoked tokens count

### Logging:
```csharp
_logger.LogInformation("User {UserId} logged in", user.Id);
_logger.LogInformation("Access token refreshed for user {UserId}", userId);
_logger.LogWarning("Failed login attempt for username: {Username}", username);
_logger.LogInformation("All tokens revoked for user {UserId}, reason: {Reason}", userId, reason);
```

---

## 🔗 Frontend Integration

> ℹ️ Frontend code **өзгертусіз жұмыс істейді**! 
> Flutter `ApiClient` әлдеқашан JWT-ға дайын:

```dart
// lib/services/api_client.dart
// Бұл код әлдеқашан бар, өзгерту қажет емес!
options.headers['Authorization'] = 'Bearer $token';
```

### Refresh Token Auto-handling

Frontend автоматты 401 қатесін ұстап, refresh жасайды:

```dart
// Бұл логика қазір қосылуы мүмкін
onError: (error, handler) async {
  if (error.response?.statusCode == 401) {
    final refreshed = await _refreshAccessToken();
    if (refreshed) {
      return handler.resolve(await _retry(error.requestOptions));
    }
  }
  return handler.next(error);
}
```

---

## ✅ Acceptance Criteria

Міндетті талаптар:

1. ✅ Login endpoint JWT tokens қайтарады
2. ✅ Access token 15 минут expire
3. ✅ Refresh token 300 күн expire
4. ✅ Refresh token sliding expiration жұмыс істейді
5. ✅ Protected endpoints JWT token қажет етеді
6. ✅ Logout token-ды revoke жасайды
7. ✅ Password change барлық tokens revoke жасайды
8. ✅ SESSION_NOT_FOUND қатесі болмайды
9. ✅ Long-running operations (30+ минут) жұмыс істейді
10. ✅ Unit tests 80%+ coverage

---

## 📞 Support & Questions

Implementation кезінде сұрақтар болса:
- Frontend team: [Сіздің байланысыңыз]
- Documentation: `BACKEND_SESSION_FIX.md`
- Reference: ASP.NET Core JWT docs

---

## 📚 References

- [ASP.NET Core JWT Authentication](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/)
- [JWT.io](https://jwt.io/)
- [Refresh Token Best Practices](https://auth0.com/blog/refresh-tokens-what-are-they-and-when-to-use-them/)

---

## 📱 Frontend Өзгерістері (Flutter)

### ✅ Жақсы Жаңалық

**Flutter app әлдеқашан дайын!** `ApiClient` Bearer token-ды қолдайды, негізгі өзгеріс қажет емес.

### 🔧 Міндетті Өзгерістер

#### 1. Token Storage жаңарту

Login response-тен **екі** token-ды сақтау:

```dart
// lib/providers/auth_provider.dart немесе auth service
Future<void> login(String username, String password) async {
  final response = await apiClient.post('/api/auth/login', data: {
    'Username': username,
    'Password': password,
  });

  // Екеуін де сақта
  await _storage.write(key: 'accessToken', value: response.data['accessToken']);
  await _storage.write(key: 'refreshToken', value: response.data['refreshToken']);
  
  notifyListeners();
}
```

#### 2. Auto Token Refresh (401 Error Handling)

```dart
// lib/services/api_client.dart - Interceptor қос
onError: (error, handler) async {
  if (error.response?.statusCode == 401) {
    final refreshToken = await _storage.read(key: 'refreshToken');
    
    try {
      final refreshDio = Dio(BaseOptions(baseUrl: baseUrl));
      final response = await refreshDio.post('/api/auth/refresh', 
        data: {'refreshToken': refreshToken}
      );
      
      // Жаңа token-ды сақта
      await _storage.write(key: 'accessToken', value: response.data['accessToken']);
      
      // Retry original request
      final opts = error.requestOptions;
      opts.headers['Authorization'] = 'Bearer ${response.data['accessToken']}';
      return handler.resolve(await dio.fetch(opts));
    } catch (e) {
      await _storage.deleteAll();
      return handler.next(error);
    }
  }
  return handler.next(error);
}
```

#### 3. Logout жаңарту

```dart
Future<void> logout() async {
  final refreshToken = await _storage.read(key: 'refreshToken');
  
  try {
    await apiClient.post('/api/auth/logout', data: {'refreshToken': refreshToken});
  } catch (e) {
    // Proceed anyway
  }
  
  await _storage.deleteAll();
  // Navigate to login
}
```

### 🎯 Қысқаша (TL;DR)

1. **Login**: `accessToken` + `refreshToken` сақта
2. **401 Error**: `refreshToken` қолданып жаңа `accessToken` ал
3. **Logout**: `/api/auth/logout` шақыр, storage тазала

**Нәтиже:**
- ❌ SESSION_NOT_FOUND қатесі жоқ
- ✅ Long-running operations жұмыс істейді (30+ минут)
- ✅ User 300 күн ішінде login болмайды

---

**Құжат дайындалды:** 2026-01-06  
**Версия:** 1.1 (Frontend section қосылды)  
**Статус:** 🟢 Approved for Implementation
