# StoreKit IAP Тестілеу Нұсқаулығы

## 🎯 Мақсат

QazNat VT қосымшасында StoreKit (In-App Purchase) интеграциясын тестілеу.

---

## 📋 Алдын-ала талаптар

### 1. App Store Connect конфигурациясы

#### Product ID-лар таңдалған:
- **Standard**: `com.qaznat.vt.subscription.standard`
- **Pro**: `com.qaznat.vt.subscription.pro`
- **VIP**: `com.qaznat.vt.subscription.vip`

#### App Store Connect-те өнімдер құру:

1. **App Store Connect**-ке кіріңіз → **My Apps** → **QazNat VT**
2. **Features** → **Subscriptions** → **Create Subscription Group**
   - Group Name: `QazNat VT Subscriptions`
   - Group ID: `com.qaznat.vt.subscriptions`

3. Әрбір тарифке жаңа subscription жасаңыз:

**Standard Subscription:**
```
Reference Name: Standard Monthly
Product ID: com.qaznat.vt.subscription.standard
Subscription Duration: 1 Month
Price: $4.99 (ААҚ немесе өзіңіздің нарыққа сәйкес)
Localization:
  - Display Name (en): Standard
  - Description (en): Basic video translation features
  - Display Name (kk): Стандарт
  - Description (kk): Бейне аудармаға арналған базалық мүмкіндіктер
```

**Pro Subscription:**
```
Reference Name: Pro Monthly
Product ID: com.qaznat.vt.subscription.pro
Subscription Duration: 1 Month
Price: $9.99
Localization:
  - Display Name (en): Pro
  - Description (en): Advanced translation with priority support
  - Display Name (kk): Pro
  - Description (kk): Кеңейтілген аударма және басымды қолдау
```

**VIP Subscription:**
```
Reference Name: VIP Monthly
Product ID: com.qaznat.vt.subscription.vip
Subscription Duration: 1 Month
Price: $19.99
Localization:
  - Display Name (en): VIP
  - Description (en): Unlimited translation with premium support
  - Display Name (kk): VIP
  - Description (kk): Шексіз аударма және премиум қолдау
```

4. **Review Information** бөлімін толтырыңыз және **Submit for Review** басыңыз (тек production үшін).

---

## 🧪 Тестілеу әдістері

### Әдіс 1: StoreKit Configuration File (Ұсынылады - тез және оңай)

Бұл әдіс **Xcode-та** StoreKit файлын құрып, нақты App Store Connect-ке жүгінбей-ақ тестілеуге мүмкіндік береді.

#### 1.1 Configuration File жасау

1. Xcode-да: **File** → **New** → **File**
2. **StoreKit Configuration File** таңдаңыз
3. Аты: `StoreKitConfiguration.storekit`
4. Орналасуы: `ios/` немесе түбірлік директория

#### 1.2 Өнімдерді қосу

`StoreKitConfiguration.storekit` файлын ашып, төмендегі өнімдерді қосыңыз:

**Add Subscription Group:**
- Group Name: `QazNat VT Subscriptions`

**Add 3 subscriptions:**

1. **Standard**
   - Product ID: `com.qaznat.vt.subscription.standard`
   - Reference Name: `Standard Monthly`
   - Price: `$4.99` (USD)
   - Subscription Duration: `1 Month`
   - Localizations:
     - English: "Standard" / "Basic video translation features"
     - Kazakh: "Стандарт" / "Бейне аудармаға арналған базалық мүмкіндіктер"

2. **Pro**
   - Product ID: `com.qaznat.vt.subscription.pro`
   - Reference Name: `Pro Monthly`
   - Price: `$9.99`
   - Duration: `1 Month`

3. **VIP**
   - Product ID: `com.qaznat.vt.subscription.vip`
   - Reference Name: `VIP Monthly`
   - Price: `$19.99`
   - Duration: `1 Month`

#### 1.3 Simulator-да тестілеу

1. **Xcode → Product → Scheme → Edit Scheme** ашыңыз
2. **Run** → **Options** табын ашыңыз
3. **StoreKit Configuration** → `StoreKitConfiguration.storekit` таңдаңыз
4. Simulator немесе құрылғыда run жасаңыз

**Артықшылықтары:**
- ✅ Sandbox аккаунт керек емес
- ✅ Instant тестілеу
- ✅ App Store Connect-ке өнім қосудың қажеті жоқ
- ✅ Transaction Manager арқылы purchase-тарды басқаруға болады

**Transaction Manager (Debug):**
- Xcode → **Debug** → **StoreKit** → **Manage Transactions**
- Мұнда сіз барлық сатып алуларды көре аласыз және оларды Refund/Delete жасай аласыз

---

### Әдіс 2: Sandbox Testing (Нақты App Store сценариясы)

#### 2.1 Sandbox аккаунт жасау

1. **App Store Connect** → **Users and Access** → **Sandbox Testers** → **+**
2. Жаңа sandbox email құрыңыз (мысалы: `test@qaznat.kz`)
3. Құпия сөз орнатыңыз

> ⚠️ **МАҢЫЗДЫ**: Бұл email нағыз Apple ID-мен қолданылмауы керек!

#### 2.2 Құрылғыны конфигурациялау

**iOS құрылғысында:**
1. **Settings** → **App Store** → **Sandbox Account** → sandbox email енгізіңіз

**macOS-та:**
1. **System Preferences** → **App Store** → Sign Out (егер production account болса)
2. Қосымшаны іске қосыңыз, сатып алу сұранысы келгенде sandbox email енгізіңіз

#### 2.3 Тестілеу

1. Қосымшаны run жасаңыз (физикалық құрылғы немесе simulator)
2. Subscription Screen ашыңыз
3. Кез-келген тарифті таңдап "Subscribe" басыңыз
4. Sandbox аккаунтымен кіріңіз
5. **Сатып алуды растаңыз** (төлем алынбайды, бұл sandbox!)

**Sandbox ерекшеліктері:**
- 💳 Нақты төлем жоқ
- ⏱ Subscription duration жылдамдатылған:
  - 1 ай → 5 минут
  - 1 жыл → 1 сағат
- 🔄 Auto-renewal 6 рет қайталанады

---

## 🔍 Тестілеу сценарийлері

### Сценарий 1: Жаңа сатып алу (New Purchase)

**Қадамдар:**
1. ✅ Қосымшаны іске қосыңыз
2. ✅ Subscription Screen ашыңыз → 3 тариф көрініс табуы керек
3. ✅ "Pro" тарифін таңдаңыз
4. ✅ "Subscribe" батырмасын басыңыз
5. ✅ StoreKit төлем диалогы шығуы керек
6. ✅ Face ID / Password растау
7. ✅ Сәтті сатып алу туралы хабарлама

**Күтілетін нәтиже:**
- Console логында: `✅ Purchase verified: com.qaznat.vt.subscription.pro`
- Backend-ке verification сұранысы жіберілуі керек

### Сценарий 2: Қайтадан жүктеу (Restore Purchases)

**Қадамдар:**
1. ✅ Бұрын сатып алған subscription бар екеніне көз жеткізіңіз
2. ✅ Subscription Screen → "Restore Purchases" басыңыз
3. ✅ Сәтті қалпына келтіру хабарламасы

**Күтілетін нәтиже:**
- Бұрынғы subscription белсендіріледі
- Console логында: `Purchase update: ... - restored`

### Сценарий 3: Бірнеше subscription-дар (Multiple Tiers)

**Қадамдар:**
1. ✅ Standard сатып алыңыз
2. ✅ Pro-ға upgrade жасаңыз
3. ✅ Қызмет Standard-тан Pro-ға ауысуы керек

**Күтілетін нәтиже:**
- StoreKit автоматты түрде төменгі тарифті өшіріп, жоғарыға ауыстырады

### Сценарий 4: Қателер (Error Handling)

**Қадамдар:**
1. ✅ Төлем кезінде "Cancel" басыңыз
2. ✅ Интернет байланысты өшіріп, сатып алуға тырысыңыз

**Күтілетін нәтиже:**
- Қателер дұрыс өңделуі керек
- Pending күйлер көрсетілуі керек
- Пайдаланушыға түсінікті хабарламалар

---

## 🐛 Debug логтары

### Қалыпты жағдай (Success Flow):

```
IAP Service initializing for ios...
Loading products for ios...
Product IDs: [com.qaznat.vt.subscription.standard, com.qaznat.vt.subscription.pro, com.qaznat.vt.subscription.vip]
Loaded 3 products
  - com.qaznat.vt.subscription.standard: Standard (4,99 $)
  - com.qaznat.vt.subscription.pro: Pro (9,99 $)
  - com.qaznat.vt.subscription.vip: VIP (19,99 $)
Purchasing subscription: com.qaznat.vt.subscription.pro
Purchase update: com.qaznat.vt.subscription.pro - purchased
Verifying Apple receipt...
✅ Purchase verified: com.qaznat.vt.subscription.pro
Purchase completed: com.qaznat.vt.subscription.pro
```

### Қателер (Errors):

**Өнім табылмаған:**
```
Products not found: [com.qaznat.vt.subscription.pro]
```
👉 **Шешім**: App Store Connect-те Product ID дұрыс екенін тексеріңіз

**IAP қолжетімсіз:**
```
In-App Purchase is not available on this platform
```
👉 **Шешім**: Simulator-да StoreKit Configuration қосылғанын тексеріңіз немесе нақты құрылғыда sandbox аккаунт қосылғанын тексеріңіз

**Verification failed:**
```
❌ Purchase verification failed: com.qaznat.vt.subscription.pro
```
👉 **Шешім**: Backend API `/api/subscription/verify-apple` endpoint-і жұмыс істейтініне көз жеткізіңіз

---

## 📱 macOS-қа арналған ерекше конфигурация

macOS қосымшасында IAP жұмыс істеуі үшін:

### 1. Entitlements файлын тексеру

`macos/Runner/Runner.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <!-- IAP үшін керек -->
    <key>com.apple.security.in-app-purchase</key>
    <true/>
</dict>
</plist>
```

### 2. Signing конфигурациясы

Xcode-да `macos/Runner.xcodeproj` ашып:
1. **Signing & Capabilities** табын ашыңыз
2. **+ Capability** → **In-App Purchase** қосыңыз
3. Team-ді таңдаңыз

---

## ✅ Тестілеу Checklist

- [ ] StoreKit Configuration file құрылды
- [ ] 3 subscription өнімі қосылды (Standard, Pro, VIP)
- [ ] Xcode Scheme-де StoreKit configuration белсендіріледі
- [ ] Қосымшаны run жасағанда өнімдер жүктеледі
- [ ] Сатып алу процесі жұмыс істейді
- [ ] Purchase verification backend-пен байланысады
- [ ] Restore Purchases жұмыс істейді
- [ ] Қателер дұрыс өңделеді
- [ ] macOS entitlements конфигурацияланды

---

## 🚀 Келесі қадамдар

1. ✅ StoreKit Configuration file жасау (төменде қараңыз)
2. ✅ Локальда тестілеу
3. ⏭ Backend verification endpoint жасау (қажет болса)
4. ⏭ Production-ға өнімдерді App Store Connect-те құру
5. ⏭ TestFlight арқылы beta тестілеу

---

## 📞 Көмек керек болса

**StoreKit қателері:**
- [Apple StoreKit Documentation](https://developer.apple.com/documentation/storekit)
- [Testing In-App Purchases](https://developer.apple.com/documentation/storekit/in-app_purchase/testing_in-app_purchases)

**Flutter IAP plugin:**
- [in_app_purchase package](https://pub.dev/packages/in_app_purchase)

---

**Сәттілік тілеймін! 🎉**
