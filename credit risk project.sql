/* ============================================================
Project: Credit Risk Analytics (Retail Banking)
Author: Sibongile Tshabalala
============================================================ */

/* ============================================================
1. Create and Use Database
============================================================ */
CREATE DATABASE CreditRisk;
GO

USE CreditRisk;
GO


/* ============================================================
2. Dataset Inspection & Validation
============================================================ */

-- Total Records
SELECT COUNT(*) AS total_records
FROM dbo.german_credit_data;

-- Preview Data
SELECT TOP 10 *
FROM dbo.german_credit_data;

-- Column Names (IMPORTANT CHECK)
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'german_credit_data';


/* ============================================================
3. Data Quality Checks
============================================================ */

-- Target Distribution
SELECT 
    Risk,
    COUNT(*) AS total,
    COUNT(*) * 1.0 / SUM(COUNT(*)) OVER() AS proportion
FROM dbo.german_credit_data
GROUP BY Risk;

-- Missing Values
SELECT 
    COUNT(*) - COUNT(Saving_accounts) AS missing_saving_accounts,
    COUNT(*) - COUNT(Checking_account) AS missing_checking_account
FROM dbo.german_credit_data;

-- Duplicate Check
SELECT 
    Age,
    Credit_amount,
    Duration,
    COUNT(*) AS duplicate_count
FROM dbo.german_credit_data
GROUP BY Age, Credit_amount, Duration
HAVING COUNT(*) > 1;

-- Data Range
SELECT 
    MIN(Age) AS min_age,
    MAX(Age) AS max_age,
    MIN(Credit_amount) AS min_credit,
    MAX(Credit_amount) AS max_credit,
    MIN(Duration) AS min_duration,
    MAX(Duration) AS max_duration
FROM dbo.german_credit_data;


/* ============================================================
4. Feature Engineering (Create Clean Table)
============================================================ */

IF OBJECT_ID('dbo.credit_risk_clean', 'U') IS NOT NULL
    DROP TABLE dbo.credit_risk_clean;

SELECT
    Age,
    Sex,
    Job,
    Housing,

    ISNULL(Saving_accounts, 'unknown') AS saving_accounts,
    ISNULL(Checking_account, 'unknown') AS checking_account,

    Credit_amount,
    Duration,
    Purpose,

    -- Target
    CASE 
        WHEN LOWER(Risk) = 'bad' THEN 1
        ELSE 0
    END AS default_flag,

    -- Engineered Features
    (Credit_amount * 1.0) / Duration AS credit_per_duration,
    (Credit_amount * 1.0) / (Age + 1) AS debt_ratio_proxy,

    -- Bands
    CASE 
        WHEN Credit_amount < 2000 THEN 'Low'
        WHEN Credit_amount < 5000 THEN 'Medium'
        ELSE 'High'
    END AS credit_amount_band,

    CASE 
        WHEN Duration <= 12 THEN 'Short'
        WHEN Duration <= 36 THEN 'Medium'
        ELSE 'Long'
    END AS duration_band

INTO dbo.credit_risk_clean
FROM dbo.german_credit_data;

-- View Output
SELECT TOP 10 *
FROM dbo.credit_risk_clean;


/* ============================================================
5. EDA (Analytics)
============================================================ */

-- Overall Default Rate
SELECT 
    COUNT(*) AS total_customers,
    SUM(default_flag) AS defaulters,
    AVG(CAST(default_flag AS FLOAT)) AS default_rate
FROM dbo.credit_risk_clean;

-- Risk by Credit Band
SELECT 
    credit_amount_band,
    COUNT(*) AS total,
    AVG(CAST(default_flag AS FLOAT)) AS default_rate
FROM dbo.credit_risk_clean
GROUP BY credit_amount_band
ORDER BY default_rate DESC;

-- Risk by Duration
SELECT 
    duration_band,
    COUNT(*) AS total,
    AVG(CAST(default_flag AS FLOAT)) AS default_rate
FROM dbo.credit_risk_clean
GROUP BY duration_band
ORDER BY default_rate DESC;

-- Risk by Age Group
SELECT 
    CASE 
        WHEN Age < 30 THEN 'Young'
        WHEN Age < 50 THEN 'Middle'
        ELSE 'Older'
    END AS age_group,
    COUNT(*) AS total,
    AVG(CAST(default_flag AS FLOAT)) AS default_rate
FROM dbo.credit_risk_clean
GROUP BY 
    CASE 
        WHEN Age < 30 THEN 'Young'
        WHEN Age < 50 THEN 'Middle'
        ELSE 'Older'
    END
ORDER BY default_rate DESC;


/* ============================================================
6. Risk Scoring (SQL Model)
============================================================ */

ALTER TABLE dbo.credit_risk_clean
ADD risk_score FLOAT;

UPDATE dbo.credit_risk_clean
SET risk_score =
      (Credit_amount * 0.0001)
    + (Duration * 0.01)
    + (debt_ratio_proxy * 0.05);

-- Check Scores
SELECT TOP 10 
    Credit_amount,
    Duration,
    debt_ratio_proxy,
    risk_score
FROM dbo.credit_risk_clean
ORDER BY risk_score DESC;


/* ============================================================
7. Decile Analysis
============================================================ */

IF OBJECT_ID('dbo.credit_risk_scored', 'U') IS NOT NULL
    DROP TABLE dbo.credit_risk_scored;

SELECT *,
       NTILE(10) OVER (ORDER BY risk_score DESC) AS decile
INTO dbo.credit_risk_scored
FROM dbo.credit_risk_clean;

-- Decile Output
SELECT 
    decile,
    COUNT(*) AS total_customers,
    SUM(default_flag) AS defaulters,
    AVG(CAST(default_flag AS FLOAT)) AS default_rate
FROM dbo.credit_risk_scored
GROUP BY decile
ORDER BY decile;


/* ============================================================
8. Business Insight (Portfolio Risk)
============================================================ */

-- High Risk Customers
SELECT 
    COUNT(*) AS high_risk_customers,
    AVG(CAST(default_flag AS FLOAT)) AS default_rate
FROM dbo.credit_risk_scored
WHERE decile >= 8;

-- Low Risk Customers
SELECT 
    COUNT(*) AS low_risk_customers,
    AVG(CAST(default_flag AS FLOAT)) AS default_rate
FROM dbo.credit_risk_scored
WHERE decile <= 3;


/* ============================================================
9. Stored Procedure
============================================================ */

GO

CREATE OR ALTER PROCEDURE dbo.sp_credit_risk_summary
AS
BEGIN
    SELECT 
        COUNT(*) AS total_customers,
        SUM(default_flag) AS total_defaults,
        AVG(CAST(default_flag AS FLOAT)) AS default_rate
    FROM dbo.credit_risk_clean;
END;

GO

-- Execute Procedure
EXEC dbo.sp_credit_risk_summary;