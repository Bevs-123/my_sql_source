/*
Foundation Recap Exercise
 
Use the table PatientStay.  
This lists 44 patients admitted to London hospitals over 5 days between Feb 26th and March 2nd 2024
*/
 

 
/*
1. Filter the list the patients to show only those  -
a) in the Oxleas hospital,
b) and also in the PRUH hospital,
c) admitted in February 2024
d) only the surgical wards (i.e. wards ending with the word Surgery)
 
 
2. Show the PatientId, AdmittedDate, DischargeDate, Hospital and Ward columns only, not all the columns.
3. Order results by AdmittedDate (latest first) then PatientID column (high to low)
4. Add a new column LengthOfStay which calculates the number of days that the patient stayed in hospital, inclusive of both admitted and discharge date.
*/
 
-- Write the SQL statement here
--SELECT * FROM PATIENTSTAY 
;
SELECT COUNT(Q1.PatientId) AS PT_COUNT, SUM(Q1.TARIFF) AS SUM_TARIFF,Q1.Hospital
FROM
 (SELECT
	PS.PatientId 
    ,PS.AdmittedDate
    ,PS.DischargeDate
    ,PS.Hospital 
    ,PS.Ward 
    ,PS.Tariff
    ,DATEDIFF(DD,PS.AdmittedDate,PS.DischargeDate) AS LengthOfStay
    ,DATEADD(MM,3,PS.DischargeDate) AS AppointmentDate
FROM
	PatientStay PS 
/* WHERE 
ps.Hospital IN ('Oxleas','Pruh')
AND AdmittedDate BETWEEN '2024-02-01' AND '2024-02-29'
AND Ward LIKE '%SURGERY%' 
*/
--ORDER BY AdmittedDate ASC, PatientId DESC
) Q1
  GROUP BY Q1.Hospital 
  HAVING SUM(Q1.TARIFF) > 10 
  ORDER BY COUNT(Q1.PatientId) DESC;
 
/*
5. How many patients has each hospital admitted? 
6. How much is the total tariff for each hospital?
7. List only those hospitals that have admitted over 10 patients
8. Order by the hospital with most admissions first
*/
 
-- Write the SQL statement here


SELECT
    PS.Hospital
    ,SUM(PS.Tariff) AS Tariff
    ,COUNT(*) AdmissionCount

FROM
	PatientStay PS

    GROUP BY 
    PS.Hospital

HAVING 
    COUNT(*) > 10

ORDER BY
    AdmissionCount DESC 
