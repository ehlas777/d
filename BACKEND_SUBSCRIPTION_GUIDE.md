# Backend Subscription Implementation Guide
# Жазылымдарды Backend-те жүзеге асыру нұсқаулығы

## 📋 Мазмұны / Table of Contents

1. [Шолу / Overview](#overview)
2. [Дерекқор схемасы / Database Schema](#database-schema)
3. [API Endpoints](#api-endpoints)
4. [Apple Receipt Verification](#apple-receipt-verification)
5. [Google Play Billing Verification](#google-play-billing-verification)
6. [Cross-Platform Синхрондау / Sync](#cross-platform-sync)
7. [Webhook Integration](#webhook-integration)
8. [Қауіпсіздік / Security](#security)
9. [Тестілеу / Testing](#testing)

---

## 🎯 Overview / Шолу

### Мақсат / Goal

Cross-platform subscription жүйесін жүзеге асыру:
- Пайдаланушы iOS-та сатып алып, Android-та қолдана алады
- Пайдаланушы Android-та сатып алып, iOS-та қолдана алады
- Барлық платформаларда бірдей subscription статусы

### Архитектура / Architecture

```
┌─────────────┐
│  iOS App    │──┐
└─────────────┘  │
                 │    ┌──────────────┐    ┌──────────────┐
┌─────────────┐  ├───→│   Backend    │───→│   Database   │
│ Android App │──┤    │   API        │    │              │
└─────────────┘  │    └──────────────┘    └──────────────┘
                 │           │
┌─────────────┐  │           ↓
│  macOS App  │──┘    ┌──────────────┐
└─────────────┘       │ Apple/Google │
                      │   Servers    │
                      └──────────────┘
```

---

## 🗄️ Database Schema / Дерекқор схемасы

### 1. Users Table

```sql
CREATE TABLE Users (
    Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    Email NVARCHAR(255) NOT NULL UNIQUE,
    Username NVARCHAR(100) NOT NULL,
    PasswordHash NVARCHAR(255) NOT NULL,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),
    
    INDEX IX_Users_Email (Email)
);
```

### 2. Subscriptions Table

```sql
CREATE TABLE Subscriptions (
    Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    UserId UNIQUEIDENTIFIER NOT NULL,
    
    -- Subscription Details
    PlanId NVARCHAR(50) NOT NULL, -- 'standard', 'pro'
    Platform NVARCHAR(20) NOT NULL, -- 'ios', 'android'
    Status NVARCHAR(20) NOT NULL, -- 'active', 'expired', 'cancelled', 'pending'
    
    -- Platform-specific IDs
    OriginalTransactionId NVARCHAR(255), -- Apple/Google transaction ID
    ProductId NVARCHAR(255) NOT NULL,
    
    -- Dates
    PurchaseDate DATETIME2 NOT NULL,
    ExpiresDate DATETIME2 NOT NULL,
    CancelledDate DATETIME2 NULL,
    
    -- Auto-renewal
    AutoRenewing BIT DEFAULT 1,
    
    -- Metadata
    Receipt NVARCHAR(MAX), -- Encrypted receipt data
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),
    
    FOREIGN KEY (UserId) REFERENCES Users(Id),
    INDEX IX_Subscriptions_UserId (UserId),
    INDEX IX_Subscriptions_Status (Status),
    INDEX IX_Subscriptions_ExpiresDate (ExpiresDate)
);
```

### 3. SubscriptionHistory Table (опционал)

```sql
CREATE TABLE SubscriptionHistory (
    Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    SubscriptionId UNIQUEIDENTIFIER NOT NULL,
    UserId UNIQUEIDENTIFIER NOT NULL,
    
    Event NVARCHAR(50) NOT NULL, -- 'purchased', 'renewed', 'cancelled', 'expired'
    OldStatus NVARCHAR(20),
    NewStatus NVARCHAR(20),
    
    Metadata NVARCHAR(MAX), -- JSON
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    
    FOREIGN KEY (SubscriptionId) REFERENCES Subscriptions(Id),
    FOREIGN KEY (UserId) REFERENCES Users(Id),
    INDEX IX_SubscriptionHistory_SubscriptionId (SubscriptionId)
);
```

---

## 🔌 API Endpoints

### 1. Get Current Subscription

**Endpoint:** `GET /api/subscription/current`

**Headers:**
```
Authorization: Bearer {jwt_token}
```

**Response:**
```json
{
  "subscription": {
    "id": "uuid",
    "planId": "pro",
    "status": "active",
    "expiresDate": "2026-02-03T10:00:00Z",
    "autoRenewing": true,
    "platform": "ios"
  }
}
```

**C# Implementation:**
```csharp
[HttpGet("current")]
[Authorize]
public async Task<IActionResult> GetCurrentSubscription()
{
    var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    
    var subscription = await _context.Subscriptions
        .Where(s => s.UserId == Guid.Parse(userId))
        .Where(s => s.Status == "active")
        .Where(s => s.ExpiresDate > DateTime.UtcNow)
        .OrderByDescending(s => s.ExpiresDate)
        .FirstOrDefaultAsync();
    
    if (subscription == null)
    {
        return Ok(new { subscription = (object)null });
    }
    
    return Ok(new { subscription });
}
```

---

### 2. Verify Apple Receipt

**Endpoint:** `POST /api/subscription/verify-apple`

**Headers:**
```
Authorization: Bearer {jwt_token}
Content-Type: application/json
```

**Request Body:**
```json
{
  "receiptData": "base64_encoded_receipt",
  "productId": "com.qaznat.polydub.subscription.pro"
}
```

**Response:**
```json
{
  "success": true,
  "subscription": {
    "id": "uuid",
    "planId": "pro",
    "expiresDate": "2026-02-03T10:00:00Z"
  }
}
```

**C# Implementation:**
```csharp
[HttpPost("verify-apple")]
[Authorize]
public async Task<IActionResult> VerifyAppleReceipt([FromBody] AppleReceiptRequest request)
{
    var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    
    try
    {
        // 1. Verify receipt with Apple
        var verificationResult = await VerifyReceiptWithApple(request.ReceiptData);
        
        if (!verificationResult.IsValid)
        {
            return BadRequest(new { success = false, error = "Invalid receipt" });
        }
        
        // 2. Extract subscription info
        var latestReceipt = verificationResult.LatestReceiptInfo;
        var expiresDate = DateTimeOffset.FromUnixTimeMilliseconds(
            long.Parse(latestReceipt.ExpiresDateMs)
        ).UtcDateTime;
        
        // 3. Save to database
        var subscription = new Subscription
        {
            UserId = Guid.Parse(userId),
            PlanId = GetPlanIdFromProductId(request.ProductId),
            Platform = "ios",
            Status = "active",
            OriginalTransactionId = latestReceipt.OriginalTransactionId,
            ProductId = request.ProductId,
            PurchaseDate = DateTime.UtcNow,
            ExpiresDate = expiresDate,
            AutoRenewing = latestReceipt.AutoRenewStatus == "1",
            Receipt = EncryptReceipt(request.ReceiptData)
        };
        
        _context.Subscriptions.Add(subscription);
        await _context.SaveChangesAsync();
        
        // 4. Log history
        await LogSubscriptionEvent(subscription.Id, userId, "purchased");
        
        return Ok(new { success = true, subscription });
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Apple receipt verification failed");
        return StatusCode(500, new { success = false, error = ex.Message });
    }
}

private async Task<AppleVerificationResult> VerifyReceiptWithApple(string receiptData)
{
    using var httpClient = new HttpClient();
    
    // Production URL
    var url = "https://buy.itunes.apple.com/verifyReceipt";
    
    // Sandbox URL (for testing)
    // var url = "https://sandbox.itunes.apple.com/verifyReceipt";
    
    var requestBody = new
    {
        receipt_data = receiptData,
        password = _configuration["Apple:SharedSecret"], // App Store Connect-тен алу
        exclude_old_transactions = true
    };
    
    var response = await httpClient.PostAsJsonAsync(url, requestBody);
    var result = await response.Content.ReadFromJsonAsync<AppleVerificationResult>();
    
    // If status is 21007, try sandbox
    if (result.Status == 21007)
    {
        url = "https://sandbox.itunes.apple.com/verifyReceipt";
        response = await httpClient.PostAsJsonAsync(url, requestBody);
        result = await response.Content.ReadFromJsonAsync<AppleVerificationResult>();
    }
    
    return result;
}
```

**Apple Verification Models:**
```csharp
public class AppleVerificationResult
{
    [JsonPropertyName("status")]
    public int Status { get; set; }
    
    [JsonPropertyName("latest_receipt_info")]
    public List<AppleReceiptInfo> LatestReceiptInfo { get; set; }
    
    public bool IsValid => Status == 0;
}

public class AppleReceiptInfo
{
    [JsonPropertyName("original_transaction_id")]
    public string OriginalTransactionId { get; set; }
    
    [JsonPropertyName("product_id")]
    public string ProductId { get; set; }
    
    [JsonPropertyName("expires_date_ms")]
    public string ExpiresDateMs { get; set; }
    
    [JsonPropertyName("auto_renew_status")]
    public string AutoRenewStatus { get; set; }
}
```

---

### 3. Verify Google Purchase

**Endpoint:** `POST /api/subscription/verify-google`

**Request Body:**
```json
{
  "purchaseToken": "google_purchase_token",
  "productId": "polydub_pro_monthly",
  "packageName": "com.qaznat.polydub"
}
```

**C# Implementation:**
```csharp
[HttpPost("verify-google")]
[Authorize]
public async Task<IActionResult> VerifyGooglePurchase([FromBody] GooglePurchaseRequest request)
{
    var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    
    try
    {
        // 1. Initialize Google Play Developer API
        var credential = GoogleCredential.FromFile("path/to/service-account.json")
            .CreateScoped(AndroidPublisherService.Scope.Androidpublisher);
        
        var service = new AndroidPublisherService(new BaseClientService.Initializer
        {
            HttpClientInitializer = credential
        });
        
        // 2. Verify purchase
        var purchaseRequest = service.Purchases.Subscriptions.Get(
            request.PackageName,
            request.ProductId,
            request.PurchaseToken
        );
        
        var purchase = await purchaseRequest.ExecuteAsync();
        
        // 3. Check if valid
        if (purchase.PaymentState != 1) // 1 = Paid
        {
            return BadRequest(new { success = false, error = "Payment not completed" });
        }
        
        var expiresDate = DateTimeOffset.FromUnixTimeMilliseconds(
            purchase.ExpiryTimeMillis ?? 0
        ).UtcDateTime;
        
        // 4. Save to database
        var subscription = new Subscription
        {
            UserId = Guid.Parse(userId),
            PlanId = GetPlanIdFromProductId(request.ProductId),
            Platform = "android",
            Status = "active",
            OriginalTransactionId = purchase.OrderId,
            ProductId = request.ProductId,
            PurchaseDate = DateTime.UtcNow,
            ExpiresDate = expiresDate,
            AutoRenewing = purchase.AutoRenewing ?? false,
            Receipt = EncryptPurchaseToken(request.PurchaseToken)
        };
        
        _context.Subscriptions.Add(subscription);
        await _context.SaveChangesAsync();
        
        return Ok(new { success = true, subscription });
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Google purchase verification failed");
        return StatusCode(500, new { success = false, error = ex.Message });
    }
}
```

**NuGet Packages:**
```xml
<PackageReference Include="Google.Apis.AndroidPublisher.v3" Version="1.60.0.3066" />
```

---

### 4. Cancel Subscription

**Endpoint:** `POST /api/subscription/cancel`

**C# Implementation:**
```csharp
[HttpPost("cancel")]
[Authorize]
public async Task<IActionResult> CancelSubscription()
{
    var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    
    var subscription = await _context.Subscriptions
        .Where(s => s.UserId == Guid.Parse(userId))
        .Where(s => s.Status == "active")
        .FirstOrDefaultAsync();
    
    if (subscription == null)
    {
        return NotFound(new { success = false, error = "No active subscription" });
    }
    
    subscription.Status = "cancelled";
    subscription.CancelledDate = DateTime.UtcNow;
    subscription.AutoRenewing = false;
    subscription.UpdatedAt = DateTime.UtcNow;
    
    await _context.SaveChangesAsync();
    await LogSubscriptionEvent(subscription.Id, userId, "cancelled");
    
    return Ok(new { success = true });
}
```

---

## 🔔 Webhook Integration

### Apple Server Notifications

**Endpoint:** `POST /api/webhooks/apple`

```csharp
[HttpPost("apple")]
[AllowAnonymous]
public async Task<IActionResult> AppleWebhook([FromBody] AppleNotification notification)
{
    try
    {
        // Verify signature
        if (!VerifyAppleSignature(notification))
        {
            return Unauthorized();
        }
        
        var notificationType = notification.NotificationType;
        var receiptInfo = notification.UnifiedReceipt.LatestReceiptInfo.First();
        
        var subscription = await _context.Subscriptions
            .FirstOrDefaultAsync(s => s.OriginalTransactionId == receiptInfo.OriginalTransactionId);
        
        if (subscription == null)
        {
            return NotFound();
        }
        
        switch (notificationType)
        {
            case "DID_RENEW":
                subscription.ExpiresDate = DateTimeOffset.FromUnixTimeMilliseconds(
                    long.Parse(receiptInfo.ExpiresDateMs)
                ).UtcDateTime;
                await LogSubscriptionEvent(subscription.Id, subscription.UserId.ToString(), "renewed");
                break;
                
            case "DID_FAIL_TO_RENEW":
                subscription.Status = "expired";
                subscription.AutoRenewing = false;
                await LogSubscriptionEvent(subscription.Id, subscription.UserId.ToString(), "renewal_failed");
                break;
                
            case "CANCEL":
                subscription.Status = "cancelled";
                subscription.CancelledDate = DateTime.UtcNow;
                await LogSubscriptionEvent(subscription.Id, subscription.UserId.ToString(), "cancelled");
                break;
        }
        
        await _context.SaveChangesAsync();
        return Ok();
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Apple webhook processing failed");
        return StatusCode(500);
    }
}
```

---

## 🔒 Security / Қауіпсіздік

### 1. Receipt Encryption

```csharp
private string EncryptReceipt(string receipt)
{
    using var aes = Aes.Create();
    aes.Key = Convert.FromBase64String(_configuration["Encryption:Key"]);
    aes.IV = Convert.FromBase64String(_configuration["Encryption:IV"]);
    
    using var encryptor = aes.CreateEncryptor();
    var receiptBytes = Encoding.UTF8.GetBytes(receipt);
    var encrypted = encryptor.TransformFinalBlock(receiptBytes, 0, receiptBytes.Length);
    
    return Convert.ToBase64String(encrypted);
}
```

### 2. API Rate Limiting

```csharp
services.AddRateLimiter(options =>
{
    options.AddFixedWindowLimiter("subscription", opt =>
    {
        opt.Window = TimeSpan.FromMinutes(1);
        opt.PermitLimit = 10;
    });
});
```

### 3. JWT Validation

```csharp
services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = Configuration["Jwt:Issuer"],
            ValidAudience = Configuration["Jwt:Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(Configuration["Jwt:Key"])
            )
        };
    });
```

---

## 🧪 Testing / Тестілеу

### 1. Unit Tests

```csharp
[Fact]
public async Task VerifyAppleReceipt_ValidReceipt_ReturnsSuccess()
{
    // Arrange
    var controller = new SubscriptionController(_context, _logger, _config);
    var request = new AppleReceiptRequest
    {
        ReceiptData = "valid_receipt_data",
        ProductId = "com.qaznat.polydub.subscription.pro"
    };
    
    // Act
    var result = await controller.VerifyAppleReceipt(request);
    
    // Assert
    var okResult = Assert.IsType<OkObjectResult>(result);
    var response = Assert.IsType<VerificationResponse>(okResult.Value);
    Assert.True(response.Success);
}
```

### 2. Integration Tests

```csharp
[Fact]
public async Task GetCurrentSubscription_ActiveSubscription_ReturnsSubscription()
{
    // Arrange
    var client = _factory.CreateClient();
    var token = await GetAuthToken();
    client.DefaultRequestHeaders.Authorization = 
        new AuthenticationHeaderValue("Bearer", token);
    
    // Act
    var response = await client.GetAsync("/api/subscription/current");
    
    // Assert
    response.EnsureSuccessStatusCode();
    var subscription = await response.Content.ReadFromJsonAsync<SubscriptionResponse>();
    Assert.NotNull(subscription);
}
```

---

## 📝 Configuration / Конфигурация

### appsettings.json

```json
{
  "Apple": {
    "SharedSecret": "your_app_store_shared_secret",
    "WebhookUrl": "https://yourdomain.com/api/webhooks/apple"
  },
  "Google": {
    "ServiceAccountPath": "path/to/service-account.json",
    "PackageName": "com.qaznat.polydub"
  },
  "Encryption": {
    "Key": "base64_encryption_key",
    "IV": "base64_initialization_vector"
  },
  "Jwt": {
    "Key": "your_jwt_secret_key",
    "Issuer": "JwtAuthApi",
    "Audience": "JwtAuthApi"
  }
}
```

---

## 🚀 Deployment Checklist

- [ ] Дерекқор миграциялары орындалды
- [ ] Apple Shared Secret конфигурацияланды
- [ ] Google Service Account жасалды
- [ ] JWT қауіпсіздігі қосылды
- [ ] Rate limiting қосылды
- [ ] Webhook endpoints тестіленді
- [ ] Logging және monitoring қосылды
- [ ] HTTPS қосылды
- [ ] Backup стратегиясы дайын

---

## 📚 Қосымша ресурстар

- [Apple Receipt Validation](https://developer.apple.com/documentation/appstorereceipts/verifyreceipt)
- [Google Play Billing API](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptions)
- [ASP.NET Core Security](https://docs.microsoft.com/en-us/aspnet/core/security/)

---

**Құжат жасалды:** 2026-01-03  
**Нұсқа:** 1.0  
**Автор:** Antigravity AI
