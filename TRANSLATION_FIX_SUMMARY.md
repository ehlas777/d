# Аударма API Жолдар Санын Сақтау - Өзгерістер

## 📋 Мәселе

Аударма API жұмыс істегенде:
- Кіріс жолдар саны мен шығыс жолдар саны сәйкес келмейді
- SRT субтитрлер форматы бұзылады
- JSON құрылымы өзгеріп кетеді
- `\n` символдары дұрыс сақталмайды

## ✅ Жасалған Өзгерістер

### 1. Backend Өзгерістері (oz_api-main)

#### a) GeminiTranslationService.cs
**Файл:** `/Services/GeminiTranslationService.cs`

**Өзгерістер:**
- ✅ Промптті толығымен қайта жазылды
- ✅ Жолдар санын қатаң сақтау талабы қосылды
- ✅ Line-by-line аударма нұсқаулары
- ✅ JSON форматын дұрыс қолдану
- ✅ `\n` символдарын дұрыс кодтау

**Негізгі ерекшеліктер:**
```csharp
// Промптте:
1. LINE COUNT MUST BE IDENTICAL
2. TRANSLATE LINE-BY-LINE
3. PRESERVE EMPTY LINES
4. NUMBER CONVERSION TO WORDS
5. JSON FORMAT ONLY
6. NEWLINE ENCODING (\n not \\n)
```

#### b) TranslationController.cs
**Файл:** `/Controllers/TranslationController.cs`

**Өзгерістер:**
- ✅ Жолдар санын есептеу (кіріс)
- ✅ Аударма нәтижесін тексеру (шығыс)
- ✅ Line count validation
- ✅ `completed_with_warnings` статусы қосылды

**Код:**
```csharp
// Line 74-76: Кіріс жолдарын есептеу
var inputLineCount = request.Text.Split('\n').Length;
_logger.LogInformation("Translation request: Input has {LineCount} lines", inputLineCount);

// Line 105-126: Validation логикасы
if (inputLineCount != outputLineCount) {
    _logger.LogWarning("⚠️ LINE COUNT MISMATCH...");
    job.Status = "completed_with_warnings";
    job.ErrorMessage = $"Line count mismatch...";
}
```

#### c) TranslationJob.cs (Model)
**Файл:** `/Models/Translation/TranslationJob.cs`

**Өзгерістер:**
- ✅ `InputLineCount` өрісі қосылды
- ✅ `OutputLineCount` өрісі қосылды

```csharp
/// <summary>
/// Кіріс жолдар саны (validation үшін)
/// </summary>
public int InputLineCount { get; set; }

/// <summary>
/// Шығыс жолдар саны (validation үшін)
/// </summary>
public int OutputLineCount { get; set; }
```

#### d) Database Migration
**Жасалған migration:**
```bash
dotnet ef migrations add AddLineCountToTranslationJob
```

**Қолдану:**
```bash
cd /Users/ykylas/Downloads/oz_api-main
dotnet ef database update
```

---

### 2. Frontend Өзгерістері (qaznat_vt - Flutter)

#### a) translation_models.dart
**Файл:** `/lib/models/translation_models.dart`

**Өзгерістер:**
- ✅ `TranslationJobResult` моделіне өрістер қосылды:
  - `errorMessage`
  - `inputLineCount`
  - `outputLineCount`
  - `sourceLanguage`
  - `targetLanguage`

- ✅ Helper методтар қосылды:
```dart
/// Жолдар санының сәйкестігін тексеру
bool get hasLineCountMismatch {
  if (inputLineCount == null || outputLineCount == null) return false;
  return inputLineCount != outputLineCount;
}

/// Validation қате хабарын алу
String? get validationWarning {
  if (hasLineCountMismatch) {
    return 'Жолдар саны сәйкес емес: күтілген $inputLineCount, алынған $outputLineCount';
  }
  return null;
}
```

#### b) backend_translation_service.dart
**Файл:** `/lib/services/backend_translation_service.dart`

**Өзгерістер:**

1. **`translate()` методына validation қосылды:**
```dart
// Line 32-34: Pre-validation
final inputLines = text.split('\n');
final inputLineCount = inputLines.length;

// Line 64-79: Post-validation
if (inputLineCount != outputLineCount) {
  debugPrint('⚠️ WARNING: Line count mismatch!');
  debugPrint('   Expected: $inputLineCount lines');
  debugPrint('   Got: $outputLineCount lines');
}
```

2. **Жаңа `translateWithValidation()` методы қосылды:**
```dart
Future<TranslationJobResult> translateWithValidation({
  required String text,
  required String targetLanguage,
  String? sourceLanguage,
  required int durationSeconds,
  String? videoFileName,
}) async {
  // Pre-validation + Translation + Post-validation
}
```

---

## 🔧 Қалай Қолдану

### Backend (C# / .NET)

1. **Migration қолдану:**
```bash
cd /Users/ykylas/Downloads/oz_api-main
dotnet ef database update
```

2. **Сервер қайта іске қосу:**
```bash
dotnet run
```

### Frontend (Flutter)

1. **Қарапайым аударма (validation бар):**
```dart
final service = BackendTranslationService(apiClient);

final result = await service.translate(
  text: 'Жол 1\nЖол 2\nЖол 3',
  targetLanguage: 'zh',
  durationSeconds: 30,
);

// Тексеру
if (result.hasLineCountMismatch) {
  print('⚠️ ${result.validationWarning}');
}
```

2. **Күшейтілген validation:**
```dart
final result = await service.translateWithValidation(
  text: 'Жол 1\nЖол 2\nЖол 3',
  targetLanguage: 'zh',
  durationSeconds: 30,
);
```

---

## 📊 Validation Process Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    CLIENT (Flutter)                         │
├─────────────────────────────────────────────────────────────┤
│  1. Count input lines: text.split('\n').length              │
│  2. Send to API: {text: "line1\nline2\nline3"}              │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────────┐
│              BACKEND API (TranslationController)            │
├─────────────────────────────────────────────────────────────┤
│  3. Count input lines: request.Text.Split('\n').Length      │
│  4. Save to DB: job.InputLineCount = inputLineCount         │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────────┐
│           TRANSLATION SERVICE (GeminiTranslationService)    │
├─────────────────────────────────────────────────────────────┤
│  5. Send prompt to Gemini with strict line count rules     │
│  6. Gemini returns: {"translatedText": "行1\n行2\n行3"}      │
│  7. Parse JSON and extract translatedText                   │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────────┐
│              BACKEND API (TranslationController)            │
├─────────────────────────────────────────────────────────────┤
│  8. Count output lines: result.TranslatedText.Split('\n')   │
│  9. Compare: inputLineCount == outputLineCount              │
│ 10. If mismatch: status = "completed_with_warnings"         │
│ 11. Save to DB: job.OutputLineCount = outputLineCount       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                    CLIENT (Flutter)                         │
├─────────────────────────────────────────────────────────────┤
│ 12. Receive response                                        │
│ 13. Check result.hasLineCountMismatch                       │
│ 14. Display warning if needed                               │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 Күтілетін Нәтиже

### Бұрын (❌)
```
Кіріс:
Жол 1
Жол 2
Жол 3

Шығыс:
Жол 1 Жол 2 Жол 3
```
**Мәселе:** 3 жол → 1 жолға біріктірілді

### Енді (✅)
```
Кіріс:
Жол 1
Жол 2
Жол 3

Шығыс:
行 1
行 2
行 3
```
**Нәтиже:** 3 жол → 3 жол (дәл сәйкес!)

---

## 🔍 Логтарды Тексеру

### Backend Логтары
```
Translation request: Input has 3 lines
Output line count: 3
✅ Line count validation passed for job {JobId}: 3 lines
```

### Frontend Логтары
```
=== Translation Request ===
Input line count: 3
...
=== Translation Response ===
Output line count: 3
✅ Line count validation passed: 3 lines
```

---

## ⚠️ Ескертулер

1. **Migration қолдануды ұмытпаңыз:**
   ```bash
   dotnet ef database update
   ```

2. **Gemini API Prompt:**
   - Database-тегі `TranslationSettings.TranslationPrompt` өрісі жаңа промптті қолданбайды
   - Код-тағы `DefaultTranslationPrompt` қолданылады
   - Егер database-тегі промптті қолданғыңыз келсе, оны жаңартыңыз

3. **Кері үйлесімділік:**
   - Ескі `TranslationJob` жазбаларында `InputLineCount` және `OutputLineCount` = 0 болады
   - Бұл қалыпты жағдай, жаңа аудармалар үшін толтырылады

---

## 📚 Қосымша Ресурстар

- [TRANSLATION_API_INTEGRATION.md](TRANSLATION_API_INTEGRATION.md) - Толық API құжаттамасы
- Backend код: `oz_api-main/Services/GeminiTranslationService.cs`
- Frontend код: `qaznat_vt/lib/services/backend_translation_service.dart`

---

## ✨ Қорытынды

Енді аударма жүйесі:
- ✅ Жолдар санын қатаң сақтайды
- ✅ SRT субтитрлер форматын бұзбайды
- ✅ JSON құрылымын дұрыс өңдейді
- ✅ `\n` символдарын дұрыс кодтайды
- ✅ Validation логикасы екі жақта да бар (backend + frontend)
- ✅ Егер мәселе болса, `completed_with_warnings` статусы қойылады

**Тестілеу үшін дайын!** 🚀
