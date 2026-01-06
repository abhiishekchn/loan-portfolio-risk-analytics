
CREATE DATABASE bank_loan_analysis;

USE bank_loan_analysis;

CREATE TABLE customers (
    customer_id VARCHAR(20) PRIMARY KEY,
    first_name VARCHAR(50), last_name VARCHAR(50),
    gender CHAR(1), date_of_birth DATE, age INT,
    marital_status VARCHAR(20), employment_type VARCHAR(20),
    annual_income DECIMAL(15,2),
    credit_score INT CHECK (credit_score BETWEEN 300 AND 900),
    city VARCHAR(50), state VARCHAR(50),
    customer_since DATE
);

CREATE TABLE loan_applications (
    application_id VARCHAR(20) PRIMARY KEY,
    customer_id VARCHAR(20) NOT NULL,
    application_date DATE, loan_type VARCHAR(20),
    requested_amount DECIMAL(15,2), tenure_months INT,
    interest_rate DECIMAL(5,2),
    application_status VARCHAR(20) CHECK (application_status IN ('Approved', 'Rejected', 'Pending')),
    rejection_reason VARCHAR(100),
    credit_score_at_application INT,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE loans (
    loan_id VARCHAR(20) PRIMARY KEY,
    application_id VARCHAR(20) NOT NULL UNIQUE,
    disbursed_amount DECIMAL(15,2),
    disbursement_date DATE, emi_amount DECIMAL(10,2),
    loan_status VARCHAR(20) CHECK (loan_status IN ('Active', 'Closed', 'Defaulted')),
    outstanding_balance DECIMAL(15,2), closure_date DATE,
    FOREIGN KEY (application_id) REFERENCES loan_applications(application_id)
);

CREATE TABLE payments (
    payment_id VARCHAR(20) PRIMARY KEY,
    loan_id VARCHAR(20) NOT NULL,
    payment_date DATE, amount_paid DECIMAL(10,2),
    payment_status VARCHAR(20) CHECK (payment_status IN ('Paid', 'Missed', 'Partial')),
    days_delayed INT DEFAULT 0,
    FOREIGN KEY (loan_id) REFERENCES loans(loan_id)
);

CREATE TABLE loan_defaults (
    default_id VARCHAR(20) PRIMARY KEY,
    loan_id VARCHAR(20) NOT NULL UNIQUE,
    default_date DATE, default_reason VARCHAR(50),
    recovery_status VARCHAR(20) CHECK (recovery_status IN ('Recovered', 'Legal', 'Written Off')),
    FOREIGN KEY (loan_id) REFERENCES loans(loan_id)
);

CREATE TABLE risk_assessment (
    risk_id VARCHAR(20) PRIMARY KEY,
    customer_id VARCHAR(20) NOT NULL,
    application_id VARCHAR(20) NOT NULL,
    debt_to_income_ratio DECIMAL(5,2),
    risk_score INT CHECK (risk_score BETWEEN 0 AND 100),
    risk_category VARCHAR(20),
    probability_of_default DECIMAL(5,3) CHECK (probability_of_default BETWEEN 0 AND 1),
    risk_decision VARCHAR(20), assessment_date DATE,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (application_id) REFERENCES loan_applications(application_id)
);

CREATE USER 'remote_user'@'%'
identified BY 'Abhi754989';
GRANT All privileges ON
bank_loan_analysis.* To 'remote_user'@'%';
FLUSH privileges;

-- LAYER 1 - Sanity Checks
-- 1. Volume check

SELECT COUNT(*) FROM customers;

SELECT COUNT(*) FROM loan_applications;

SELECT COUNT(*) FROM loan_defaults;

SELECT COUNT(*) FROM loans;

SELECT COUNT(*) FROM payments;

SELECT COUNT(*) FROM risk_assessment;

-- 2. Primary Key Uniqueness check 

SELECT customer_id 
FROM customers
GROUP BY customer_id
HAVING count(customer_id)>1;

SELECT application_id
FROM loan_applications
GROUP BY application_id
HAVING count(application_id)>1;

SELECT loan_id
FROM loan_defaults
GROUP BY loan_id
HAVING count(loan_id)>1;

SELECT payment_id
FROM payments
GROUP BY payment_id
HAVING count(payment_id)>1;

-- 3. Status Logic Validation

-- Rejected applications should not have loans

SELECT la.application_id, la.application_status, l.loan_id
FROM loan_applications AS la
LEFT JOIN loans AS l
ON la.application_id=l.application_id
WHERE la.application_status='Rejected';


-- Closed loans should not have future payments

SELECT l.loan_id, l.loan_status, p.payment_status,d.default_id
FROM loans AS l
LEFT JOIN payments AS p
ON l.loan_id=p.loan_id
LEFT JOIN loan_defaults AS d
ON l.loan_id=d.loan_id
WHERE l.loan_status='Closed';

-- LAYER 2 - DESCRIPTIVE ANALYTICS

/*
1. Overall Portfolio Size & Funnel
Business Question:
What is the overall size of the loan portfolio across customers, applications, and loans?
Analytical Focus:
Counts of customers, applications, approved loans, rejected applications, and defaults.
Challenge / Constraints:
Ensure rejected applications are not counted as loans; counts must reflect the true lending funnel.
*/

-- Total custiomers
SELECT COUNT(*) AS total_customers FROM customers;

-- Total applications 
SELECT count(application_id) AS total_applications FROM loan_applications;

-- Total Approved loans 
SELECT count(application_status) AS approved_applications
FROM loan_applications
WHERE application_status='Approved';

-- Total Rejected loans 
SELECT count(application_status) as rejected_applications
FROM loan_applications
WHERE application_status='Rejected';

-- Total Active loans
SELECT COUNT(loan_id) AS total_active_loans
FROM loans
WHERE loan_status <> 'Closed';

-- Total Defaults
SELECT COUNT(default_id) AS total_defaults
FROM loan_defaults;

/*
2. Loan Approval & Rejection Split
Business Question:
How are loan applications distributed between approved and rejected outcomes?
Analytical Focus:
Approval rate and rejection rate across all applications.
Challenge / Constraints:
Application status definitions must be consistently interpreted.
*/

SELECT 
ROUND((SELECT count(*) AS approved_applications
FROM loan_applications
WHERE application_status='Approved')*100
/
(SELECT count(*) FROM loan_applications),2) AS application_approval_rate
,
ROUND(
(SELECT count(*) AS approved_applications
FROM loan_applications
WHERE application_status='Rejected')*100
/
(SELECT count(*) FROM loan_applications),2) AS application_rejection_rate;

/*
3.  Portfolio Exposure Overview
Business Question:
What is the total financial exposure of the bank’s loan portfolio?
Analytical Focus:
Total disbursed amount, outstanding balance, and exposure by loan status.
Challenge / Constraints:
Closed loans should not inflate outstanding exposure.
*/

SELECT SUM(disbursed_amount) AS total_disbursed_amount,
(SELECT SUM(outstanding_balance) 
FROM loans
WHERE loan_status <> 'Closed') AS total_exposure_amount
FROM loans;

SELECT loan_status, 
SUM(outstanding_balance)  AS exposure_amount, 
ROUND(SUM(outstanding_balance)*100/(SELECT SUM(outstanding_balance) FROM loans WHERE loan_status <> 'Closed' ),2) 
AS exposure_rate
FROM loans
WHERE loan_status <> 'Closed'
GROUP BY loan_status;

-- High risk exposure % by delay
SELECT 
    ROUND(
        SUM(CASE WHEN p.days_delayed > 60 THEN l.outstanding_balance ELSE 0 END)
        * 100.0 / SUM(l.outstanding_balance),
    2) AS high_risk_exposure_pct
FROM loans l
JOIN payments p
    ON l.loan_id = p.loan_id
WHERE l.loan_status <> 'Closed';

/*
4. Loan Status Composition
Business Question:
How is the loan portfolio currently distributed by lifecycle status?
Analytical Focus:
Active, closed, and defaulted loans as a percentage of total loans.
Challenge / Constraints:
Loan status must align with closure dates and default records.
*/

SELECT
	loan_status,
	ROUND(COUNT(*)*100/(SELECT COUNT(*) FROM loans),2)
    AS loan_status_share
FROM loans
GROUP BY loan_status;

/*
5. Loan Type Mix
Business Question:
Which loan types dominate the portfolio in volume and value?
Analytical Focus:
Loan count and exposure split by loan type.
Challenge / Constraints:
High exposure concentration in one loan type should be clearly visible.
*/

SELECT 
	loan_type,
    COUNT(*) AS total_loan_type,
    ROUND(COUNT(*)*100/(SELECT COUNT(*) FROM loan_applications),2) 
    AS loan_type_share
 FROM loan_applications
 WHERE application_status='Approved'
 GROUP BY loan_type
 ORDER BY total_loan_type DESC;
 
 SELECT 
	a.loan_type, 
    COUNT(*) AS total_loan_type,
    ROUND(COUNT(*)*100/(SELECT COUNT(*) FROM loans),2)  AS loan_type_share,
    SUM(l.outstanding_balance) AS loan_exposure,
    ROUND(SUM(l.outstanding_balance)*100/
    (SELECT SUM(outstanding_balance) FROM loans WHERE loan_status <> 'CLOSED'),2)
    AS loan_exposure_pct
FROM loan_applications AS a
JOIN loans AS l
ON l.application_id=a.application_id
WHERE l.loan_status <> 'CLOSED'
GROUP BY a.loan_type
ORDER BY total_loan_type DESC;

/*
6. Customer Income Profile
Business Question:
What does the income distribution of customers income profile look like?
Analytical Focus:
Customers segmented into income bands.
Challenge / Constraints:
Income bands must be defined once and reused consistently across analyses.
*/

SELECT 
CASE
WHEN annual_income <= 700000 THEN 'Low_Income'
WHEN annual_income <= 2000000 THEN 'Medium_Income'
WHEN annual_income > 2000000 THEN 'High_Income'
END AS income_class,
COUNT(*) AS total_customers
FROM customers
GROUP BY income_class
ORDER BY total_customers DESC;

/*
Business Question:
What does the income distribution of customers income profile look like?
*/

SELECT 
CASE
WHEN c.annual_income <= 700000 THEN 'Low_Income'
WHEN c.annual_income <= 2000000 THEN 'Medium_Income'
WHEN c.annual_income > 2000000 THEN 'High_Income'
END AS income_class, 
count(a.application_status) AS loan_income_portfolio
FROM customers AS c
JOIN loan_applications AS a
ON c.customer_id=a.customer_id
WHERE a.application_status='Approved'
GROUP BY income_class;

/*
7. Credit Score Distribution
Business Question:
What is the credit quality profile of customers for every application?
Analytical Focus
Distribution of customers across credit score bands.
Challenge / Constraints:
Credit score at customer level vs application level must not be mixed.
*/

SELECT 
COUNT(*) AS applications,
CASE
WHEN credit_score_at_application IS NULL THEN 'Unknown'
WHEN credit_score_at_application < 580 Then 'Poor'
WHEN credit_score_at_application < 670 THEN 'Fair'
WHEN credit_score_at_application < 740 THEN 'Good'
WHEN credit_score_at_application < 800 THEN 'Very_Good'
ELSE 'Excellent'
END as credit_score_band,
ROUND(COUNT(*)*100
/
(SELECT count(*) FROM loan_applications),2) AS application_pct
FROM loan_applications
GROUP BY credit_score_band
ORDER BY applications DESC;

/*
8. Tenure Distribution
Business Question:
How are loans distributed across different tenure lengths?
Analytical Focus:
Loan counts and exposure by tenure buckets.
Challenge / Constraints:
Bucket definitions should reflect realistic lending horizons.
*/ 

SELECT 
COUNT(l.loan_id) AS loan_count,
CASE
WHEN a.tenure_months IS NULL THEN 'Unknown'
WHEN a.tenure_months <= 12 THEN 'Short_term'
WHEN a.tenure_months <= 36 THEN 'Mid_term'
WHEN a.tenure_months <= 60 THEN 'Long_term'
ELSE 'Very_long_term'
END AS tenure_terms,
SUM(l.outstanding_balance) AS exposure_amt,
ROUND(
	SUM(l.outstanding_balance)*100/(SELECT SUM(outstanding_balance) 
	FROM loans WHERE loan_status <> 'Closed'),2) AS exposure_amt_pct
FROM loans AS l
JOIN loan_applications AS a
ON a.application_id=l.application_id
WHERE l.loan_status <> 'Closed'
GROUP BY tenure_terms
ORDER BY exposure_amt_pct DESC;

-- LAYER 3 - DAIGNOSTIC ANALYTICS

/*
1 — Default Rate by Credit Score Band
Business Question:
Which credit score segments contribute disproportionately to loan defaults?
Diagnostic Focus:
Compare loan default rates across standardized credit score bands to identify high-risk credit segments.
*/

SELECT
CASE
WHEN a.credit_score_at_application IS NULL THEN 'Unknown'
WHEN a.credit_score_at_application < 580 Then 'Poor'
WHEN a.credit_score_at_application < 670 THEN 'Fair'
WHEN a.credit_score_at_application < 740 THEN 'Good'
WHEN a.credit_score_at_application < 800 THEN 'Very_Good'
ELSE 'Excellent'
END as credit_score_band,
COUNT(d.default_id) AS default_count,
ROUND(
	COUNT(d.default_id)*100/COUNT(l.loan_id),2) AS default_rate
FROM loans AS l
JOIN loan_applications AS a
ON l.application_id=a.application_id
LEFT JOIN loan_defaults AS d
ON l.loan_id=d.loan_id
GROUP BY credit_score_band
ORDER BY default_rate DESC ;

/*
2 — Default Rate by Tenure Bucket**
Business Question:
Does loan tenure length influence the likelihood of default?
Diagnostic Focus:
Evaluate default rates across standardized tenure buckets to assess whether longer repayment horizons increase risk.
*/

SELECT
CASE 
WHEN a.tenure_months IS NULL THEN 'Unknown'
WHEN a.tenure_months <= 12 THEN 'Short_term'
WHEN a.tenure_months <= 36 THEN 'Mid_term'
WHEN a.tenure_months <= 60 THEN 'Long_term'
ELSE 'Very_long_term'
END AS tenure_terms,
COUNT(l.loan_id) AS loans_count,
COUNT(d.default_id) AS default_count,
ROUND(
	COUNT(d.default_id)*100 /COUNT(l.loan_id),2) AS default_rate
FROM loans AS l
JOIN loan_applications AS a
ON a.application_id=l.application_id
LEFT JOIN loan_defaults AS d
ON l.loan_id=d.loan_id
GROUP BY tenure_terms
ORDER BY default_rate DESC;

/*
3 — Default Rate by Loan Type
Business Question:
Which loan products carry higher default risk?
Diagnostic Focus:
Measure default rates across loan types to identify product-level risk concentration.
*/

SELECT 
a.loan_type,
COUNT(d.default_id) AS default_count,
ROUND(
	COUNT(d.default_id)*100/COUNT(l.loan_id),2) AS default_rate
FROM loans AS l
JOIN loan_applications AS a
ON a.application_id=l.application_id
LEFT JOIN loan_defaults AS d
ON l.loan_id=d.loan_id
GROUP BY a.loan_type
ORDER BY default_rate DESC;

/*
4 — Default Rate by Risk Category
Business Question:
Do higher assigned risk categories actually translate into higher defaults?
Diagnostic Focus
Compare default rates across internal risk categories to validate the effectiveness of risk classification.
*/

SELECT 
r.risk_category,
COUNT(d.default_id) AS default_count,
round(COUNT(d.default_id)*100/COUNT(l.loan_id),2) AS default_rate
FROM loans AS l
JOIN loan_applications AS a
ON a.application_id=l.application_id
JOIN risk_assessment AS r
ON a.application_id=r.application_id
LEFT JOIN loan_defaults AS d
ON l.loan_id=d.loan_id
GROUP BY r.risk_category
ORDER BY default_rate DESC;

/*
5 — Approval Decision Quality Analysis
Business Question
Were high-risk customers approved while lower-risk customers were rejected?
Diagnostic Focus
Analyze approval and rejection outcomes relative to risk categories to identify decision inefficiencies.
*/

SELECT 
r.risk_category,
SUM(
	CASE
    WHEN a.application_status='Approved' THEN 1
    ELSE 0
    END) AS approved_count,
SUM(
	CASE
    WHEN a.application_status='Rejected' THEN 1
    ELSE 0
    END) AS rejected_count,
ROUND(SUM(
	CASE
    WHEN a.application_status='Approved' THEN 1
    ELSE 0
    END)/COUNT(*)*100,2) As approved_pct
FROM risk_assessment AS r
JOIN loan_applications AS a
ON r.application_id=a.application_id
GROUP BY r.risk_category; 

/*
6 — Payment Delinquency Before Default
Business Question:
Do defaulted loans exhibit early signs of payment stress before default?
Diagnostic Focus:
Examine payment delays and missed payments prior to default to detect early warning signals.
*/

SELECT 
	CASE 
		WHEN max_delay <= 30 THEN 'Low'
		WHEN max_delay <= 60 THEN 'Medium'
		ELSE 'High'
		END AS risk_by_delays,
	COUNT(*) AS default_count
FROM(
	SELECT 
		l.loan_id, 
		MAX(p.days_delayed) AS max_delay
        FROM loans as l
        JOiN payments AS p
        ON p.loan_id=l.loan_id
        JOIN loan_defaults AS d
        ON l.loan_id=d.loan_id
        GROUP BY l.loan_id) AS t
GROUP BY risk_by_delays;

/*
7 — Exposure at Risk by Payment Delay
Business Question
How much loan exposure is currently at risk due to delayed repayments?
Diagnostic Focus
Quantify outstanding exposure associated with delinquent payments to estimate potential future losses.
*/

SELECT 
	CASE 
		WHEN t.max_delay <= 30 THEN 'Low'
		WHEN t.max_delay <= 60 THEN 'Medium'
		ELSE 'High'
		END AS risk_by_delays,
        SUM(l.outstanding_balance) AS exposure_amt
FROM(
	SELECT 
		l.loan_id, 
		MAX(p.days_delayed) AS max_delay
        FROM loans as l
        JOiN payments AS p
        ON p.loan_id=l.loan_id
        JOIN loan_defaults AS d
        ON l.loan_id=d.loan_id
         WHERE l.loan_status <> 'Closed'
        GROUP BY l.loan_id) AS t
JOIN loans l 
    ON l.loan_id = t.loan_id
GROUP BY risk_by_delays
ORDER BY exposure_amt;

/*
8. Customer Exposure Ranking
Query:
Rank active loans by outstanding balance for customers.
*/

SELECT 
	c.customer_id,
    SUM(l.outstanding_balance) AS exposure_amt,
    RANK() OVER (ORDER BY SUM(l.outstanding_balance) DESC) AS exposure_rank
FROM 
	customers AS c
    JOIN loan_applications AS a
    ON a.customer_id=c.customer_id
    JOIN loans as l
    ON l.application_id=a.application_id
WHERE l.loan_status<>'Closed'
GROUP BY c.customer_id;

/*
9. Top Risk Contributors by Segment
Query:
Identify credit score, tenure, or loan type segments contributing the highest defaulted exposure.
Analytical Focus:
Segment-level risk contribution analysis using ranking and aggregation.
Challenge:
Combine default information with exposure and rank segments using window functions.
*/

WITH defaulted_exp AS 
(SELECT 
	CASE
		WHEN a.credit_score_at_application < 580 Then 'Poor'
		WHEN a.credit_score_at_application < 670 THEN 'Fair'
		WHEN a.credit_score_at_application < 740 THEN 'Good'
		WHEN a.credit_score_at_application < 800 THEN 'Very_Good'
		ELSE 'Excellent'
		END as credit_score_band,
	SUM(l.outstanding_balance) AS defaulted_exposure
    FROM loans AS l
    JOIN loan_defaults AS d
	ON l.loan_id=d.loan_id
    JOIN loan_applications AS a
    ON a.application_id=l.application_id
    GROUP BY credit_score_band),
    ranked_exp AS(
    SELECT credit_score_band, defaulted_exposure,
    RANK() OVER(ORDER BY defaulted_exposure DESC) AS def_rank,
    SUM(defaulted_exposure) OVER() AS total_def_exposure
    FROM defaulted_exp)
    SELECT 
		credit_score_band,
        defaulted_exposure,
        def_rank,
        ROUND(defaulted_exposure*100/total_def_exposure,2) AS cont_pct
	FROM ranked_exp;
    

        
        
    
    