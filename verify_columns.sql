-- Subscriptions кестесінде CreatedAt, Price, Type бағандары бар ма?
SELECT 
    CASE WHEN EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Subscriptions' AND COLUMN_NAME = 'CreatedAt') 
        THEN 'CreatedAt: БАР ✓' 
        ELSE 'CreatedAt: ЖОҚ ✗' 
    END AS CreatedAt_Status,
    CASE WHEN EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Subscriptions' AND COLUMN_NAME = 'Price') 
        THEN 'Price: БАР ✓' 
        ELSE 'Price: ЖОҚ ✗' 
    END AS Price_Status,
    CASE WHEN EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Subscriptions' AND COLUMN_NAME = 'Type') 
        THEN 'Type: БАР ✓' 
        ELSE 'Type: ЖОҚ ✗' 
    END AS Type_Status,
    CASE WHEN EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Subscriptions' AND COLUMN_NAME = 'DurationInDays') 
        THEN 'DurationInDays: БАР ✓' 
        ELSE 'DurationInDays: ЖОҚ ✗' 
    END AS DurationInDays_Status;

-- Барлық бағандарды көрсету
SELECT COLUMN_NAME 
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_NAME = 'Subscriptions'
ORDER BY ORDINAL_POSITION;
