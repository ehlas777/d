# Backend Dev Alignment (qaznat_vt + oz_api-main)

This note keeps the Flutter app (`qaznat_vt`) and the .NET backend (`oz_api-main`) aligned in local dev.

## Goal
- Run backend on the same base URL the Flutter app expects (`http://localhost:5008`).
- Keep translation endpoints working for all target languages (including Uyghur `ug`).
- Avoid leaking secrets while using your own credentials in `appsettings.Development.json` or user-secrets.

## Prereqs
- .NET 9 SDK (project targets `net9.0`).
- SQL Server reachable for `DefaultConnection`.
- Optional: Redis for caching/ratelimiting (can be disabled for local smoke tests).

## Configure backend (Development)
1) Copy/edit `appsettings.Development.json` (or use dotnet user-secrets) with private values:
   - `ConnectionStrings:DefaultConnection`
   - `Jwt:Key`, `Issuer`, `Audience`
   - `Gemini:ApiKey`, `Gemini:ApiEndpoint`
   - Any other API keys (Grok, DeepSeek, Anthropic, SMTP, etc.).
2) Set CORS/frontend origin to allow the Flutter client:
   - `AppSettings:FrontendUrl` -> `http://localhost:5008` (and mobile emulators if needed).
3) If Redis is not running, either start it (`localhost:6379`) or set `ApiRateLimit.EnableRateLimit=false` and `Redis` settings accordingly for dev.
4) Ensure `YouTubeDownload:CookiesPath` and similar file paths exist or disable those features for local runs.

## Run backend for Flutter dev
Backend is already configured for `http://localhost:5008` (Kestrel + `Properties/launchSettings.json`), so you can run without changing ports:
```bash
cd ../oz_api-main
dotnet restore
# Apply migrations if you use a fresh DB:
# dotnet ef database update
ASPNETCORE_ENVIRONMENT=Development ASPNETCORE_URLS=http://localhost:5008 dotnet run
# or: dotnet watch run --urls http://localhost:5008
```

## Endpoints the Flutter app calls
- `POST /api/auth/login` (token stored in secure storage/memory)
- `POST /api/translation/translate-segments` (main batch translation path)
- `GET /api/translation/pricing` (optional cost display)
- `GET /api/translation/history` (if history UI is used)

### Translation specifics
- `targetLanguage` is passed as an ISO code; backend now maps extended codes (e.g., `ug`, `ps`, `ku`, `tg`, `ba`, etc.) to human names for the Gemini prompt. Use the latest backend branch so this mapping is present.
- Segment count guard now normalizes Gemini output (trims/pads) to avoid failures when line counts drift. Keep this version to prevent “Translation failed” in the UI.

## Quick smoke tests
With backend running:
```bash
curl -i http://localhost:5008/api/translation/pricing
curl -i -X POST http://localhost:5008/api/translation/translate-segments \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "segments":[{"id":"segment_0","text":"Test"}],
    "targetLanguage":"ug",
    "durationSeconds":10
  }'
```
Expect 200 with `success:true` and 1 translated segment.

## Frontend alignment
- `lib/services/api_client.dart` uses `http://localhost:5008`; keep backend on that port or update both sides together.
- `AppSettings:FrontendUrl` is used in `Controllers/AuthController.cs` (password-reset links). Set it to the Flutter URL (`http://localhost:5008` for local) via user-secrets or local `appsettings.Development.json`.
- CORS is currently wide-open in `Program.cs` (AllowAll). If you tighten it, include the Flutter origin.

## What not to commit
- Real connection strings, API keys, or OAuth tokens. Use user-secrets or environment variables locally.
