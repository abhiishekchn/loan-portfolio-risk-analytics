-- =============================================
-- Bank Loan Portfolio Risk Analytics
-- Final Analysis Queries
-- =============================================
-- This file contains the finalized SQL queries
-- used to build the Power BI dashboard and
-- derive business insights.
-- =============================================


-- ======================================================
-- 1. PORTFOLIO OVERVIEW METRICS
-- ======================================================

-- Total active loans
SELECT COUNT(*) AS total_active_loans
FROM loans
WHERE loan_status <> 'Closed';

-- Application approval and rejection rates
SELECT
    ROUND(SUM(CASE WHEN application_status = 'Approved' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
        AS approval_rate_pct,
    ROUND(SUM(CASE WHEN application_status = 'Rejected' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
        AS rejection_rate_pct
FROM loan_applications;

-- Default rate on active loans
SELECT
    ROUND(COUNT(DISTINCT d.loan_id) * 100.0 / COUNT(DISTINCT l.loan_id), 2)
        AS default_rate_pct
FROM loans l
LEFT JOIN loan_defaults d
    ON l.loan_id = d.loan_id
WHERE l.loan_status <> 'Closed';

-- Loan status composition
SELECT
    loan_status,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM loans), 2) AS loan_status_share_pct
FROM loans
GROUP BY loan_status;


-- ======================================================
-- 2. RISK SEGMENTATION ANALYSIS
-- ======================================================

-- Default rate by credit score band
SELECT
    CASE
        WHEN a.credit_score_at_application IS NULL THEN 'Unknown'
        WHEN a.credit_score_at_application < 580 THEN 'Poor'
        WHEN a.credit_score_at_application < 670 THEN 'Fair'
        WHEN a.credit_score_at_application < 740 THEN 'Good'
        WHEN a.credit_score_at_application < 800 THEN 'Very_Good'
        ELSE 'Excellent'
    END AS credit_score_band,
    COUNT(d.default_id) AS default_count,
    ROUND(COUNT(d.default_id) * 100.0 / COUNT(l.loan_id), 2) AS default_rate_pct
FROM loans l
JOIN loan_applications a
    ON l.application_id = a.application_id
LEFT JOIN loan_defaults d
    ON l.loan_id = d.loan_id
GROUP BY credit_score_band
ORDER BY default_rate_pct DESC;

-- Default rate by loan tenure bucket
SELECT
    CASE
        WHEN a.tenure_months <= 12 THEN 'Short_term'
        WHEN a.tenure_months <= 36 THEN 'Mid_term'
        WHEN a.tenure_months <= 60 THEN 'Long_term'
        ELSE 'Very_long_term'
    END AS tenure_bucket,
    ROUND(COUNT(d.default_id) * 100.0 / COUNT(l.loan_id), 2) AS default_rate_pct
FROM loans l
JOIN loan_applications a
    ON l.application_id = a.application_id
LEFT JOIN loan_defaults d
    ON l.loan_id = d.loan_id
GROUP BY tenure_bucket
ORDER BY default_rate_pct DESC;

-- Default rate by loan type
SELECT
    a.loan_type,
    ROUND(COUNT(d.default_id) * 100.0 / COUNT(l.loan_id), 2) AS default_rate_pct
FROM loans l
JOIN loan_applications a
    ON l.application_id = a.application_id
LEFT JOIN loan_defaults d
    ON l.loan_id = d.loan_id
GROUP BY a.loan_type
ORDER BY default_rate_pct DESC;


-- ======================================================
-- 3. DECISION QUALITY ANALYSIS
-- ======================================================

-- Approval vs rejection by risk category
SELECT
    r.risk_category,
    SUM(CASE WHEN a.application_status = 'Approved' THEN 1 ELSE 0 END) AS approved_count,
    SUM(CASE WHEN a.application_status = 'Rejected' THEN 1 ELSE 0 END) AS rejected_count,
    ROUND(
        SUM(CASE WHEN a.application_status = 'Approved' THEN 1 ELSE 0 END) * 100.0
        / COUNT(*),
    2) AS approval_rate_pct
FROM loan_applications a
JOIN risk_assessment r
    ON a.application_id = r.application_id
GROUP BY r.risk_category
ORDER BY r.risk_category;


-- ======================================================
-- 4. EARLY WARNING & DELINQUENCY SIGNALS
-- ======================================================

-- Delinquency severity prior to default
SELECT
    CASE
        WHEN max_delay <= 30 THEN 'Low'
        WHEN max_delay <= 60 THEN 'Medium'
        ELSE 'High'
    END AS delinquency_risk_level,
    COUNT(*) AS defaulted_loans
FROM (
    SELECT
        l.loan_id,
        MAX(p.days_delayed) AS max_delay
    FROM loans l
    JOIN payments p
        ON l.loan_id = p.loan_id
    JOIN loan_defaults d
        ON l.loan_id = d.loan_id
    GROUP BY l.loan_id
) t
GROUP BY delinquency_risk_level
ORDER BY delinquency_risk_level;

-- Exposure at risk by delinquency severity
SELECT
    CASE
        WHEN t.max_delay <= 30 THEN 'Low'
        WHEN t.max_delay <= 60 THEN 'Medium'
        ELSE 'High'
    END AS delinquency_risk_level,
    SUM(l.outstanding_balance) AS exposure_amount
FROM (
    SELECT
        l.loan_id,
        MAX(p.days_delayed) AS max_delay
    FROM loans l
    JOIN payments p
        ON l.loan_id = p.loan_id
    GROUP BY l.loan_id
) t
JOIN loans l
    ON l.loan_id = t.loan_id
WHERE l.loan_status <> 'Closed'
GROUP BY delinquency_risk_level
ORDER BY exposure_amount DESC;

