-- =============================================
-- Add Subscription Tier Features columns
-- Жазылым деңгейлерінің ерекшеліктерін қосу
-- =============================================

-- Алдымен бағаналарды қосамыз
-- First, add the columns

-- Check if StandardFeatures column exists
IF NOT EXISTS (
    SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'TranslationSettings' 
    AND COLUMN_NAME = 'StandardFeatures'
)
BEGIN
    ALTER TABLE TranslationSettings
    ADD StandardFeatures NVARCHAR(MAX) NULL;
    
    PRINT '✓ StandardFeatures бағанасы қосылды';
    PRINT '✓ StandardFeatures column added';
END
ELSE
BEGIN
    PRINT '- StandardFeatures бағанасы бұрыннан бар';
END

-- Check if ProFeatures column exists
IF NOT EXISTS (
    SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'TranslationSettings' 
    AND COLUMN_NAME = 'ProFeatures'
)
BEGIN
    ALTER TABLE TranslationSettings
    ADD ProFeatures NVARCHAR(MAX) NULL;
    
    PRINT '✓ ProFeatures бағанасы қосылды';
    PRINT '✓ ProFeatures column added';
END
ELSE
BEGIN
    PRINT '- ProFeatures бағанасы бұрыннан бар';
END

-- Check if VipFeatures column exists
IF NOT EXISTS (
    SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'TranslationSettings' 
    AND COLUMN_NAME = 'VipFeatures'
)
BEGIN
    ALTER TABLE TranslationSettings
    ADD VipFeatures NVARCHAR(MAX) NULL;
    
    PRINT '✓ VipFeatures бағанасы қосылды';
    PRINT '✓ VipFeatures column added';
END
ELSE
BEGIN
    PRINT '- VipFeatures бағанасы бұрыннан бар';
END
GO

-- Енді дефолт мәндерді орнатамыз (тек NULL болса)
-- Now set default values (only if NULL)

PRINT ''
PRINT 'Дефолт мәндерді орнату...'
PRINT 'Setting default feature values...'

UPDATE TranslationSettings
SET 
    StandardFeatures = N'["10 минут/күн тегін аудару","Базалық қолдау","Стандартты сапа","Барлық тілдерге қол жетімділік"]'
WHERE IsActive = 1 AND StandardFeatures IS NULL;

UPDATE TranslationSettings
SET 
    ProFeatures = N'["30 минут/күн тегін аудару","Басымдықты қолдау","HD сапасы","Барлық тілдерге қол жетімділік","Қосымша мүмкіндіктер"]'
WHERE IsActive = 1 AND ProFeatures IS NULL;

UPDATE TranslationSettings
SET 
    VipFeatures = N'["Шексіз аудару","VIP қолдау 24/7","Премиум сапасы","Барлық тілдерге қол жетімділік","Барлық қосымша мүмкіндіктер","Арнайы интеграциялар"]'
WHERE IsActive = 1 AND VipFeatures IS NULL;

PRINT '✓ Дефолт мәндер орнатылды';
PRINT '✓ Default features set'
GO

-- Нәтижелерді тексеру / Verify results
PRINT ''
PRINT 'Нәтижелерді тексеру / Verifying results:'
PRINT ''

SELECT 
    Id,
    IsActive,
    StandardFreeMinutes,
    ProFreeMinutes,
    VipFreeMinutes,
    StandardFeatures,
    ProFeatures,
    VipFeatures,
    UpdatedAt
FROM TranslationSettings
WHERE IsActive = 1;

PRINT ''
PRINT '=== Migration аяқталды / Migration complete ==='
