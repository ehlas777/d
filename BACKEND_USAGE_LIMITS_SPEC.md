# Backend Usage Limits & Tracking Specification

## Overview

Абонттардың видео аударма лимиттерін дұрыс есептеу және tracking жүйесі.

---

## Subscription Tiers

### 1. Free Users (Кірмеген қолданушылар)
- **Daily Limit:** 1 минут
- **Max Video Duration:** 60 секунд
- **Features:** Watermark қосылады
- **Tracking:** IP-based немесе device-based

### 2. Standard Subscription
- **Daily Limit:** 10 минут
- **Max Video Duration:** 10 минут
- **Features:** Watermark жоқ
- **Auto-reset:** Күн сайын 00:00 UTC

### 3. Pro Subscription
- **Daily Limit:** 30 минут
- **Max Video Duration:** 30 минут
- **Features:** Priority processing, HD quality
- **Auto-reset:** Күн сайын 00:00 UTC

### 4. VIP Subscription
- **Daily Limit:** Шексіз (Unlimited)
- **Max Video Duration:** Шексіз
- **Features:** Premium support, no watermark, HD quality
- **Tracking:** Статистика үшін ғана

---

## Usage Calculation Points

### 1️⃣ Видео қосқан кезде (Video Upload)
**Action:** Pre-flight validation only
**Deduction:** ЖОҚ (No deduction yet)
**Logic:**
```
if (user.subscriptionType != "VIP") {
    videoDurationMinutes = video.duration / 60;
    
    if (videoDurationMinutes > user.remainingDailyMinutes) {
        return Error("Insufficient balance");
    }
    
    if (videoDurationMinutes > user.maxVideoDuration) {
        return Error("Video too long for your tier");
    }
}

// Allow upload, but don't deduct yet
return Success();
```

### 2️⃣ Аударған кезде (Translation Start)
**Action:** Deduct from balance
**Deduction:** ✅ ИӘ (Full video duration)
**Timing:** When `/api/translation/translate-segments` is called

**Logic:**
```csharp
public async Task<TranslationResult> TranslateSegments(
    string userId,
    List<Segment> segments,
    string targetLanguage,
    int durationSeconds,
    string videoFileName)
{
    var user = await GetUserById(userId);
    
    // VIP bypass
    if (user.HasUnlimitedAccess) {
        return await PerformTranslation(segments, targetLanguage);
    }
    
    var durationMinutes = durationSeconds / 60.0;
    
    // Check balance
    if (user.RemainingMinutes < durationMinutes) {
        throw new InsufficientBalanceException();
    }
    
    // Deduct BEFORE translation
    await DeductMinutes(userId, durationMinutes, videoFileName, targetLanguage);
    
    // Perform translation
    var result = await PerformTranslation(segments, targetLanguage);
    
    return result;
}
```

### 3️⃣ Тіл ауыстырып қайта аудару (Re-translate to Different Language)
**Action:** Deduct again (same video, new language)
**Deduction:** ✅ ИӘ (Full video duration again)
**Logic:** Same as Translation Start

**Example:**
```
Video: 2.5 минут
First translation (kk → ru): -2.5 мин
Second translation (ru → en): -2.5 мин
Total used: 5.0 минут
```

### 4️⃣ Видеоны сақтаған кезде (Video Save)
**Action:** No additional deduction
**Deduction:** ЖОҚ
**Logic:** 
- Аудармадан кейін автоматты сақталады
- Қосымша charge жоқ
- Тек статистика жаңартылады

---

## Database Schema

### Users Table
```sql
CREATE TABLE Users (
    Id UNIQUEIDENTIFIER PRIMARY KEY,
    Email NVARCHAR(255),
    SubscriptionType NVARCHAR(50), -- Free, Standard, Pro, VIP
    SubscriptionExpiry DATETIME,
    
    -- Daily limits (set based on tier)
    DailyMinutesLimit DECIMAL(10,2),
    MaxVideoDurationMinutes DECIMAL(10,2),
    HasUnlimitedAccess BIT DEFAULT 0,
    
    -- Current usage
    RemainingMinutes DECIMAL(10,2),
    MinutesUsedToday DECIMAL(10,2),
    LastResetDate DATE,
    
    CreatedAt DATETIME DEFAULT GETDATE()
)
```

### TranslationHistory Table (Tracking)
```sql
CREATE TABLE TranslationHistory (
    Id UNIQUEIDENTIFIER PRIMARY KEY,
    UserId UNIQUEIDENTIFIER,
    VideoFileName NVARCHAR(500),
    VideoHash NVARCHAR(100), -- Same video detection
    
    SourceLanguage NVARCHAR(10),
    TargetLanguage NVARCHAR(10),
    
    DurationSeconds INT,
    DurationMinutes AS (DurationSeconds / 60.0) PERSISTED,
    
    MinutesDeducted DECIMAL(10,2),
    BalanceBefore DECIMAL(10,2),
    BalanceAfter DECIMAL(10,2),
    
    TranslatedAt DATETIME DEFAULT GETDATE(),
    
    INDEX IX_User_Date (UserId, TranslatedAt),
    INDEX IX_VideoHash (VideoHash)
)
```

---

## API Endpoints

### 1. Get User Balance
```
GET /api/TranslationStats/user-balance?search={username}

Response:
{
    "id": "uuid",
    "email": "user@example.com",
    "subscriptionStatus": "Standard",
    "hasUnlimitedAccess": false,
    
    "totalLimit": 10.0,
    "balanceMinutes": 7.5,
    "usedMinutes": 2.5,
    "maxVideoDuration": 600
}
```

### 2. Deduct Minutes (Internal)
```
POST /api/TranslationStats/deduct-minutes

Request:
{
    "userId": "uuid",
    "durationMinutes": 2.5,
    "videoFileName": "video.mp4",
    "targetLanguage": "ru"
}

Response:
{
    "success": true,
    "remainingMinutes": 7.5,
    "usedToday": 2.5
}
```

### 3. Reset Daily Limits (Cron Job)
```
POST /api/admin/reset-daily-limits

Logic:
- Runs daily at 00:00 UTC
- Resets RemainingMinutes = DailyMinutesLimit
- Resets MinutesUsedToday = 0
- Updates LastResetDate = TODAY
- VIP users: RemainingMinutes = 9999999
```

---

## Business Logic

### Daily Reset Algorithm
```csharp
public async Task ResetDailyLimits()
{
    var today = DateTime.UtcNow.Date;
    
    var usersToReset = await db.Users
        .Where(u => u.LastResetDate < today)
        .ToListAsync();
    
    foreach (var user in usersToReset)
    {
        if (user.HasUnlimitedAccess)
        {
            user.RemainingMinutes = 9999999; // VIP
        }
        else
        {
            user.RemainingMinutes = user.DailyMinutesLimit;
        }
        
        user.MinutesUsedToday = 0;
        user.LastResetDate = today;
    }
    
    await db.SaveChangesAsync();
}
```

### Deduct Minutes Algorithm
```csharp
public async Task<DeductionResult> DeductMinutes(
    string userId, 
    double minutes,
    string videoFileName,
    string targetLanguage)
{
    var user = await db.Users.FindAsync(userId);
    
    // VIP check
    if (user.HasUnlimitedAccess)
    {
        // Record for statistics only, don't deduct
        await RecordUsage(userId, minutes, videoFileName, targetLanguage);
        return new DeductionResult { Success = true, Remaining = 9999999 };
    }
    
    // Check if enough balance
    if (user.RemainingMinutes < minutes)
    {
        throw new InsufficientBalanceException();
    }
    
    // Deduct
    var balanceBefore = user.RemainingMinutes;
    user.RemainingMinutes -= minutes;
    user.MinutesUsedToday += minutes;
    
    // Record history
    await db.TranslationHistory.AddAsync(new TranslationHistory
    {
        UserId = userId,
        VideoFileName = videoFileName,
        TargetLanguage = targetLanguage,
        DurationMinutes = minutes,
        BalanceBefore = balanceBefore,
        BalanceAfter = user.RemainingMinutes,
        MinutesDeducted = minutes,
        TranslatedAt = DateTime.UtcNow
    });
    
    await db.SaveChangesAsync();
    
    return new DeductionResult 
    { 
        Success = true, 
        Remaining = user.RemainingMinutes,
        UsedToday = user.MinutesUsedToday
    };
}
```

---

## Frontend Integration

### Client Expectations
```json
{
    "balanceMinutes": 7.5,      // Қалған минуттар (Remaining)
    "usedMinutes": 2.5,         // Бүгін істеткені (Used Today)
    "totalLimit": 10.0,         // Күнделікті лимит
    "hasUnlimitedAccess": false
}
```

### Client Usage Flow
1. Upload video → GET `/api/TranslationStats/user-balance` (check only)
2. Start translation → POST `/api/translation/translate-segments` (auto-deduct)
3. Show dialog → GET `/api/TranslationStats/user-balance` (updated balance)
4. Re-translate → POST `/api/translation/translate-segments` (deduct again)

---

## Error Handling

### Insufficient Balance
```json
{
    "error": "INSUFFICIENT_BALANCE",
    "message": "Жеткіліксіз баланс. Сізде 2.5 мин бар, бірақ 5.0 мин қажет.",
    "requiredMinutes": 5.0,
    "availableMinutes": 2.5,
    "shortfall": 2.5
}
```

### Video Too Long
```json
{
    "error": "VIDEO_TOO_LONG",
    "message": "Видео тым ұзын. Максималды: 10 мин.",
    "videoDuration": 15.5,
    "maxAllowed": 10.0
}
```

---

- **Daily reset** - автоматты, UTC 00:00

---

## ⚠️ Hidden Edge Cases & Solutions (Potentials Risks)

Жүйенің тұрақты жұмыс істеуі үшін мына "жасырын" сценарийлерді ескеру МІНДЕТТІ:

### 1. The "Double Spending" Problem (Қатар аударма)
**Scenario:** Қолданушыда 5 минут бар. Ол бір уақытта (browser tabs) екі 4-минуттық видеоны аударуға жібереді.
**Risk:** Check кезінде екеуінде де `5 > 4` (True) болады, екеуі де өтіп кетеді. Нәтижесінде баланс: `-3` минут (теріс баланс).
**Solution:**
- **Database Transaction (Lock):** Балансты тексерер алдында `ROWLOCK` немесе transaction қолдану керек.
- **Atomic Update:** `UPDATE Users SET RemainingMinutes = RemainingMinutes - @cost WHERE Id = @UserId AND RemainingMinutes >= @cost`
- Егер `RowsAffected == 0` болса -> `InsufficientBalanceException`.

### 2. Failed Translations & Refund Policy (Қайтару)
**Scenario:** Аударма басталды (минуттар алынды), бірақ серверде қате шықты (FFmpeg crash, API timeout).
**Risk:** Қолданушының минуттары күйіп кетеді, нәтиже жоқ.
**Solution:**
- **Refund Logic:** Translation Failed статусы түссе, автоматты түрде минуттарды қайтару.
- **Orchestrator:** `try-catch` блогында Exception ұсталса -> `RefundMinutes(userId, cost)`.

### 3. Subscription Changing Mid-Day (Тариф ауыстыру)
**Scenario:** Қолданушы таңертең Standard (10 мин) болды, 8 минутын жұмсады (Қалды: 2). Түсте Pro (30 мин) тарифке ауысты.
**Risk:** Баланс қалай есептеледі? 30 (жаңа) ма, әлде 30 - 8 = 22 ме?
**Solution:**
- **Upgrade Logic:** `NewRemaining = NewLimit - UsedToday`.
- Егер `UsedToday > NewLimit` болса (бұл downgrade кезінде мүмкін), `NewRemaining = 0`.
- **Reset:** Тариф ауысқан сәтте `UsedToday` өшпеуі керек, тек `Limit` және `Remaining` жаңартылады.

### 4. Timezone Confusion (Уақыт белдеуі)
**Scenario:** Қазақстан уақытымен (UTC+5) түнгі 03:00-де reset болса (UTC 22:00), қолданушылар "ертеңгі лимит келмеді" деп шағымданады.
**Risk:** UX түсініспеушілік.
**Solution:**
- **User Local Time:** Reset logic әрқашан UTC 00:00 болсын (техникалық оңай), бірақ UI-да "Лимит жаңартылады: 05:00" деп көрсету немесе "Used **Today** (UTC)" деп ескерту.
- Немесе әр қолданушының timezone-ына қарай reset job жасау (күрделірек). **Ұсыныс: UTC 00:00 (Қазақстан уақытымен таңғы 06:00/05:00) бекіту.**

### 5. Floating Point Precision (Сандық қателіктер)
**Scenario:** 10.00 минут лимит. 3 рет 3.33333 минуттық видео аударылды.
**Risk:** `10 - 3.33333 - 3.33333 - 3.33333 = 0.00001` қалып қалуы немесе `-0.00001` болуы мүмкін.
**Solution:**
- **Rounding:** Барлық есептеулерді 2 цифрға дейін дөңгелеу (`Math.Round(x, 2)`).
- **Grace Margin:** `0.01` минут айырмашылықты елемеу.

### 6. "Zombie" Jobs (Аяқталмаған процесстер)
**Scenario:** Сервер қайта қосылды (Deploy/Restart). Жүріп жатқан аудармалар үзілді.
**Risk:** Status "Processing" болып тұра береді, минуттар алынған, бірақ refund жоқ.
**Solution:**
- **Timeout Monitor:** Егер Job 30 минуттан артық "Processing" болса -> "Failed" деп белгілеп, автоматты Refund жасау.

### 7. VIP Status Expiry (VIP біткен кезде)
**Scenario:** VIP users unlimited. Жазылым бүгін бітті.
**Risk:** `SubscriptionExpiry` тексерілмей қалса, шексіз қолдана береді.
**Solution:**
- **Check Expiry First:** Әр `TranslateSegments` алдында: `if (HasUnlimited && ExpiryDate < Now) -> Remove VIP, downgrade to Free`.

---

## Updated Database Schema Requirements

Аталған қателіктерді болдырмау үшін DB-ға қосымша өрістер:

```sql
ALTER TABLE TranslationHistory ADD 
    Status NVARCHAR(20) DEFAULT 'Completed', -- 'Completed', 'Failed', 'Refunded'
    ErrorMessage NVARCHAR(MAX) NULL;
```

Updated Transaction Logic (Pseudo-code):
```sql
BEGIN TRANSACTION
    -- 1. Atomic Check & Update
    UPDATE Users 
    SET RemainingMinutes = RemainingMinutes - @Cost,
        MinutesUsedToday = MinutesUsedToday + @Cost
    WHERE Id = @UserId 
      AND (HasUnlimitedAccess = 1 OR RemainingMinutes >= @Cost);

    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK;
        THROW 50001, 'Insufficient Balance', 1;
    END

    -- 2. Log History
    INSERT INTO TranslationHistory (...) VALUES (...);
COMMIT
```

---

## 🧪 Testing Scenarios

### Unit Tests
1. ✅ **Free user:** 1 min limit қатаң сақталады
2. ✅ **Standard user:** First translation (5 min) - balance 10→5
3. ✅ **Standard user:** Re-translate same video (5 min) - balance 5→0
4. ✅ **VIP user:** Unlimited - balance әрқашан 9999999
5. ✅ **Daily reset:** Күн ауысқанда Remaining = Limit
6. ✅ **Upload check:** Insufficient balance блоктайды
7. ✅ **Translation deduction:** Balance дұрыс алынады
8. ✅ **Concurrent requests:** Double spending болмайды (atomic update)
9. ✅ **Failed translation:** Refund автоматты орындалады
10. ✅ **VIP expiry:** Expiry date біткен соң downgrade болады

### Integration Tests
- Backend API → Frontend интеграциясы
- Daily reset cron job тестілеу
- Transaction rollback сценарийлері
- Multi-language translation chain тестілеу

### Load Tests
- 100 қолданушы бір уақытта аударма жіберсе
- Database lock timeout тестілеу
- Reset job performance (10000+ users)

---

## 🔒 Security Considerations

### 1. Rate Limiting (DDoS Protection)
```csharp
[RateLimit(WindowSeconds = 60, MaxRequests = 10)]
public async Task<IActionResult> TranslateSegments(...)
{
    // Max 10 translation requests per user per minute
}
```

### 2. Authorization Checks
```csharp
// CRITICAL: Verify user owns the translation job
if (job.UserId != currentUser.Id && !currentUser.IsAdmin)
{
    throw new UnauthorizedException();
}
```

### 3. Input Validation
- **Video Duration:** MAX 3600 seconds (1 hour) for non-VIP
- **Filename Sanitization:** SQL injection/Path traversal қорғаныс
- **Language Codes:** Whitelist - тек қолдау көрсетілген тілдер

### 4. Audit Logging
```sql
CREATE TABLE AuditLog (
    Id UNIQUEIDENTIFIER PRIMARY KEY,
    UserId UNIQUEIDENTIFIER,
    Action NVARCHAR(50), -- 'DEDUCT', 'REFUND', 'RESET', 'UPGRADE'
    Details NVARCHAR(MAX),
    Timestamp DATETIME DEFAULT GETDATE()
)
```

---

## 📊 Monitoring & Alerts

### Metrics to Track
1. **Daily Active Users (DAU)** - тариф бойынша
2. **Average Minutes Used** - tier-ге қарай
3. **Failed Translations Rate** - refund статистикасы
4. **Concurrent Translation Peak** - сервер capacity
5. **Negative Balance Count** - atomic update қатесі
6. **Reset Job Duration** - performance monitoring

### Critical Alerts
- ⚠️ **Negative Balance Detected** → Immediate investigation
- ⚠️ **Reset Job Failed** → Manual intervention needed
- ⚠️ **Refund Rate > 5%** → Translation service degradation
- ⚠️ **API Response Time > 3s** → Performance issue

### Grafana Dashboard Example
```
┌─────────────────────────────────────────┐
│ Daily Usage by Tier                     │
│ Free:     ████ 25%                      │
│ Standard: ████████ 50%                  │
│ Pro:      ████ 20%                      │
│ VIP:      ██ 5%                         │
└─────────────────────────────────────────┘
```

---

## ⚡ Performance Requirements (SLA)

### API Response Times
- `/api/translation/translate-segments`: < 2s (p95)
- `/api/TranslationStats/user-balance`: < 500ms (p95)
- Daily reset job: < 5 minutes (for 100k users)

### Database Indexes (Performance)
```sql
-- Critical for fast balance checks
CREATE INDEX IX_Users_Balance ON Users(Id, RemainingMinutes, HasUnlimitedAccess);

-- Critical for daily reset
CREATE INDEX IX_Users_LastReset ON Users(LastResetDate) WHERE LastResetDate IS NOT NULL;

-- Critical for user analytics
CREATE INDEX IX_TransHistory_User_Date ON TranslationHistory(UserId, TranslatedAt DESC);
```

---

## 🔄 Migration Plan (Existing Users)

### Step 1: Add New Columns
```sql
ALTER TABLE Users ADD 
    DailyMinutesLimit DECIMAL(10,2) DEFAULT 10.0,
    RemainingMinutes DECIMAL(10,2) DEFAULT 10.0,
    MinutesUsedToday DECIMAL(10,2) DEFAULT 0.0,
    LastResetDate DATE DEFAULT CAST(GETDATE() AS DATE);
```

### Step 2: Migrate Existing Users
```sql
UPDATE Users SET 
    DailyMinutesLimit = CASE 
        WHEN SubscriptionType = 'Free' THEN 1.0
        WHEN SubscriptionType = 'Standard' THEN 10.0
        WHEN SubscriptionType = 'Pro' THEN 30.0
        WHEN SubscriptionType = 'VIP' THEN 9999999.0
        ELSE 1.0
    END,
    RemainingMinutes = DailyMinutesLimit,
    MinutesUsedToday = 0.0,
    LastResetDate = CAST(GETDATE() AS DATE);
```

### Step 3: Backfill History (Optional)
```sql
-- Populate TranslationHistory from old logs if available
INSERT INTO TranslationHistory (UserId, DurationMinutes, TranslatedAt, Status)
SELECT UserId, Duration, CreatedAt, 'Completed'
FROM OldTranslationLogs
WHERE CreatedAt >= DATEADD(DAY, -30, GETDATE()); -- Last 30 days
```

### Step 4: Enable Enforcement
```csharp
// Feature flag
public static bool UsageLimitsEnabled = true; // Enable after migration
```

---

## 💰 Cost Calculation Examples

### Example 1: Standard User
```
Day 1:
  - Upload 5 min video → Check: 5 < 10 ✅
  - Translate to Russian → Deduct: 10 - 5 = 5 min remaining
  - Translate to English → Deduct: 5 - 5 = 0 min remaining
  - Try translate to Turkish → Error: Insufficient balance ❌

Day 2 (after reset):
  - Balance reset to 10 min ✅
```

### Example 2: Pro User with Upgrade
```
Morning (Standard, 10 min limit):
  - Translate 8 min video → 10 - 8 = 2 min remaining

Afternoon (Upgrade to Pro):
  - New limit: 30 min
  - Used today: 8 min
  - New remaining: 30 - 8 = 22 min ✅
```

### Example 3: VIP User
```
Unlimited translations:
  - Translate 50 videos (total 200 min)
  - Balance: 9999999 → 9999999 (no change)
  - Stats recorded for analytics only
```

---

## 📝 Notes & Best Practices

- **Video duration екі рет charge жасамаймыз** (upload кезінде емес, тек translation кезінде)
- **Әр тілге аудару жеке charge** (2.5 мин видеоны 3 тілге аударса = 7.5 мин total)
- **VIP-тер шексіз**, бірақ статистика жазылады
- **Daily reset** - автоматты, UTC 00:00
- **Atomic operations** - critical балансқа race condition болмауы үшін
- **Always refund on failure** - қолданушы тәжірибесі маңызды
- **Monitor everything** - метрика жоқ болса, optimize ете алмайсыз
- **Test migrations** - production-ға deploy алдында staging-те тестілеңіз

---

## 🚀 Deployment Checklist

- [ ] Database schema жаңартылды
- [ ] Migration scripts тестіленді
- [ ] Indexes қосылды
- [ ] Cron job (daily reset) орнатылды
- [ ] Monitoring/alerts бапталды
- [ ] API endpoints тестіленді
- [ ] Frontend интеграциясы дайын
- [ ] Error handling толық
- [ ] Security audit өтті
- [ ] Load testing өтті
- [ ] Documentation жаңартылды
- [ ] Rollback plan дайын

---

**© 2026 Qaznat PolyDub - Usage Limits Specification v1.0**
