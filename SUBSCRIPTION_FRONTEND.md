# Subscription System - Frontend Documentation

Бұл құжат QazNat VT қосымшасындағы жазылым (subscription) жүйесінің frontend бөлігін сипаттайды.

## 🏗 Архитектура

Жүйе 3 негізгі қабаттан тұрады:
1.  **UI Layer**: Экрандар мен компоненттер (`SubscriptionScreen`, `SubscriptionCard`)
2.  **Routing Layer**: Платформаға байланысты логиканы басқару (`PlatformPaymentRouter`)
3.  **Service Layer**: Сыртқы жүйелермен байланыс (`IAPService`, `SubscriptionApiService`)

---

## 🛠 Services

### 1. PlatformPaymentRouter
**Орналасқан жері:** `lib/services/platform_payment_router.dart`

Бұл сервис барлық төлем операцияларының орталық нүктесі болып табылады. Ол қосымшаның қай платформада (iOS, Android, Web) жұмыс істеп тұрғанын анықтап, сәйкес сервиске жүгінеді.

*   **Міндеті:** UI-ды платформалық ерекшеліктерден оқшаулау.
*   **Басты әдістері:**
    *   `getSubscriptionPlans()`: Бағаларды алу (Алдымен Backend, болмаса Store).
    *   `subscribe(planId)`: Сатып алу процесін бастау.
    *   `restorePurchases()`: Бұрынғы сатып алуларды қалпына келтіру.

### 2. SubscriptionApiService
**Орналасқан жері:** `lib/services/subscription_api_service.dart`

Backend сервермен тікелей байланысатын сервис.

*   **Міндеті:**
    *   Жазылым жоспарларын және бағаларын серверден алу (`getProducts`).
    *   App Store (iOS) чектерін серверге тексеруге жіберу (`verifyAppleReceipt`).
    *   Google Play (Android) сатып алуларын серверге тексеруге жіберу (`verifyGooglePurchase`).
    *   Ағымдағы жазылым статусын тексеру.

### 3. IAPService
**Орналасқан жері:** `lib/services/iap_service.dart`

Сторлармен (Apple App Store, Google Play Store) жұмыс істейтін төменгі деңгейлі сервис. `in_app_purchase` пакетін қолданады.

*   **Міндеті:**
    *   Стордан өнімдерді жүктеу.
    *   Сатып алу интерфейсін шақыру (FaceID/TouchID/Google Pay).
    *   Сатып алу сәтті өткенде receipt/token алу.

---

## 🎨 UI Компоненттері

### SubscriptionScreen
**Орналасқан жері:** `lib/screens/subscription_screen.dart`

Пайдаланушыға жазылым жоспарларын көрсететін негізгі экран.
*   Backend-тен келген деректерді көрсетеді.
*   Loading, Error және Success күйлерін басқарады.
*   Design: Premium gradients, modern cards.

### SubscriptionCard
**Орналасқан жері:** `lib/widgets/subscription_card.dart`

Жазылым карточкасының дизайны.
*   **Standard**: Orange/Yellow gradient.
*   **Pro**: Blue gradient + "RECOMMENDED" badge.
*   **VIP**: Pink/Purple gradient.

---

## 🔄 Жұмыс процесі (Flows)

### 1. Өнімдерді жүктеу (Load Products)
UI ашылғанда `PlatformPaymentRouter.getSubscriptionPlans()` шақырылады:
1.  **Backend Call**: `/api/subscription/products` арқылы соңғы бағаларды сұрайды.
2.  **IAP Sync**: Егер платформа iOS немесе Android болса, фондық режимде стордан өнімдерді жүктеп қояды (сатып алуға дайын болу үшін).
3.  **Mapping**: Backend ID-ларын Store Product ID-ларымен сәйкестендіреді.
4.  **Fallback**: Егер backend жауап бермесе, стордан алынған деректерді көрсетеді.

### 2. Сатып алу (Purchase Flow)
Пайдаланушы "Subscribe" батырмасын басқанда:
1.  `PlatformPaymentRouter.subscribe()` шақырылады.
2.  `IAPService.purchaseSubscription(productId)` стордың төлем терезесін ашады.
3.  Пайдаланушы төлемді растайды (FaceID/Password).
4.  Стор сәтті төлем туралы жауап қайтарады.
5.  **Верификация**:
    *   **iOS**: `receiptData` алынып, `SubscriptionApiService.verifyAppleReceipt()` арқылы backend-ке жіберіледі.
    *   **Android**: `purchaseToken` алынып, `SubscriptionApiService.verifyGooglePurchase()` арқылы backend-ке жіберіледі.
6.  Сервер растаған соң, UI жаңартылып, жазылым белсендіріледі.

---

## ⚙️ Конфигурация (Config)

**Файл:** `lib/config/iap_config.dart`

Мұнда Product ID-лар сақталады. Бұлар App Store Connect және Google Play Console-мен дәлме-дәл сәйкес келуі керек.

```dart
// iOS
static const String iosProductIdStandard = 'com.qaznat.vt.subscription.standard';
static const String iosProductIdPro = 'com.qaznat.vt.subscription.pro';
...

// Android
static const String androidProductIdStandard = 'qaznat_vt_standard_monthly';
static const String androidProductIdPro = 'qaznat_vt_pro_monthly';
...
```

## 🚀 Жаңа өнім қосу қадамдары
1.  App Store Connect / Google Play Console-да жаңа Product ID жасау.
2.  Backend дерекқорға жаңа жоспарды қосу.
3.  `lib/config/iap_config.dart` ішіне жаңа ID қосу.
4.  `lib/widgets/subscription_card.dart` ішінде жаңа дизайн (түс) қосу (қажет болса).
