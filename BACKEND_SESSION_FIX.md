# Backend SESSION_NOT_FOUND Fix Guide

## Мәселе

Frontend-те video translation processing кезінде (7+ сегмент, ~5-10 минут) SESSION_NOT_FOUND қатесі пайда болады.

```
PlatformException(SESSION_NOT_FOUND, Session not found., null, null)
```

**Себебі:** Backend session timeout қысқа болғандықтан (мысалы, 5-10 минут), ұзақ processing кезінде session expired болады.

---

## Шешім опциялары

### ✅ Опция 1: Session Timeout-ты ұлғайту (Ең қарапайым)

**Өзгертулер:**

#### 1. Session Configuration (ASP.NET Core)

`Program.cs` немесе `Startup.cs`:

```csharp
builder.Services.AddSession(options =>
{
    // Video processing үшін ұзағырақ timeout (60 минут)
    options.IdleTimeout = TimeSpan.FromMinutes(60); // ⬅️ Өзгерту
    options.Cookie.HttpOnly = true;
    options.Cookie.IsEssential = true;
    options.Cookie.SameSite = SameSiteMode.None; // Mobile/Desktop үшін
    options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
});
```

**Артықшылықтары:**
- ✅ Қарапайым
- ✅ Кез келген request-тер session-ды "ұзартады" (sliding expiration)

**Кемшіліктері:**
- ⚠️ Inactive users үшін ұзақ session memory-де қалады

---

### ✅ Опция 2: API Token-based Authentication (Ұсынылады)

Session-нан Token-based auth-қа көшу.

#### 1. JWT Token Configuration

`appsettings.json`:

```json
{
  "Jwt": {
    "Key": "your-secret-key-min-32-chars",
    "Issuer": "qaznat-api",
    "Audience": "qaznat-client",
    "ExpireMinutes": 1440
  }
}
```

#### 2. JWT Middleware Setup

`Program.cs`:

```csharp
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using System.Text;

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
        ClockSkew = TimeSpan.Zero // Exact expiration
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
```

#### 3. Login Endpoint - JWT Generation

`Controllers/AuthController.cs`:

```csharp
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.IdentityModel.Tokens;

[HttpPost("login")]
public async Task<IActionResult> Login([FromBody] LoginRequest request)
{
    // Validate credentials
    var user = await _userService.ValidateUser(request.Username, request.Password);
    if (user == null)
    {
        return Unauthorized(new { message = "Invalid credentials" });
    }

    // Generate JWT token
    var token = GenerateJwtToken(user);
    
    return Ok(new 
    { 
        token = token,
        userId = user.Id,
        username = user.Username,
        expiresIn = 1440 * 60 // seconds
    });
}

private string GenerateJwtToken(User user)
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
        new Claim("role", user.Role ?? "user")
    };

    var token = new JwtSecurityToken(
        issuer: _configuration["Jwt:Issuer"],
        audience: _configuration["Jwt:Audience"],
        claims: claims,
        expires: DateTime.UtcNow.AddMinutes(
            int.Parse(_configuration["Jwt:ExpireMinutes"])
        ),
        signingCredentials: credentials
    );

    return new JwtSecurityTokenHandler().WriteToken(token);
}
```

#### 4. Protected Endpoints

```csharp
[Authorize] // ⬅️ JWT token қажет
[HttpPost("api/translation/translate-segments")]
public async Task<IActionResult> TranslateSegments([FromBody] TranslateSegmentsRequest request)
{
    // Get user from token claims
    var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    
    // Process translation...
    
    return Ok(result);
}
```

**Артықшылықтары:**
- ✅ Stateless - server memory-де session жоқ
- ✅ Scalable - multiple server instances
- ✅ Token өзінде user info бар
- ✅ Mobile/Desktop app-терге қолайлы

**Кемшіліктері:**
- ⚠️ Token revocation күрделі (whitelist/blacklist керек)

---

### ✅ Опция 3: Refresh Token Mechanism

Long-running operations үшін refresh token.

#### Models

```csharp
public class TokenResponse
{
    public string AccessToken { get; set; }  // 15 минут
    public string RefreshToken { get; set; } // 7 күн
    public int ExpiresIn { get; set; }
}

public class RefreshTokenRequest
{
    public string RefreshToken { get; set; }
}
```

#### Refresh Endpoint

```csharp
[HttpPost("refresh")]
public async Task<IActionResult> RefreshToken([FromBody] RefreshTokenRequest request)
{
    var storedToken = await _tokenService.GetRefreshToken(request.RefreshToken);
    
    if (storedToken == null || storedToken.ExpiresAt < DateTime.UtcNow)
    {
        return Unauthorized(new { message = "Invalid or expired refresh token" });
    }

    var user = await _userService.GetById(storedToken.UserId);
    var newAccessToken = GenerateJwtToken(user);
    var newRefreshToken = await _tokenService.GenerateRefreshToken(user.Id);

    // Invalidate old refresh token
    await _tokenService.RevokeRefreshToken(request.RefreshToken);

    return Ok(new TokenResponse
    {
        AccessToken = newAccessToken,
        RefreshToken = newRefreshToken,
        ExpiresIn = 900 // 15 minutes
    });
}
```

#### Database Table

```sql
CREATE TABLE RefreshTokens (
    Id INT PRIMARY KEY IDENTITY,
    UserId INT FOREIGN KEY REFERENCES Users(Id),
    Token NVARCHAR(500) UNIQUE NOT NULL,
    CreatedAt DATETIME2 NOT NULL,
    ExpiresAt DATETIME2 NOT NULL,
    RevokedAt DATETIME2 NULL,
    IsRevoked BIT NOT NULL DEFAULT 0
);
```

---

### ⚠️ Опция 4: Session-ды Activity-мен ұзарту

Processing кезінде периодты "heartbeat" request жіберу.

**Backend:**

```csharp
[HttpPost("api/heartbeat")]
[Authorize]
public IActionResult Heartbeat()
{
    // Session автоматты ұзарады (sliding expiration)
    return Ok(new { status = "alive", timestamp = DateTime.UtcNow });
}
```

**Frontend (Flutter):**

```dart
// Orchestrator-да timer қосу
Timer? _sessionHeartbeatTimer;

void _startSessionHeartbeat() {
  _sessionHeartbeatTimer = Timer.periodic(Duration(minutes: 2), (_) async {
    try {
      await apiClient.post('/api/heartbeat');
      print('🫀 Session heartbeat sent');
    } catch (e) {
      print('⚠️ Heartbeat failed: $e');
    }
  });
}

void _stopSessionHeartbeat() {
  _sessionHeartbeatTimer?.cancel();
}
```

**Кемшіліктері:**
- ⚠️ Network overhead
- ⚠️ Battery drainage (mobile)
- ⚠️ Complexity

---

## 🎯 Ұсынылатын шешім

**Short-term (қарапайым):**
```csharp
// Опция 1: Session timeout ұлғайту
options.IdleTimeout = TimeSpan.FromMinutes(60);
```

**Long-term (өндірістік):**
```csharp
// Опция 2: JWT Token-based authentication
// + Опция 3: Refresh tokens
```

---

## Frontend өзгертулер (қажет болса)

### JWT Token қолданса

`lib/services/api_client.dart`:

```dart
// Header автоматты қосылады (әлдеқашан бар)
options.headers['Authorization'] = 'Bearer $token';
```

### Refresh Token қолданса

`lib/services/api_client.dart`:

```dart
dio.interceptors.add(
  InterceptorsWrapper(
    onError: (error, handler) async {
      if (error.response?.statusCode == 401) {
        // Try refresh token
        final refreshed = await _refreshToken();
        if (refreshed) {
          // Retry original request
          return handler.resolve(await _retry(error.requestOptions));
        }
      }
      return handler.next(error);
    },
  ),
);
```

---

## Testing

1. **Timeout test:**
   ```bash
   # Start translation, wait 15 minutes, check if still works
   ```

2. **Token expiration:**
   ```bash
   # Set JWT expiration to 1 minute, test automatic refresh
   ```

3. **Concurrent requests:**
   ```bash
   # Multiple devices, same user, check session conflicts
   ```

---

## Қосымша ескертулер

### Security Best Practices

1. **HTTPS only** - Token transmission
2. **Token storage** - Secure storage (не session storage)
3. **CORS configuration** - Allow frontend domain
4. **Rate limiting** - Prevent brute force

### Migration Path

```
Current (Session-based)
    ↓
1. Add JWT alongside sessions (hybrid)
    ↓
2. Migrate users gradually
    ↓
3. Deprecate session-based
    ↓
Final (Token-based)
```

---

## Қорытынды

**SESSION_NOT_FOUND** мәселесін шешу үшін backend-те:

1. ✅ **Қысқа мерзім:** Session timeout-ты 60 минутқа көтеру
2. ✅ **Ұзақ мерзім:** JWT + Refresh Token механизмін енгізу
3. ✅ **Testing:** Long-running operations тестілеу

**Flutter код өзгерту қажет емес** - API client әлдеқашан JWT-ға дайын!
