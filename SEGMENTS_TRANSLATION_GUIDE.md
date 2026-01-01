# Segments Translation API - Пайдалану Нұсқаулығы

## 🎯 Мақсаты

JSON segments-терді (мысалы, SRT субтитрлер) аударғанда:
- ✅ JSON құрылымы сақталады
- ✅ Жолдар саны өзгермейді
- ✅ Әр segment өз ID-мен қайтады
- ✅ Бір Gemini запросымен барлығы аударылады (арзан!)

---

## 📋 API Endpoint

```
POST /api/translation/translate-segments
Authorization: Bearer YOUR_JWT_TOKEN
```

---

## 🚀 Flutter Пайдалану

### 1. JSON-ды Segments-ке Түрлендіру

```dart
import 'dart:convert';
import 'package:your_app/models/translation_models.dart';
import 'package:your_app/services/backend_translation_service.dart';

// JSON файлды оқу
final jsonString = await File('path/to/segments.json').readAsString();
final jsonData = jsonDecode(jsonString);

// Segments-ке түрлендіру
final segments = <TranslationSegment>[];
int index = 0;

for (var segment in jsonData['segments']) {
  segments.add(TranslationSegment(
    id: 'segment_$index',  // немесе segment['start'].toString()
    text: segment['text'],
  ));
  index++;
}

debugPrint('Prepared ${segments.length} segments for translation');
```

### 2. Аударма Жасау

```dart
final translationService = BackendTranslationService(apiClient);

final result = await translationService.translateSegments(
  segments: segments,
  targetLanguage: 'zh',  // zh, ru, en, kk
  sourceLanguage: 'kk',  // optional
  durationSeconds: 87,   // видео ұзақтығы
  videoFileName: 'video.mp4',  // optional
);

if (result.success) {
  debugPrint('✅ Translation successful!');
  debugPrint('Translated ${result.translatedSegments.length} segments');
  debugPrint('Price: ${result.price} ${result.currency}');

  // Validation
  if (result.hasLineCountMismatch) {
    debugPrint('⚠️ ${result.validationWarning}');
  }
} else {
  debugPrint('❌ Translation failed: ${result.errorMessage}');
}
```

### 3. JSON-ға Қайта Қою

```dart
// Original JSON-ды update ету
for (var translatedSegment in result.translatedSegments) {
  // ID бойынша табу
  final index = int.parse(translatedSegment.id.replaceAll('segment_', ''));

  // JSON-ға қою
  jsonData['segments'][index]['translatedText'] = translatedSegment.translatedText;
  jsonData['segments'][index]['targetLanguage'] = result.targetLanguage;
}

// Файлға жазу
final updatedJson = jsonEncode(jsonData);
await File('path/to/translated_segments.json').writeAsString(updatedJson);

debugPrint('✅ Translated JSON saved!');
```

---

## 💡 Толық Мысал

```dart
Future<void> translateVideoSegments(String jsonFilePath, String targetLanguage) async {
  try {
    // 1. JSON оқу
    final jsonString = await File(jsonFilePath).readAsString();
    final jsonData = jsonDecode(jsonString);

    // 2. Segments дайындау
    final segments = <TranslationSegment>[];
    for (int i = 0; i < jsonData['segments'].length; i++) {
      segments.add(TranslationSegment(
        id: 'segment_$i',
        text: jsonData['segments'][i]['text'],
      ));
    }

    debugPrint('📝 Prepared ${segments.length} segments');

    // 3. Аударма
    final result = await translationService.translateSegments(
      segments: segments,
      targetLanguage: targetLanguage,
      durationSeconds: (jsonData['duration'] as num).toInt(),
      videoFileName: jsonData['filename'],
    );

    if (!result.success) {
      throw Exception('Translation failed: ${result.errorMessage}');
    }

    // 4. JSON update
    for (var translated in result.translatedSegments) {
      final index = int.parse(translated.id.replaceAll('segment_', ''));
      jsonData['segments'][index]['translatedText'] = translated.translatedText;
      jsonData['segments'][index]['targetLanguage'] = targetLanguage;
    }

    // 5. Сақтау
    final outputPath = jsonFilePath.replaceAll('.json', '_translated.json');
    await File(outputPath).writeAsString(jsonEncode(jsonData));

    debugPrint('✅ Success! Saved to: $outputPath');
    debugPrint('💰 Price: ${result.price} ${result.currency}');

  } catch (e) {
    debugPrint('❌ Error: $e');
    rethrow;
  }
}

// Пайдалану
await translateVideoSegments(
  '/path/to/video_segments.json',
  'zh',  // қытайшаға аудару
);
```

---

## 📊 Request/Response Форматтары

### Request

```json
{
  "segments": [
    {
      "id": "segment_0",
      "text": "Біреуді батпаққа батырудың ең қатыгез әдісі қандай?"
    },
    {
      "id": "segment_1",
      "text": "Бірінші оқиға"
    }
  ],
  "targetLanguage": "zh",
  "sourceLanguage": "kk",
  "durationSeconds": 87,
  "videoFileName": "video.mp4"
}
```

### Response

```json
{
  "success": true,
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "translatedSegments": [
    {
      "id": "segment_0",
      "originalText": "Біреуді батпаққа батырудың ең қатыгез әдісі қандай?",
      "translatedText": "拉别人下水最狠辣的手段是什么"
    },
    {
      "id": "segment_1",
      "originalText": "Бірінші оқиға",
      "translatedText": "故事一"
    }
  ],
  "sourceLanguage": "kk",
  "targetLanguage": "zh",
  "price": 8.70,
  "currency": "KZT",
  "inputLineCount": 2,
  "outputLineCount": 2,
  "message": "Segments translated successfully",
  "errorMessage": null
}
```

---

## ⚠️ Шектеулер

| Параметр | Шек |
|----------|-----|
| Max segments | 500 |
| Min segments | 1 |
| Duration | > 0 seconds |
| Text length | Шексіз (бірақ Gemini limit бар) |

---

## 🎯 Best Practices

### 1. Batch өлшемін оптимизациялау

```dart
const int BATCH_SIZE = 100;  // 100 segments бір уақытта

Future<void> translateLargeSegments(List<Segment> allSegments) async {
  for (int i = 0; i < allSegments.length; i += BATCH_SIZE) {
    final batch = allSegments.skip(i).take(BATCH_SIZE).toList();

    final segments = batch.map((s) => TranslationSegment(
      id: 'segment_${s.index}',
      text: s.text,
    )).toList();

    final result = await translationService.translateSegments(
      segments: segments,
      targetLanguage: 'zh',
      durationSeconds: videoDuration,
    );

    // Process result...
    await Future.delayed(Duration(seconds: 1));  // Rate limiting
  }
}
```

### 2. Error Handling

```dart
try {
  final result = await translationService.translateSegments(...);

  if (!result.success) {
    // Қате өңдеу
    showErrorDialog(result.errorMessage ?? 'Unknown error');
    return;
  }

  if (result.hasLineCountMismatch) {
    // Warning көрсету
    showWarningDialog(result.validationWarning!);
  }

  // Success
  processTranslatedSegments(result.translatedSegments);

} catch (e) {
  // Network қатесі
  showErrorDialog('Network error: $e');
}
```

### 3. Progress Tracking

```dart
StreamController<double> progressController = StreamController<double>();

Future<void> translateWithProgress(List<TranslationSegment> segments) async {
  progressController.add(0.0);

  final result = await translationService.translateSegments(
    segments: segments,
    targetLanguage: 'zh',
    durationSeconds: 87,
  );

  progressController.add(1.0);

  if (result.success) {
    debugPrint('✅ Done!');
  }
}

// UI-да
StreamBuilder<double>(
  stream: progressController.stream,
  builder: (context, snapshot) {
    return LinearProgressIndicator(value: snapshot.data ?? 0.0);
  },
);
```

---

## 🔍 Қателерді Шешу

### Қате: "Maximum 500 segments allowed"

**Себебі:** 500-ден көп segment жіберілді

**Шешім:**
```dart
if (segments.length > 500) {
  // Batch-терге бөлу
  final batches = <List<TranslationSegment>>[];
  for (int i = 0; i < segments.length; i += 500) {
    batches.add(segments.skip(i).take(500).toList());
  }

  for (var batch in batches) {
    await translateSegments(segments: batch, ...);
  }
}
```

### Қате: "Segments саны сәйкес емес"

**Себебі:** Gemini жолдарды біріктірді немесе бөлді

**Шешім:**
1. Backend логтарын тексеріңіз
2. Промптті қайта қараңыз
3. Backend-ті қайта іске қосыңыз

---

## 📞 Support

Сұрақтарыңыз болса:
- Backend логтары: `dotnet run` терезесінде
- Flutter логтары: `flutter run` терезесінде

---

## ✨ Қорытынды

Енді сіз JSON segments-терді:
- ✅ Құрылымын сақтап
- ✅ Жолдар санын сақтап
- ✅ Бір запроспен
- ✅ ID-мен сәйкестендіріп

Аудара аласыз! 🚀
