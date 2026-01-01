# Whisper Транскрипция Промпты

## Мақсат

Видео файлдан аудионы шығарып, Whisper арқылы транскрибировать етіп, келесі JSON схемасына сай таза, timestamp-тармен, сөйлемге бөлінген транскрипция алу.

## Whisper API шақыру параметрлері

```bash
# OpenAI API мысалы
curl -X POST "https://api.openai.com/v1/audio/transcriptions" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F "model=whisper-1" \
  -F "file=@audio.wav" \
  -F "response_format=json" \
  -F "temperature=0.0" \
  -F "language=auto" \
  -o transcript.json
```

### Параметрлер:
- `model`: `whisper-1` немесе `large-v2` (local үшін)
- `task`: `transcribe`
- `language`: `auto` (автоанықтау) немесе `kk`/`ru`/`en`/`zh`
- `response_format`: `json`
- `temperature`: `0.0` (нақты транскрипция үшін)
- `timestamps`: `true`
- `word_timestamps`: `false` (немесе `true` егер керек болса)

## System Instruction (Whisper-ге беру)

```
Instruction:
You receive an audio extracted from a user-uploaded video. Produce a clean JSON transcription following the schema below.

Requirements:
1. Output exactly one JSON object (no extra text).
2. Language detection: if user selected explicit language (kk/ru/en/zh), force transcribe in that language. If user selected "auto", detect language automatically and set `language` field.
3. Include timestamps (start, end) in seconds with millisecond precision (e.g., 12.345).
4. Break transcript into segments representing natural sentences/utterances. Each segment must have:
   - "start": float (seconds)
   - "end": float (seconds)
   - "text": string (cleaned, punctuated)
   - "confidence": float (0.0 - 1.0) if available; otherwise null.
   - "language": language code (e.g., "kk", "ru", "en") — same for all segments or detected per segment if mixed.
5. Include a top-level summary object:
   - "filename": original filename
   - "duration": total duration in seconds (float)
   - "detected_language": language code or "mixed" if multiple
   - "model": model name used
   - "created_at": ISO 8601 timestamp UTC
6. Do not include fillers like "uh", "um" in final text unless user chose to keep disfluencies. If unsure, remove common disfluencies.
7. If speaker diarization is available and requested, add "speaker" property to segments: "speaker_1", "speaker_2", etc.
8. Preserve non-speech tokens (e.g., [laughter], [music]) as bracketed tokens in text.
9. If audio is silent for > 3s, do not create a segment for silence; just continue.
10. Ensure the final JSON is UTF-8 encoded and valid.

Return JSON schema as in "Expected JSON example" below.
```

## JSON Схема (күтілетін формат)

```json
{
  "filename": "video_2025-12-05.mp4",
  "duration": 123.456,
  "detected_language": "kk",
  "model": "whisper-1",
  "created_at": "2025-12-05T08:12:34Z",
  "segments": [
    {
      "start": 0.00,
      "end": 3.45,
      "text": "Сәлеметсіз бе, бүгінгі видеомызға қош келдіңіздер.",
      "confidence": 0.92,
      "language": "kk",
      "speaker": "speaker_1"
    },
    {
      "start": 3.46,
      "end": 7.80,
      "text": "[music]",
      "confidence": null,
      "language": "kk",
      "speaker": null
    },
    {
      "start": 7.81,
      "end": 12.50,
      "text": "Бүгін біз жаңа функцияларды қарастырамыз.",
      "confidence": 0.95,
      "language": "kk",
      "speaker": "speaker_1"
    }
  ]
}
```

## Backend Implementation Guide

### 1. Endpoint: POST /api/transcribe

```python
# FastAPI мысалы
from fastapi import FastAPI, File, UploadFile, Form
import subprocess
import json
import httpx
from datetime import datetime

app = FastAPI()

@app.post("/api/transcribe")
async def transcribe_video(
    file: UploadFile = File(...),
    options: str = Form(...)
):
    """
    Video файлды қабылдап, транскрипциялау
    """
    options_data = json.loads(options)

    # 1. Видеоны сақтау
    video_path = f"/tmp/{file.filename}"
    with open(video_path, "wb") as f:
        f.write(await file.read())

    # 2. Аудио шығару (ffmpeg)
    audio_path = video_path.replace(".mp4", ".wav")
    subprocess.run([
        "ffmpeg", "-i", video_path,
        "-ac", "1",  # mono
        "-ar", "16000",  # 16kHz
        "-vn",  # no video
        audio_path
    ])

    # 3. Whisper API шақыру
    async with httpx.AsyncClient() as client:
        with open(audio_path, "rb") as audio_file:
            response = await client.post(
                "https://api.openai.com/v1/audio/transcriptions",
                headers={"Authorization": f"Bearer {OPENAI_API_KEY}"},
                files={"file": audio_file},
                data={
                    "model": options_data.get("model", "whisper-1"),
                    "language": options_data.get("language", "auto"),
                    "response_format": "json",
                    "temperature": 0.0,
                }
            )

    raw_result = response.json()

    # 4. JSON схемасына форматтау
    result = format_to_schema(raw_result, file.filename, options_data)

    # 5. Job ID қайтару (асинхронды өңдеу үшін)
    job_id = save_result(result)

    return {"job_id": job_id}


def format_to_schema(whisper_result, filename, options):
    """
    Whisper нәтижесін біздің схемамызға түрлендіру
    """
    segments = []

    for segment in whisper_result.get("segments", []):
        segments.append({
            "start": segment["start"],
            "end": segment["end"],
            "text": segment["text"].strip(),
            "confidence": segment.get("confidence"),
            "language": whisper_result.get("language", "unknown"),
            "speaker": None  # diarization болса, осы жерге қосыңыз
        })

    return {
        "filename": filename,
        "duration": whisper_result.get("duration", 0),
        "detected_language": whisper_result.get("language", "unknown"),
        "model": "whisper-1",
        "created_at": datetime.utcnow().isoformat() + "Z",
        "segments": segments
    }
```

### 2. Endpoint: GET /api/transcribe/{job_id}/status

```python
@app.get("/api/transcribe/{job_id}/status")
async def get_status(job_id: str):
    """
    Транскрипция статусын тексеру
    """
    status = get_job_status(job_id)  # Redis/DB-дан алу

    return {
        "status": status["state"],  # "processing", "completed", "failed"
        "progress": status.get("progress", 0.0)
    }
```

### 3. Endpoint: GET /api/transcribe/{job_id}/result

```python
@app.get("/api/transcribe/{job_id}/result")
async def get_result(job_id: str):
    """
    Дайын транскрипцияны қайтару
    """
    result = load_result(job_id)  # Storage-дан жүктеу

    if not result:
        raise HTTPException(status_code=404, detail="Result not found")

    return result  # JSON schema бойынша
```

## Audio Extraction (ffmpeg)

Видеодан аудио шығару:

```bash
ffmpeg -i input.mp4 -ac 1 -ar 16000 -vn audio.wav
```

Параметрлер:
- `-i input.mp4`: кіріс видео
- `-ac 1`: mono (1 channel)
- `-ar 16000`: 16kHz sample rate (Whisper үшін оптималды)
- `-vn`: видеоны алып тастау (тек аудио)
- `audio.wav`: шығыс файл

## Testing

Үлгі тестілер:

```bash
# 1. Қазақша видео
curl -X POST http://localhost:8000/api/transcribe \
  -F "file=@test_kk.mp4" \
  -F 'options={"language":"kk","timestamps":true}'

# 2. Автоанықтау
curl -X POST http://localhost:8000/api/transcribe \
  -F "file=@test_mixed.mp4" \
  -F 'options={"language":"auto","timestamps":true}'

# 3. Speaker diarization
curl -X POST http://localhost:8000/api/transcribe \
  -F "file=@interview.mp4" \
  -F 'options={"language":"ru","speaker_diarization":true}'
```

## Қауіпсіздік

- ✅ Файл өлшемін шектеу (max 500 MB)
- ✅ Файл форматын тексеру (.mp4, .mkv, .avi, .mov)
- ✅ Вирус сканері (опциялы)
- ✅ CORS параметрлері
- ✅ API Key қорғау
- ✅ Rate limiting

## Қателіктерді өңдеу

```python
try:
    # Whisper API шақыру
    result = await transcribe_audio(...)
except httpx.HTTPStatusError as e:
    if e.response.status_code == 413:
        return {"error": "File too large"}
    elif e.response.status_code == 415:
        return {"error": "Unsupported format"}
    else:
        return {"error": f"API error: {e}"}
except Exception as e:
    return {"error": f"Processing error: {str(e)}"}
```
