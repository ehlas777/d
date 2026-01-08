# VIP/Unlimited қолданушылар үшін Backend өзгерістер

## Мәселе

Flutter қолданбасы VIP статусты пайдаланушылар үшін барлық шектеулерді алып тастау керек. Бұл үшін backend `/api/TranslationStats/user-balance` endpoint-і `hasUnlimitedAccess: true` қайтаруы тиіс.

## Қажетті Backend Response форматы

### `/api/TranslationStats/user-balance` endpoint

**Request:**
```http
GET /api/TranslationStats/user-balance?search={username|email}
Authorization: Bearer {token}
```

**Response (VIP қолданушы үшін):**
```json
{
  "id": "user-id",
  "email": "user@example.com",
  "name": "Username",
  "hasUnlimitedAccess": true,  // ⚠️ МАҢЫЗДЫ: VIP үшін true болуы керек
  "subscriptionStatus": "VIP",
  "balanceMinutes": 999999,    // Үлкен сан немесе null
  "totalLimit": 999999,
  "usedMinutes": 0,
  "maxVideoDuration": null     // null = шектеусіз
}
```

**Response (қарапайым қолданушы үшін):**
```json
{
  "id": "user-id",
  "email": "user@example.com",
  "name": "Username",
  "hasUnlimitedAccess": false, // немесе болмауы мүмкін
  "subscriptionStatus": "Free",
  "balanceMinutes": 50.5,
  "totalLimit": 100,
  "usedMinutes": 49.5,
  "maxVideoDuration": 60
}
```

## VIP статусын анықтау логикасы

Backend келесі шарттарда `hasUnlimitedAccess: true` қайтаруы керек:

1. **SubscriptionStatus = "VIP"** - дәл VIP дәрежесі
2. **SubscriptionStatus = "Premium" немесе "Enterprise"** - жоғары дәрежелер
3. **Admin роль** - әкімшілер (опционалды)
4. **Custom "Unlimited" flag** - database-де арнайы белгі

```csharp
// C# мысалы (backend код)
public class UserBalanceResponse
{
    public string Id { get; set; }
    public string Email { get; set; }
    public string Name { get; set; }
    
    // КРИТИКАЛЫҚ: VIP үшін true
    public bool HasUnlimitedAccess { get; set; }
    
    public string SubscriptionStatus { get; set; }
    public double? BalanceMinutes { get; set; }
    public double? TotalLimit { get; set; }
    public double? UsedMinutes { get; set; }
    public double? MaxVideoDuration { get; set; }
}

// Controller method
[HttpGet("user-balance")]
public async Task<ActionResult<UserBalanceResponse>> GetUserBalance([FromQuery] string search)
{
    var user = await _userService.FindByEmailOrUsername(search);
    if (user == null) return NotFound();
    
    var stats = await _translationStatsService.GetStats(user.Id);
    
    // VIP статусын тексеру
    bool isUnlimited = user.SubscriptionStatus == "VIP" 
                    || user.SubscriptionStatus == "Premium"
                    || user.SubscriptionStatus == "Enterprise"
                    || user.IsAdmin
                    || user.HasUnlimitedFlag;
    
    return new UserBalanceResponse
    {
        Id = user.Id,
        Email = user.Email,
        Name = user.Username,
        HasUnlimitedAccess = isUnlimited,  // ⚠️ МІНДЕТТІ
        SubscriptionStatus = user.SubscriptionStatus,
        BalanceMinutes = isUnlimited ? 999999 : stats.BalanceMinutes,
        TotalLimit = isUnlimited ? 999999 : stats.TotalLimit,
        UsedMinutes = stats.UsedMinutes,
        MaxVideoDuration = isUnlimited ? null : user.MaxVideoDuration
    };
}
```

## Flutter-дегі пайдалану

Flutter қолданбасы `hasUnlimitedAccess` мәнін келесідей қолданады:

```dart
// VIP қолданушылар үшін:
if (userInfo?.hasUnlimitedAccess == true) {
  // ✅ Күнделікті лимит тексерусіз
  // ✅ Баланс тексерусіз
  // ✅ Видео ұзақтығына шектеусіз
  // ✅ Trim болмайды
}
```

## Тестілеу

### Тест жағдайлары:

1. **VIP пайдаланушы:**
   - `hasUnlimitedAccess: true` қайтару керек
   - `balanceMinutes` үлкен сан немесе null
   - `maxVideoDuration` null болуы керек

2. **Free пайдаланушы:**
   - `hasUnlimitedAccess: false` немесе field болмауы мүмкін
   - `balanceMinutes` нақты сан (50, 100, т.б.)
   - `maxVideoDuration` нақты шек (60, 120, т.б.)

### cURL тест:

```bash
# VIP пайдаланушыны тесттеу
curl -X GET "https://api.example.com/api/TranslationStats/user-balance?search=vip@email.com" \
  -H "Authorization: Bearer {token}"

# Күткен нәтиже:
# {
#   "hasUnlimitedAccess": true,
#   "subscriptionStatus": "VIP",
#   ...
# }
```

## Database Schema (Мысал)

```sql
-- Users кестесіне қосу
ALTER TABLE Users ADD COLUMN HasUnlimitedAccess BOOLEAN DEFAULT FALSE;
ALTER TABLE Users ADD COLUMN SubscriptionStatus VARCHAR(50) DEFAULT 'Free';

-- VIP қолданушыларды жаңарту
UPDATE Users 
SET HasUnlimitedAccess = TRUE, 
    SubscriptionStatus = 'VIP'
WHERE Email = 'vip@example.com' OR Username = 'vipuser';
```

## Маңызды ескертулер

1. **Field атауы**: `hasUnlimitedAccess` (camelCase) - Flutter JSON deserialization үшін
2. **Boolean мән**: `true/false` - string емес, boolean
3. **Null vs false**: `null` жіберу жағымды, Flutter `== true` тексереді
4. **Кері үйлесімділік**: Ескі клиенттер үшін field болмаса проблема жоқ (null = false)

## Қосымша ақпарат

- VIP пайдаланушылар ешқандай лимитке ие емес
- Backend минут есептеусіз өткізу керек
- Billing/statistics үшін қолдануды log-та сақтау керек (tracking үшін)
