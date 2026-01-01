# Backend Login Мәселесін Шешу

## Мәселе
Тіркелгеннен кейін логин жасау мүмкін емес. Backend 500 қатесін қайтарады:
```
Invalid column name 'CreatedAt'.
Invalid column name 'Price'.
Invalid column name 'Type'.
Invalid column name 'DurationInDays'.
```

## Себебі
Database-те `Subscriptions` кестесінде қажетті бағандар жоқ. Migration қолданылмаған.

## Шешім

### 1-қадам: Backend-ті тоқтату
```bash
# 5008 портындағы процесті табу
lsof -ti:5008

# Процесті тоқтату
kill <process_id>
```

### 2-қадам: Database Migration мәселесін шешу

#### Опция A: Қолмен SQL орындау (Жылдам)
```bash
cd /Users/ykylas/Downloads/oz_api-main
```

SQL Server-ге қосылып, мына SQL-ді орындаңыз:
```sql
-- Subscriptions кестесіне жетіспейтін бағандарды қосу
ALTER TABLE Subscriptions ADD CreatedAt datetime2 NULL;
ALTER TABLE Subscriptions ADD Price decimal(18,2) NULL;
ALTER TABLE Subscriptions ADD Type nvarchar(50) NULL;
ALTER TABLE Subscriptions ADD DurationInDays int NULL;

-- Егер Courses кестесінде қосарланған ThumbnailUrl болса
-- (Migration қатесін болдырмау үшін)
-- Бұл қадамды тек қате шықса ғана орындаңыз
```

#### Опция B: Migration-ды қайта жасау
```bash
cd /Users/ykylas/Downloads/oz_api-main

# Барлық pending migration-дарды көру
dotnet ef migrations list

# Проблемалы migration-ды өшіру (егер бар болса)
dotnet ef migrations remove

# Database-ті қайта құру (ЕСКЕРТУ: барлық деректер жойылады!)
dotnet ef database drop --force
dotnet ef database update
```

### 3-қадам: Backend-ті қайта іске қосу
```bash
cd /Users/ykylas/Downloads/oz_api-main
dotnet run
```

### 4-қадам: Тексеру
```bash
# Логин тестілеу
curl -X POST http://localhost:5008/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"Username":"TestUser5","Password":"Test1234"}'
```

Егер сәтті болса, token қайтарылуы керек:
```json
{
  "token": "eyJhbGc...",
  "userId": "...",
  "username": "TestUser5"
}
```

## Уақытша Шешім (Backend түзетілгенше)

Flutter қолданбасы қазір auto-login арқылы жұмыс істейді:
- Тіркелгеннен кейін автоматты кіреді
- Қайта іске қосқанда логин сұрайды (backend мәселесі)
- Жаңа тіркелгі жасау арқылы қайта кіруге болады

## Қосымша Ақпарат

Backend логтарын көру:
```bash
tail -f /Users/ykylas/Downloads/oz_api-main/backend.log
```

Database connection тексеру:
```bash
cd /Users/ykylas/Downloads/oz_api-main
cat appsettings.Development.json | grep ConnectionString
```
