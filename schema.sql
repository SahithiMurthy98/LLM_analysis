-- =============================================================================
-- CA Housing Price Analysis — MySQL Schema
-- Author: Sahithi Locharala
-- Database: locharv_cap1 (mysql.clarksonmsda.org)
--
-- Extends the existing ca_median_prices table with:
--   1. ca_actual_prices  — real CAR housing data (from HomeMedianPrices.csv)
--   2. ca_quality_audit  — per-run validation audit log
--   3. 7 KPI views built directly on your real tables
-- =============================================================================

USE locharv_cap1;

-- CREATE TABLE ca_median_prices (
--     id          INT AUTO_INCREMENT PRIMARY KEY,
--     model       VARCHAR(100),       -- 'llama2', 'llama3.1:latest', 'codellama:7b', 'gemma3', 'llama3.1'
--     month       VARCHAR(10),        -- 'YYYY-MM'
--     price_usd   DECIMAL(12,2),      -- LLM-generated price
--     area        VARCHAR(150),       -- e.g. 'Los Angeles'
--     run_id      INT,
--     inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
-- );

-- ---------------------------------------------------------------------------
-- NEW TABLE 1: Actual (real-world) CA housing prices
-- Loaded from: MedianPricesofExistingDetachedHomesHistoricalData.csv
-- Key column used in notebook: "LA Metro" renamed to actual_price_usd
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ca_actual_prices (
    id               INT AUTO_INCREMENT PRIMARY KEY,
    month            VARCHAR(10)    NOT NULL,        -- 'YYYY-MM', matches ca_median_prices.month
    area             VARCHAR(150)   NOT NULL,         -- e.g. 'Los Angeles', 'CA'
    actual_price_usd DECIMAL(12,2)  NOT NULL,
    data_source      VARCHAR(200)   DEFAULT 'CAR Median Prices of Existing Detached Homes',
    loaded_at        TIMESTAMP      DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_actual_month_area (month, area)
);

-- ---------------------------------------------------------------------------
-- NEW TABLE 2: Data quality audit log
-- One row per validation check per run, written by log_quality_check() in notebook
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ca_quality_audit (
    log_id           INT AUTO_INCREMENT PRIMARY KEY,
    run_id           INT            NOT NULL,
    model            VARCHAR(100),
    area             VARCHAR(150),
    check_name       VARCHAR(150)   NOT NULL,         -- e.g. 'null_price_check'
    records_checked  INT,
    records_failed   INT,
    failure_rate     DECIMAL(7,4),
    severity         ENUM('info','warning','critical') DEFAULT 'info',
    logged_at        TIMESTAMP      DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------------
-- KPI VIEWS
-- All built on ca_median_prices (your real LLM output table) +
-- ca_actual_prices (real CAR data).
-- month column is VARCHAR 'YYYY-MM' in both tables — joined on month + area.
-- ---------------------------------------------------------------------------

-- KPI 1: Monthly accuracy — actual vs avg LLM price per model & area
-- Mirrors notebook logic: difference = actual - llm, percent_error = difference/actual * 100
CREATE OR REPLACE VIEW vw_kpi_monthly_accuracy AS
SELECT
    a.area,
    a.month,
    a.actual_price_usd,
    s.model,
    ROUND(AVG(s.price_usd), 2)                                       AS avg_llm_price,
    ROUND(a.actual_price_usd - AVG(s.price_usd), 2)                  AS price_difference,
    ROUND(
        (a.actual_price_usd - AVG(s.price_usd))
        / NULLIF(a.actual_price_usd, 0) * 100, 2
    )                                                                 AS percent_error,
    ROUND(
        ABS(a.actual_price_usd - AVG(s.price_usd))
        / NULLIF(a.actual_price_usd, 0) * 100, 2
    )                                                                 AS abs_pct_error,
    COUNT(s.id)                                                       AS llm_sample_count
FROM ca_actual_prices  a
JOIN ca_median_prices  s ON s.area  = a.area
                         AND s.month = a.month
GROUP BY a.area, a.month, a.actual_price_usd, s.model;


-- KPI 2: Model leaderboard — overall MAPE per model across all months
CREATE OR REPLACE VIEW vw_kpi_model_leaderboard AS
SELECT
    s.model,
    COUNT(DISTINCT s.run_id)                                          AS total_runs,
    COUNT(s.id)                                                       AS total_predictions,
    ROUND(AVG(
        ABS(a.actual_price_usd - s.price_usd)
        / NULLIF(a.actual_price_usd, 0) * 100
    ), 2)                                                             AS overall_mape_pct,
    ROUND(AVG(a.actual_price_usd - s.price_usd), 0)                  AS avg_bias_dollars,
    CASE
        WHEN AVG(a.actual_price_usd - s.price_usd) > 0 THEN 'LLM_UNDERSHOOTS'
        WHEN AVG(a.actual_price_usd - s.price_usd) < 0 THEN 'LLM_OVERSHOOTS'
        ELSE 'NEUTRAL'
    END                                                               AS bias_direction,
    RANK() OVER (
        ORDER BY AVG(ABS(a.actual_price_usd - s.price_usd)
                     / NULLIF(a.actual_price_usd, 0) * 100)
    )                                                                 AS accuracy_rank
FROM ca_median_prices  s
JOIN ca_actual_prices  a ON a.area  = s.area
                         AND a.month = s.month
GROUP BY s.model;


-- KPI 3: Quarterly trend — QoQ avg price growth, actual vs LLM per model
CREATE OR REPLACE VIEW vw_kpi_quarterly_trend AS
WITH quarterly AS (
    SELECT
        s.model,
        s.area,
        LEFT(s.month, 4)                                                        AS yr,
        QUARTER(STR_TO_DATE(CONCAT(s.month, '-01'), '%Y-%m-%d'))                AS qtr,
        ROUND(AVG(a.actual_price_usd), 0)                                       AS avg_actual,
        ROUND(AVG(s.price_usd), 0)                                              AS avg_llm
    FROM ca_median_prices  s
    JOIN ca_actual_prices  a ON a.area  = s.area
                             AND a.month = s.month
    GROUP BY s.model, s.area,
             LEFT(s.month, 4),
             QUARTER(STR_TO_DATE(CONCAT(s.month, '-01'), '%Y-%m-%d'))
)
SELECT
    model, area, yr, qtr,
    avg_actual,
    avg_llm,
    ROUND(avg_actual - avg_llm, 0)                                              AS quarterly_price_diff,
    ROUND(
        (avg_actual - LAG(avg_actual) OVER (PARTITION BY model, area ORDER BY yr, qtr))
        / NULLIF(LAG(avg_actual) OVER (PARTITION BY model, area ORDER BY yr, qtr), 0) * 100,
        2
    )                                                                           AS actual_qoq_growth_pct,
    ROUND(
        (avg_llm - LAG(avg_llm) OVER (PARTITION BY model, area ORDER BY yr, qtr))
        / NULLIF(LAG(avg_llm) OVER (PARTITION BY model, area ORDER BY yr, qtr), 0) * 100,
        2
    )                                                                           AS llm_qoq_growth_pct
FROM quarterly;


-- KPI 4: Variance suppression — does LLM smooth out real price volatility?
CREATE OR REPLACE VIEW vw_kpi_variance_suppression AS
SELECT
    s.model,
    s.area,
    ROUND(STDDEV(a.actual_price_usd), 0)                             AS actual_stddev,
    ROUND(STDDEV(s.price_usd), 0)                                    AS llm_stddev,
    ROUND(AVG(a.actual_price_usd), 0)                                AS actual_avg,
    ROUND(AVG(s.price_usd), 0)                                       AS llm_avg,
    ROUND(STDDEV(a.actual_price_usd)
          / NULLIF(AVG(a.actual_price_usd), 0) * 100, 2)             AS actual_cv_pct,
    ROUND(STDDEV(s.price_usd)
          / NULLIF(AVG(s.price_usd), 0) * 100, 2)                    AS llm_cv_pct,
    ROUND(
        1 - STDDEV(s.price_usd) / NULLIF(STDDEV(a.actual_price_usd), 0),
        4
    )                                                                 AS variance_suppression_ratio,
    CASE
        WHEN 1 - STDDEV(s.price_usd)/NULLIF(STDDEV(a.actual_price_usd),0) > 0.3
             THEN 'HIGH_SMOOTHING'
        WHEN 1 - STDDEV(s.price_usd)/NULLIF(STDDEV(a.actual_price_usd),0) > 0.1
             THEN 'MODERATE_SMOOTHING'
        ELSE 'LOW_SMOOTHING'
    END                                                               AS smoothing_label
FROM ca_median_prices  s
JOIN ca_actual_prices  a ON a.area  = s.area
                         AND a.month = s.month
GROUP BY s.model, s.area;


-- KPI 5: Run-level quality scorecard — flags nulls and out-of-range prices per run
-- Out-of-range threshold: < $100k or > $5M (reasonable for CA)
CREATE OR REPLACE VIEW vw_kpi_run_quality AS
SELECT
    run_id,
    model,
    area,
    COUNT(*)                                                          AS total_records,
    SUM(CASE WHEN price_usd IS NULL THEN 1 ELSE 0 END)               AS null_prices,
    SUM(CASE WHEN price_usd < 100000
              OR price_usd > 5000000 THEN 1 ELSE 0 END)              AS out_of_range,
    SUM(CASE WHEN price_usd IS NOT NULL
              AND price_usd BETWEEN 100000 AND 5000000
              THEN 1 ELSE 0 END)                                      AS valid_records,
    ROUND(
        SUM(CASE WHEN price_usd IS NOT NULL
                  AND price_usd BETWEEN 100000 AND 5000000
                  THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0) * 100, 2
    )                                                                 AS validity_rate_pct,
    CASE
        WHEN SUM(CASE WHEN price_usd IS NOT NULL
                       AND price_usd BETWEEN 100000 AND 5000000
                       THEN 1 ELSE 0 END)
             / NULLIF(COUNT(*), 0) >= 0.95 THEN 'PASS'
        WHEN SUM(CASE WHEN price_usd IS NOT NULL
                       AND price_usd BETWEEN 100000 AND 5000000
                       THEN 1 ELSE 0 END)
             / NULLIF(COUNT(*), 0) >= 0.80 THEN 'WARN'
        ELSE 'FAIL'
    END                                                               AS quality_gate
FROM ca_median_prices
GROUP BY run_id, model, area;


-- KPI 6: Seasonal bias — does LLM error peak in specific calendar months?
CREATE OR REPLACE VIEW vw_kpi_seasonal_bias AS
SELECT
    s.model,
    s.area,
    MONTH(STR_TO_DATE(CONCAT(s.month, '-01'), '%Y-%m-%d'))           AS month_num,
    MONTHNAME(STR_TO_DATE(CONCAT(s.month, '-01'), '%Y-%m-%d'))       AS month_name,
    ROUND(AVG(a.actual_price_usd - s.price_usd), 0)                  AS avg_bias_dollars,
    ROUND(AVG(ABS(a.actual_price_usd - s.price_usd)
              / NULLIF(a.actual_price_usd, 0) * 100), 2)             AS avg_abs_pct_error,
    COUNT(*)                                                          AS observations
FROM ca_median_prices  s
JOIN ca_actual_prices  a ON a.area  = s.area
                         AND a.month = s.month
GROUP BY s.model, s.area,
         MONTH(STR_TO_DATE(CONCAT(s.month,'-01'),'%Y-%m-%d')),
         MONTHNAME(STR_TO_DATE(CONCAT(s.month,'-01'),'%Y-%m-%d'))
ORDER BY s.model, month_num;


-- KPI 7: Annual summary — year-level avg price, bias, and MAPE per model
CREATE OR REPLACE VIEW vw_kpi_annual_summary AS
SELECT
    s.model,
    s.area,
    LEFT(s.month, 4)                                                  AS year,
    ROUND(AVG(a.actual_price_usd), 0)                                 AS avg_actual_price,
    ROUND(AVG(s.price_usd), 0)                                        AS avg_llm_price,
    ROUND(AVG(a.actual_price_usd - s.price_usd), 0)                   AS avg_bias_dollars,
    ROUND(AVG(ABS(a.actual_price_usd - s.price_usd)
              / NULLIF(a.actual_price_usd, 0) * 100), 2)              AS annual_mape_pct,
    COUNT(DISTINCT s.month)                                            AS months_covered
FROM ca_median_prices  s
JOIN ca_actual_prices  a ON a.area  = s.area
                         AND a.month = s.month
GROUP BY s.model, s.area, LEFT(s.month, 4)
ORDER BY s.model, year;
