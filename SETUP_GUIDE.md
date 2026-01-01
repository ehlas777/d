# QazNat VT - Орнату нұсқаулығы

## 🚀 Жылдам бастау

### 1. Dependencies орнату

```bash
cd qaznat_vt
flutter pub get
```

### 2. macOS Permissions (міндетті!)

macOS-те файл таңдау үшін sandboxing permissions қажет. Мен оларды қазірдің өзінде қостым:

- ✅ `com.apple.security.files.user-selected.read-write` - Файл таңдау/жүктеу
- ✅ `com.apple.security.network.client` - API шақыруға рұқсат

Файлдар:
- `macos/Runner/DebugProfile.entitlements`
- `macos/Runner/Release.entitlements`

### 3. Қолданбаны іске қосу

```bash
# macOS
flutter run -d macos

# Web (permissions жоқ, бірақ жұмыс істейді)
flutter run -d chrome

# iOS/Android
flutter run -d ios  # немесе android
```

### 4. Release build

```bash
# macOS
flutter build macos --release

# Web
flutter build web --release
```

## 📱 Платформа бойынша ерекшеліктер

### macOS
✅ Толық қолдау
✅ File picker жұмыс істейді
✅ Video preview жұмыс істейді
⚠️ Permissions қосылған (entitlements файлдарында)

### Web
✅ UI толық жұмыс істейді
✅ File picker жұмыс істейді (браузер диалогы)
⚠️ Video preview шектеулі (codec қолдауына байланысты)
⚠️ CORS үшін backend қажет

### iOS
✅ Толық қолдау
⚠️ Info.plist-ке permissions қосу керек:
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Видео таңдау үшін</string>
<key>NSCameraUsageDescription</key>
<string>Видео жазу үшін</string>
```

### Android
✅ Толық қолдау
⚠️ AndroidManifest.xml-ге permissions қосу керек:
```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

## 🔧 Backend қосу

### 1. Backend URL өзгерту

`lib/services/transcription_service.dart`:

```dart
static const String baseUrl = 'https://your-api.com/api';
```

### 2. Backend құру

Толық нұсқаулық: [`WHISPER_PROMPT.md`](WHISPER_PROMPT.md)

Қысқа:

```python
# FastAPI мысалы
@app.post("/api/transcribe")
async def transcribe_video(file: UploadFile, options: str):
    # 1. Видеоны сақтау
    # 2. ffmpeg арқылы аудио шығару
    # 3. Whisper API шақыру
    # 4. JSON форматтау
    # 5. Job ID қайтару
    return {"job_id": "uuid"}
```

### 3. CORS қосу (Web үшін)

```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
```

## 🐛 Жиі кездесетін мәселелер

### "Видео таңдау жұмыс істемейді" (macOS)

**Себебі**: Entitlements permissions жоқ

**Шешім**:
```bash
# Permissions тексеру
cat macos/Runner/DebugProfile.entitlements

# Қайта құрастыру
flutter clean
flutter pub get
flutter run -d macos
```

Міндетті болуы керек:
```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
```

### "Network request failed"

**Себебі**: Backend іске қосылмаған немесе CORS қатесі

**Шешім**:
1. Backend іске қосылғанын тексеру
2. URL дұрыстығын тексеру
3. CORS қосу (Web үшін)

### "Video preview жұмыс істемейді"

**Себебі**: Codec қолдауы жоқ (әсіресе Web-те)

**Шешім**:
- macOS/iOS/Android: Барлық форматтар жұмыс істейді
- Web: H.264 (MP4) қолданыңыз

### "Локализация көрінбейді"

**Себебі**: Provider орнатылмаған

**Шешім**: `main.dart`-та `ChangeNotifierProvider` бар екенін тексеру

## 📦 Production Build

### macOS

```bash
flutter build macos --release

# App орналасуы:
# build/macos/Build/Products/Release/qaznat_vt.app
```

### Web

```bash
flutter build web --release --web-renderer canvaskit

# Файлдар орналасуы:
# build/web/
```

### iOS

```bash
flutter build ios --release

# Xcode-пен ашып App Store-ға жіберу
open ios/Runner.xcworkspace
```

### Android

```bash
flutter build apk --release

# APK орналасуы:
# build/app/outputs/flutter-apk/app-release.apk
```

## 🧪 Тестілеу

```bash
# Код анализі
flutter analyze

# Unit тесттер
flutter test

# Барлығын бірден
flutter analyze && flutter test
```

## 📊 Performance оптимизациясы

### Flutter build режимдері:

```bash
# Debug (hot reload)
flutter run -d macos

# Profile (performance profiling)
flutter run -d macos --profile

# Release (production)
flutter run -d macos --release
```

### Web оптимизация:

```bash
# CanvasKit (жақсы performance)
flutter build web --release --web-renderer canvaskit

# HTML (кішірек өлшем)
flutter build web --release --web-renderer html
```

## 🔐 Қауіпсіздік

### API Key сақтау

Production-да environment variables қолданыңыз:

```dart
// lib/config/api_config.dart
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8000/api',
  );

  static const String apiKey = String.fromEnvironment(
    'API_KEY',
    defaultValue: '',
  );
}
```

Build:
```bash
flutter build macos --release \
  --dart-define=API_URL=https://your-api.com \
  --dart-define=API_KEY=your_secret_key
```

## 📚 Қосымша ресурстар

- [Flutter Documentation](https://docs.flutter.dev/)
- [Whisper API Docs](https://platform.openai.com/docs/guides/speech-to-text)
- [file_picker plugin](https://pub.dev/packages/file_picker)
- [video_player plugin](https://pub.dev/packages/video_player)

## 💡 Tips

1. **Hot reload**: `r` батырмасы (debug mode-та)
2. **Hot restart**: `R` батырмасы
3. **DevTools ашу**: `flutter run` кезінде URL көрсетіледі
4. **Logs көру**: Console-да барлық print() көрсетіледі
5. **Performance профильдеу**: `flutter run --profile` + DevTools

---

Сұрақтар туындаса issue ашыңыз! 🚀
