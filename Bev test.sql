
-- =============================================
-- Author:		Beverley Salt
-- Create date: 27/11/2026
-- Update date: 1
-- Version:		1.0
-- Description:	DQIP: SMOKING STATUS FROM SUS APCS
--				
--
--Change Log	<Version No> - <Date of Change>	- <Author Making Change> - <Task ID> - <Brief Description of Change>
-- =============================================
-- CONTENTS
-- PART 01 DECLARE DATE PARAMETERS
-- PART 02 DECLARE PROVIDER CODES
-- PART 03 Declaring the BLMK Commissioner codes 
-- PART 04 Extract core data from APCS with smoking / non smoking records and total spells
-- PART 05 Extract total spells into a temp table, for APCS denominators
-- PART 06 Extract smoking records and non smoking records from the core table to create APCS numerator --
-- PART 07 TO PART 10 - DISREGARD AS RELATES TO SMITH
-- Part 11 - COUNT OF APCS SPELLS WITH/WITHOUT SMOKING STATUS - FINAL EXTRACT
-- PART 12 TIDY UP


-- =============================================
-- PART 01: DECLARE DATE PARAMETERS & FILTERS
-- =============================================
DECLARE @start_date DATE = '2024-04-01', @end_date DATE = '2026-03-31'
DECLARE @filter_provider VARCHAR(10) = 'RD8'
DECLARE @filter_period DATE = '2024-12-31' 


-- =============================================
-- PART 02: DECLARE PROVIDER CODES
-- =============================================
DECLARE @Providers TABLE ([Der_Mapped_Provider_Code] VARCHAR(10)) ;
INSERT INTO @Providers ([Der_Mapped_Provider_Code])
VALUES  ('RD8') --, ('RC9')--,('RYV'),('RWK'),('NX1'),('U1P4Z'),('NT434'),('NT423'),('C5P5G'),('NVG18'),('NVC31'),('NPG19')

-- =============================================
-- PART 03: DECLARE BLMK COMMISSIONER CODES
-- =============================================
DECLARE @Commissioner_codes TABLE ([Der_Mapped_Commissioner_Code] VARCHAR(5)) ;
INSERT INTO @Commissioner_codes ([Der_Mapped_Commissioner_Code])
VALUES ('M1J4Y'), ('04F'), ('04F00'), ('06F'), ('06F00'), ('06P'), 
	('06P00'), ('M1J'), ('M1J4Y'), ('QHG'), ('QHG00') ;


-- =============================================
-- PART 04: EXTRACT APCS DATA WITH SMOKING STATUS
-- =============================================
-- Extract all APCS spells with smoking status classification
-- Smoking codes: Z720 (tobacco use), F17 (nicotine dependence), Z716 (smoking counseling)
IF OBJECT_ID('tempdb..#SPELLS') IS NOT NULL
	DROP TABLE #SPELLS

SELECT 
	'SUS_APCS' AS [Data_Source]
	,[Der_Mapped_Provider_Code] AS [Provider_Code]
	,Der_Pseudo_NHS_Number
	,'Smoking status' AS Metric
	,EOMONTH([Discharge_Date]) AS Financial_Period
	,CASE 
		WHEN [Der_Diagnosis_All] LIKE '%Z720%' OR [Der_Diagnosis_All] LIKE '%F17%' OR [Der_Diagnosis_All] LIKE '%Z716%'
		THEN 'Smoker'
		ELSE 'Not known / Missing' 
	END AS Metric_Value
	,ExcelDate.Excel_Date_Value AS Excel_Date_Value
	,COUNT(*) AS Spells
INTO #SPELLS
FROM [BLMK_Live].[tbl_SUS_BLMK_APCS_Reporting] AS T1
LEFT JOIN [UKHD].[dbo_ref_Dates] AS ExcelDate ON CAST(ExcelDate.[Full_Date] AS DATE) = EOMONTH(T1.[Discharge_Date])
WHERE Discharge_Date BETWEEN @start_date AND @end_date
	AND [Der_Mapped_Provider_Code] IN (SELECT [Der_Mapped_Provider_Code] FROM @Providers)
	AND [Der_Mapped_Commissioner_Code] IN (SELECT [Der_Mapped_Commissioner_Code] FROM @Commissioner_codes)
GROUP BY 
	[Der_Mapped_Provider_Code]
	,Der_Pseudo_NHS_Number
	,EOMONTH([Discharge_Date])
	,CASE 
		WHEN [Der_Diagnosis_All] LIKE '%Z720%' OR [Der_Diagnosis_All] LIKE '%F17%' OR [Der_Diagnosis_All] LIKE '%Z716%'
		THEN 'Smoker'
		ELSE 'Not known / Missing' 
	END
	,ExcelDate.Excel_Date_Value;

-- =============================================
-- PART 05: CREATE APCS DENOMINATOR (Total Spells)
-- =============================================
IF OBJECT_ID('tempdb..#APCS_DENOMINATOR') IS NOT NULL
	DROP TABLE #APCS_DENOMINATOR

SELECT 
	Data_Source
	,Provider_Code
	,Financial_Period
	,SUM(Spells) AS Denominator
INTO #APCS_DENOMINATOR
FROM #SPELLS
GROUP BY 
	Data_Source
	,Provider_Code
	,Financial_Period;



-- =============================================
-- PART 06: CREATE APCS NUMERATOR (Smoking Records)
-- =============================================
IF OBJECT_ID('tempdb..#APCS_NUMERATOR') IS NOT NULL
	DROP TABLE #APCS_NUMERATOR

SELECT 
	Data_Source
	,Provider_Code
	,Financial_Period
	,Metric
	,Metric_Value
	,CONCAT(Data_Source, ' | ', Provider_Code, ' | Smoking status - APCS | ', Metric_Value, ' | ', CAST(Excel_Date_Value AS VARCHAR)) AS Dashboard_Lookup_Column
	,SUM(Spells) AS Numerator
INTO #APCS_NUMERATOR
FROM #SPELLS
GROUP BY 
	Data_Source
	,Provider_Code
	,Financial_Period
	,Metric
	,Metric_Value
	,Excel_Date_Value
ORDER BY Provider_Code, Financial_Period;


-- =============================================
-- PART 07: EXTRACT SMITH SMOKERS
-- =============================================
-- Identify patients with smoking status in SMITH database
IF OBJECT_ID('tempdb..#SMITH_SMOKER') IS NOT NULL
	DROP TABLE #SMITH_SMOKER

SELECT DISTINCT
	[Pat_ID]
	,CASE WHEN [Code_Group] LIKE 'Smok%' THEN 'Smoker' ELSE 'Not known / Missing' END AS Metric_Value
INTO #SMITH_SMOKER
FROM [BLMK_Live_SMITH].[tbl_SMITHv3_Clinical_Register_Full]
WHERE [End_Date] IS NULL;
-- =============================================
-- PART 08-09: CREATE SMITH DENOMINATOR
-- =============================================
-- Count SMITH smoker patients that exist in APCS
IF OBJECT_ID('tempdb..#SMITH_DENOMINATOR') IS NOT NULL
	DROP TABLE #SMITH_DENOMINATOR

SELECT 
	'SMITH' AS Data_Source
	,T2.Provider_Code
	,T2.Financial_Period
	,COUNT(DISTINCT T2.Der_Pseudo_NHS_Number) AS Denominator
INTO #SMITH_DENOMINATOR 
FROM #SMITH_SMOKER AS T1
INNER JOIN #SPELLS AS T2 ON T2.Der_Pseudo_NHS_Number = T1.Pat_ID
GROUP BY 
	T2.Data_Source
	,T2.Provider_Code
	,T2.Financial_Period;
-- NOTE: Staging table removed - not needed for final output


-- =============================================
-- PART 11: CREATE FINAL OUTPUT
-- =============================================
-- Combine APCS results with percentages
IF OBJECT_ID('tempdb..#FINAL_OUTPUT') IS NOT NULL
	DROP TABLE #FINAL_OUTPUT

SELECT
	T1.Data_Source
	,T1.Provider_Code
	,T1.Financial_Period
	,T1.Metric
	,T1.Metric_Value
	,T1.Dashboard_Lookup_Column
	,SUM(T1.Numerator) AS Numerator
	,SUM(T2.Denominator) AS Denominator
	,CAST((SUM(T1.Numerator * 1.0) / SUM(T2.Denominator)) * 100 AS DECIMAL(10,2)) AS Percentage
INTO #FINAL_OUTPUT
FROM #APCS_NUMERATOR AS T1
INNER JOIN #APCS_DENOMINATOR AS T2 
	ON T2.Data_Source = T1.Data_Source 
	AND T2.Provider_Code = T1.Provider_Code 
	AND T2.Financial_Period = T1.Financial_Period
WHERE T1.Provider_Code = @filter_provider 
	AND T1.Financial_Period = @filter_period
GROUP BY 
	T1.Data_Source
	,T1.Metric
	,T1.Metric_Value
	,T1.Provider_Code
	,T1.Financial_Period
	,T1.Dashboard_Lookup_Column
UNION ALL
-- Add SMITH results
SELECT
	T1.Data_Source
	,T1.Provider_Code
	,T1.Financial_Period
	,'Smoking status' AS Metric
	,'Smoker' AS Metric_Value
	,CONCAT('SMITH', ' | ', T1.Provider_Code, ' | Smoking status - SMITH | Smoker | ', CAST(T1.Financial_Period AS VARCHAR)) AS Dashboard_Lookup_Column
	,SUM(T1.Denominator) AS Numerator
	,SUM(T2.Denominator) AS Denominator
	,CAST((SUM(T1.Denominator * 1.0) / SUM(T2.Denominator)) * 100 AS DECIMAL(10,2)) AS Percentage
FROM #SMITH_DENOMINATOR AS T1
INNER JOIN #APCS_DENOMINATOR AS T2 
	ON T2.Provider_Code = T1.Provider_Code 
	AND T2.Financial_Period = T1.Financial_Period
WHERE T1.Provider_Code = @filter_provider 
	AND T1.Financial_Period = @filter_period
GROUP BY 
	T1.Data_Source
	,T1.Provider_Code
	,T1.Financial_Period;


-- =============================================
-- FINAL RESULTS
-- =============================================
SELECT * FROM #FINAL_OUTPUT
ORDER BY Data_Source, Provider_Code, Financial_Period, Metric_Value;

-- =============================================
-- PART 12: CLEANUP (Uncomment to execute)
-- =============================================
-- DROP TABLE #SPELLS;
-- DROP TABLE #APCS_DENOMINATOR;
-- DROP TABLE #APCS_NUMERATOR;
-- DROP TABLE #SMITH_SMOKER;
-- DROP TABLE #SMITH_DENOMINATOR;
-- DROP TABLE #FINAL_OUTPUT;

