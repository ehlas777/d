# Backend Setup Steps - Аударма Validation

## ⚠️ МАҢЫЗДЫ: Backend-ті қайта іске қосу керек!

### 1. Backend-ті Тоқтату
```bash
# Terminal-да backend процесін тоқтатыңыз (Ctrl+C)
```

### 2. Database Migration Қолдану

#### Опция A: Автоматты (ұсынылады)
```bash
cd /Users/ykylas/Downloads/oz_api-main

# Migration қолдану
dotnet ef database update --context ApplicationDbContext

# Егер қате шықса, тек біздің migration-ді қолданыңыз:
dotnet ef database update 20251206165520_AddLineCountToTranslationJob --context ApplicationDbContext
```

#### Опция B: Қолмен SQL (егер автоматты жұмыс істемесе)
```bash
# SQL Server-ге қосылып, мына SQL-ді орындаңыз:
# Файл: /Users/ykylas/Downloads/oz_api-main/APPLY_MIGRATION.sql
```

SQL код:
```sql
ALTER TABLE [TranslationJobs] ADD [InputLineCount] int NOT NULL DEFAULT 0;
ALTER TABLE [TranslationJobs] ADD [OutputLineCount] int NOT NULL DEFAULT 0;

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20251206165520_AddLineCountToTranslationJob', N'9.0.0');
```

### 3. Backend-ті Қайта Іске Қосу
```bash
cd /Users/ykylas/Downloads/oz_api-main
dotnet run
```

### 4. Тексеру

Backend іске қосылғаннан кейін логтарда мынаны көруіңіз керек:
```
info: Microsoft.EntityFrameworkCore.Database.Command[20101]
      Executed DbCommand (2ms) [Parameters=[], CommandType='Text', CommandTimeout='30']
      SELECT ... FROM [TranslationJobs] ...
```

Егер қате болса:
```
Invalid column name 'InputLineCount'
```

Бұл migration қолданылмаған дегенді білдіреді - 2-қадамға қайта оралыңыз.

### 5. Flutter-ден Тестілеу

Backend қайта іске қосылғаннан кейін:
```bash
cd /Users/ykylas/Downloads/qaznat_vt
flutter run
```

Аударма тестілеңіз:
- 3-5 жолды мәтін жазыңыз
- Аударма басталсын
- Логтарда мыналарды көруіңіз керек:
  ```
  Input line count: 3
  Output line count: 3
  ✅ Line count validation passed: 3 lines
  ```

---

## 🔍 Қателерді Шешу

### Қате: 500 Internal Server Error
**Себебі:** Database migration қолданылмаған немесе backend қайта іске қосылмаған

**Шешім:**
1. Backend-ті тоқтатыңыз
2. Migration қолданыңыз (жоғарыдағы 2-қадам)
3. Backend-ті қайта іске қосыңыз

### Қате: Invalid column name 'InputLineCount'
**Себебі:** Database-те бағандар жасалмаған

**Шешім:**
```bash
cd /Users/ykylas/Downloads/oz_api-main
dotnet ef database update --force
```

### Қате: There is already an object named 'CourseOrders'
**Себебі:** Басқа pending migration-дар бар

**Шешім:**
```bash
# Тек біздің migration-ді қолданыңыз:
dotnet ef migrations script 20251205150947_AddTranslationSystem 20251206165520_AddLineCountToTranslationJob -o migration.sql

# Содан кейін migration.sql файлын қолмен орындаңыз
```

---

## ✅ Сәтті Орындалғанын Қалай Білуге Болады?

1. **Backend логтарында:**
   ```
   Translation request: Input has 3 lines
   ✅ Line count validation passed for job {JobId}: 3 lines
   ```

2. **Flutter логтарында:**
   ```
   Input line count: 3
   Output line count: 3
   ✅ Line count validation passed: 3 lines
   ```

3. **Database-те:**
   ```sql
   SELECT TOP 1 InputLineCount, OutputLineCount
   FROM TranslationJobs
   ORDER BY CreatedAt DESC
   ```
   Нәтиже: 0 емес сандар көрсетілуі керек

---

## 📞 Көмек Қажет Болса

1. Backend логтарын көрсетіңіз:
   ```bash
   # Backend terminal шығысын көшіріңіз
   ```

2. Database migration статусын тексеріңіз:
   ```bash
   cd /Users/ykylas/Downloads/oz_api-main
   dotnet ef migrations list
   ```

3. Database connection-ды тексеріңіз:
   ```bash
   cat appsettings.Development.json | grep ConnectionString
   ```
