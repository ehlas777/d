# Backend User Settings & Subscription API Guide

## Мазмұны
1. [Шолу](#шолу)
2. [Қолданушы баптауларын сақтау](#қолданушы-баптауларын-сақтау)
3. [Subscription API тілге байланысты деректер](#subscription-api-тілге-байланысты-деректер)
4. [API Endpoints](#api-endpoints)
5. [Database Schema](#database-schema)
6. [Frontend Integration](#frontend-integration)

---

## Шолу

Бұл құжат backend-те қолданушы баптауларын сақтау және subscription деректерін тілге байланысты қайтару туралы нұсқаулық.

### Негізгі талаптар:
- ✅ Қолданушының таңдаған **интерфейс тілін** сақтау
- ✅ Қолданушының **аударма баптауларын** сақтау (target language, speed, т.б.)
- ✅ Барлық құрылғыларда **синхрондау**
- ✅ Subscription бағаларын **USD валютасында** қайтару
- ✅ Subscription деректерін **тілге байланысты** қайтару

---

## Қолданушы баптауларын сақтау

### 1. User Settings Model

Backend-те `UserSettings` моделін жасау керек:

```csharp
public class UserSettings
{
    public string UserId { get; set; }
    
    // Interface Language Settings
    public string InterfaceLanguage { get; set; } = "en"; // en, kk, ru, zh, ar, uz, tr
    
    // Translation Settings
    public string DefaultSourceLanguage { get; set; } = "auto";
    public string DefaultTargetLanguage { get; set; } = "en";
    public double VideoSpeed { get; set; } = 1.0; // 0.5 to 2.0
    
    // App Preferences
    public bool AutoSaveProjects { get; set; } = true;
    public bool ShowWatermark { get; set; } = true;
    public string VideoQuality { get; set; } = "high"; // low, medium, high
    
    // Timestamps
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
```

### 2. Database Table

PostgreSQL/SQL Server үшін:

```sql
CREATE TABLE UserSettings (
    UserId VARCHAR(36) PRIMARY KEY,
    InterfaceLanguage VARCHAR(10) NOT NULL DEFAULT 'en',
    DefaultSourceLanguage VARCHAR(10) DEFAULT 'auto',
    DefaultTargetLanguage VARCHAR(10) DEFAULT 'en',
    VideoSpeed DECIMAL(3,2) DEFAULT 1.0,
    AutoSaveProjects BOOLEAN DEFAULT TRUE,
    ShowWatermark BOOLEAN DEFAULT TRUE,
    VideoQuality VARCHAR(20) DEFAULT 'high',
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (UserId) REFERENCES Users(Id) ON DELETE CASCADE
);

-- Index for faster lookups
CREATE INDEX idx_user_settings_user_id ON UserSettings(UserId);
```

---

## Subscription API тілге байланысты деректер

### 1. Subscription Plan Model

Backend-те subscription plan деректерін тілге байланысты қайтару:

```csharp
public class SubscriptionPlan
{
    public string Id { get; set; }
    public string TierName { get; set; } // "standard", "pro", "vip"
    
    // Localized fields
    public Dictionary<string, string> Name { get; set; } // { "en": "Standard", "kk": "Стандарт", "ru": "Стандарт" }
    public Dictionary<string, string> Description { get; set; }
    public Dictionary<string, List<string>> Features { get; set; }
    
    // Pricing (always in USD)
    public decimal MonthlyPrice { get; set; }
    public string Currency { get; set; } = "USD";
    public string Interval { get; set; } = "month";
    
    // Platform-specific product IDs
    public string IosProductId { get; set; }
    public string AndroidProductId { get; set; }
    
    public bool IsActive { get; set; } = true;
}
```

### 2. Database Schema for Subscription Plans

```sql
CREATE TABLE SubscriptionPlans (
    Id VARCHAR(36) PRIMARY KEY,
    TierName VARCHAR(50) NOT NULL UNIQUE, -- 'standard', 'pro', 'vip'
    MonthlyPrice DECIMAL(10,2) NOT NULL,
    Currency VARCHAR(3) DEFAULT 'USD',
    Interval VARCHAR(20) DEFAULT 'month',
    IosProductId VARCHAR(100),
    AndroidProductId VARCHAR(100),
    IsActive BOOLEAN DEFAULT TRUE,
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Localized content table
CREATE TABLE SubscriptionPlanLocalizations (
    Id SERIAL PRIMARY KEY,
    PlanId VARCHAR(36) NOT NULL,
    LanguageCode VARCHAR(10) NOT NULL, -- 'en', 'kk', 'ru', etc.
    Name VARCHAR(100) NOT NULL,
    Description TEXT,
    Features JSONB, -- Array of feature strings
    FOREIGN KEY (PlanId) REFERENCES SubscriptionPlans(Id) ON DELETE CASCADE,
    UNIQUE(PlanId, LanguageCode)
);

-- Index for faster lookups
CREATE INDEX idx_plan_localizations ON SubscriptionPlanLocalizations(PlanId, LanguageCode);
```

### 3. Sample Data

```sql
-- Insert subscription plans
INSERT INTO SubscriptionPlans (Id, TierName, MonthlyPrice, Currency, IosProductId, AndroidProductId) VALUES
('plan-standard', 'standard', 19.99, 'USD', 'com.qaznat.polydub.subscription.standard', 'polydub_standard_monthly'),
('plan-pro', 'pro', 39.99, 'USD', 'com.qaznat.polydub.subscription.pro', 'polydub_pro_monthly');

-- Insert English localizations
INSERT INTO SubscriptionPlanLocalizations (PlanId, LanguageCode, Name, Description, Features) VALUES
('plan-standard', 'en', 'Standard', 'Basic video translation features', 
 '["10 minutes/day free translation", "Basic support", "Standard quality", "Access to all languages"]'::jsonb),
('plan-pro', 'en', 'Pro', 'Advanced translation with priority support',
 '["30 minutes/day free translation", "Priority support", "High quality", "Advanced features", "No watermark"]'::jsonb);

-- Insert Kazakh localizations
INSERT INTO SubscriptionPlanLocalizations (PlanId, LanguageCode, Name, Description, Features) VALUES
('plan-standard', 'kk', 'Стандарт', 'Бейне аударма үшін базалық мүмкіндіктер',
 '["Күніне 10 минут тегін аударма", "Базалық қолдау", "Стандартты сапа", "Барлық тілдерге қолжетімділік"]'::jsonb),
('plan-pro', 'kk', 'Pro', 'Кеңейтілген аударма және басымды қолдау',
 '["Күніне 30 минут тегін аударма", "Басымды қолдау", "Жоғары сапа", "Кеңейтілген мүмкіндіктер", "Су таңбасыз"]'::jsonb);

-- Insert Russian localizations
INSERT INTO SubscriptionPlanLocalizations (PlanId, LanguageCode, Name, Description, Features) VALUES
('plan-standard', 'ru', 'Стандарт', 'Базовые функции для перевода видео',
 '["10 минут перевода в день бесплатно", "Базовая поддержка", "Стандартное качество", "Доступ ко всем языкам"]'::jsonb),
('plan-pro', 'ru', 'Pro', 'Расширенный перевод и приоритетная поддержка',
 '["30 минут перевода в день бесплатно", "Приоритетная поддержка", "Высокое качество", "Расширенные функции", "Без водяных знаков"]'::jsonb);
```

---

## API Endpoints

### 1. User Settings Endpoints

#### GET `/api/user/settings`
Қолданушының баптауларын алу

**Response:**
```json
{
  "userId": "4fc1c1eb-4864-4a0c-b03a-549df2c83f3b",
  "interfaceLanguage": "kk",
  "defaultSourceLanguage": "auto",
  "defaultTargetLanguage": "en",
  "videoSpeed": 1.0,
  "autoSaveProjects": true,
  "showWatermark": true,
  "videoQuality": "high",
  "updatedAt": "2026-01-03T12:30:00Z"
}
```

#### PUT `/api/user/settings`
Қолданушының баптауларын жаңарту

**Request:**
```json
{
  "interfaceLanguage": "en",
  "defaultTargetLanguage": "kk",
  "videoSpeed": 1.2
}
```

**Response:**
```json
{
  "success": true,
  "message": "Settings updated successfully",
  "settings": {
    "userId": "4fc1c1eb-4864-4a0c-b03a-549df2c83f3b",
    "interfaceLanguage": "en",
    "defaultTargetLanguage": "kk",
    "videoSpeed": 1.2,
    "updatedAt": "2026-01-03T12:35:00Z"
  }
}
```

### 2. Subscription Endpoints

#### GET `/api/subscription/products`
Subscription жоспарларын тілге байланысты алу

**Query Parameters:**
- `platform` (required): "ios", "android", "web"
- `lang` (optional, default: "en"): "en", "kk", "ru", "zh", "ar", "uz", "tr"

**Request Example:**
```
GET /api/subscription/products?platform=ios&lang=kk
```

**Response:**
```json
{
  "products": [
    {
      "id": "plan-standard",
      "tierName": "standard",
      "name": "Стандарт",
      "description": "Бейне аударма үшін базалық мүмкіндіктер",
      "monthlyPrice": 19.99,
      "currency": "USD",
      "interval": "month",
      "features": [
        "Күніне 10 минут тегін аударма",
        "Базалық қолдау",
        "Стандартты сапа",
        "Барлық тілдерге қолжетімділік"
      ],
      "productId": "com.qaznat.polydub.subscription.standard"
    },
    {
      "id": "plan-pro",
      "tierName": "pro",
      "name": "Pro",
      "description": "Кеңейтілген аударма және басымды қолдау",
      "monthlyPrice": 39.99,
      "currency": "USD",
      "interval": "month",
      "features": [
        "Күніне 30 минут тегін аударма",
        "Басымды қолдау",
        "Жоғары сапа",
        "Кеңейтілген мүмкіндіктер",
        "Су таңбасыз"
      ],
      "productId": "com.qaznat.polydub.subscription.pro"
    }
  ]
}
```

**Response for English (lang=en):**
```json
{
  "products": [
    {
      "id": "plan-standard",
      "tierName": "standard",
      "name": "Standard",
      "description": "Basic video translation features",
      "monthlyPrice": 19.99,
      "currency": "USD",
      "interval": "month",
      "features": [
        "10 minutes/day free translation",
        "Basic support",
        "Standard quality",
        "Access to all languages"
      ],
      "productId": "com.qaznat.polydub.subscription.standard"
    }
  ]
}
```

---

## Backend Implementation (C#)

### 1. UserSettingsController

```csharp
[ApiController]
[Route("api/user")]
[Authorize]
public class UserSettingsController : ControllerBase
{
    private readonly IUserSettingsService _settingsService;
    
    public UserSettingsController(IUserSettingsService settingsService)
    {
        _settingsService = settingsService;
    }
    
    [HttpGet("settings")]
    public async Task<IActionResult> GetSettings()
    {
        var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        var settings = await _settingsService.GetUserSettingsAsync(userId);
        
        if (settings == null)
        {
            // Create default settings if not exists
            settings = await _settingsService.CreateDefaultSettingsAsync(userId);
        }
        
        return Ok(settings);
    }
    
    [HttpPut("settings")]
    public async Task<IActionResult> UpdateSettings([FromBody] UpdateSettingsRequest request)
    {
        var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        var settings = await _settingsService.UpdateUserSettingsAsync(userId, request);
        
        return Ok(new
        {
            success = true,
            message = "Settings updated successfully",
            settings
        });
    }
}
```

### 2. SubscriptionController

```csharp
[ApiController]
[Route("api/subscription")]
public class SubscriptionController : ControllerBase
{
    private readonly ISubscriptionService _subscriptionService;
    
    public SubscriptionController(ISubscriptionService subscriptionService)
    {
        _subscriptionService = subscriptionService;
    }
    
    [HttpGet("products")]
    public async Task<IActionResult> GetProducts(
        [FromQuery] string platform,
        [FromQuery] string lang = "en")
    {
        // Validate platform
        if (!new[] { "ios", "android", "web" }.Contains(platform?.ToLower()))
        {
            return BadRequest(new { error = "Invalid platform. Must be: ios, android, or web" });
        }
        
        // Validate language code
        var supportedLanguages = new[] { "en", "kk", "ru", "zh", "ar", "uz", "tr" };
        if (!supportedLanguages.Contains(lang?.ToLower()))
        {
            lang = "en"; // Fallback to English
        }
        
        var products = await _subscriptionService.GetLocalizedProductsAsync(platform, lang);
        
        return Ok(new { products });
    }
}
```

### 3. SubscriptionService Implementation

```csharp
public class SubscriptionService : ISubscriptionService
{
    private readonly ApplicationDbContext _context;
    
    public SubscriptionService(ApplicationDbContext context)
    {
        _context = context;
    }
    
    public async Task<List<SubscriptionProductDto>> GetLocalizedProductsAsync(
        string platform, 
        string languageCode)
    {
        var plans = await _context.SubscriptionPlans
            .Where(p => p.IsActive)
            .Include(p => p.Localizations)
            .ToListAsync();
        
        var products = new List<SubscriptionProductDto>();
        
        foreach (var plan in plans)
        {
            // Get localization for requested language, fallback to English
            var localization = plan.Localizations
                .FirstOrDefault(l => l.LanguageCode == languageCode)
                ?? plan.Localizations.FirstOrDefault(l => l.LanguageCode == "en");
            
            if (localization == null) continue;
            
            // Get platform-specific product ID
            var productId = platform.ToLower() switch
            {
                "ios" => plan.IosProductId,
                "android" => plan.AndroidProductId,
                _ => null
            };
            
            products.Add(new SubscriptionProductDto
            {
                Id = plan.Id,
                TierName = plan.TierName,
                Name = localization.Name,
                Description = localization.Description,
                MonthlyPrice = plan.MonthlyPrice,
                Currency = "USD", // Always USD
                Interval = plan.Interval,
                Features = localization.Features,
                ProductId = productId
            });
        }
        
        return products;
    }
}
```

---

## Frontend Integration

### 1. Қолданбаны іске қосқанда баптауларды жүктеу

```dart
class AppState extends ChangeNotifier {
  UserSettings? _settings;
  
  Future<void> loadUserSettings() async {
    try {
      final response = await apiClient.get('/api/user/settings');
      _settings = UserSettings.fromJson(response.data);
      
      // Apply interface language
      if (_settings?.interfaceLanguage != null) {
        await _applyInterfaceLanguage(_settings!.interfaceLanguage);
      }
      
      notifyListeners();
    } catch (e) {
      print('Error loading user settings: $e');
    }
  }
  
  Future<void> updateSettings(Map<String, dynamic> updates) async {
    try {
      final response = await apiClient.put('/api/user/settings', data: updates);
      _settings = UserSettings.fromJson(response.data['settings']);
      
      // Apply changes immediately
      if (updates.containsKey('interfaceLanguage')) {
        await _applyInterfaceLanguage(updates['interfaceLanguage']);
      }
      
      notifyListeners();
    } catch (e) {
      print('Error updating settings: $e');
    }
  }
}
```

### 2. Тілді өзгерткенде backend-ке сақтау

```dart
Future<void> changeLanguage(String languageCode) async {
  // Update locally
  await _localeService.setLocale(Locale(languageCode));
  
  // Save to backend
  await _appState.updateSettings({
    'interfaceLanguage': languageCode,
  });
}
```

### 3. Subscription жоспарларын жүктеу

```dart
Future<List<SubscriptionPlan>> getSubscriptionPlans() async {
  final languageCode = Localizations.localeOf(context).languageCode;
  final platform = Platform.isIOS ? 'ios' : Platform.isAndroid ? 'android' : 'web';
  
  final response = await apiClient.get(
    '/api/subscription/products',
    queryParameters: {
      'platform': platform,
      'lang': languageCode,
    },
  );
  
  final products = response.data['products'] as List;
  return products.map((json) => SubscriptionPlan.fromJson(json)).toList();
}
```

---

## Маңызды ескертулер

### 1. Бағалар
- ✅ Барлық бағалар **USD валютасында** сақталады
- ✅ Frontend-те KZT-дан USD-ге конвертация жасалады (егер қажет болса)
- ✅ Backend әрқашан `currency: "USD"` қайтарады

### 2. Тілдер
- ✅ Қолданушының таңдаған тілі backend-те сақталады
- ✅ Барлық құрылғыларда синхрондалады
- ✅ Subscription деректері тілге байланысты қайтарылады

### 3. Баптаулар
- ✅ Қолданушының барлық баптаулары (тіл, жылдамдық, т.б.) backend-те сақталады
- ✅ Жаңа құрылғыда кіргенде автоматты түрде жүктеледі
- ✅ Өзгерістер барлық құрылғыларда синхрондалады

### 4. Fallback механизмі
- ✅ Егер тіл табылмаса, ағылшын тіліне fallback
- ✅ Егер баптаулар жоқ болса, default мәндер қолданылады

---

## Тестілеу

### 1. User Settings тестілеу

```bash
# Get user settings
curl -X GET "http://localhost:5008/api/user/settings" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Update settings
curl -X PUT "http://localhost:5008/api/user/settings" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "interfaceLanguage": "kk",
    "defaultTargetLanguage": "en",
    "videoSpeed": 1.2
  }'
```

### 2. Subscription Products тестілеу

```bash
# Get products in Kazakh
curl -X GET "http://localhost:5008/api/subscription/products?platform=ios&lang=kk"

# Get products in English
curl -X GET "http://localhost:5008/api/subscription/products?platform=ios&lang=en"

# Get products in Russian
curl -X GET "http://localhost:5008/api/subscription/products?platform=ios&lang=ru"
```

---

## Қорытынды

Бұл құжат backend-те:
1. ✅ Қолданушы баптауларын сақтау және синхрондау
2. ✅ Subscription бағаларын USD-да қайтару
3. ✅ Subscription деректерін тілге байланысты қайтару
4. ✅ Барлық құрылғыларда баптауларды синхрондау

туралы толық нұсқаулық береді.
