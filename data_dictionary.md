# Data Dictionary — LLM Synthetic Data Analysis

**Project:** LLM-Based Synthetic Data Generation & Evaluation  
**Author:** Sahithi Locharala  
**Database:** `locharv_cap1` · `mysql.clarksonmsda.org`  
**Last updated:** May 2026

This document defines every table, column, validation rule, derived metric, and KPI used across the project. All analytical outputs — charts, statistical tests, KPI views — are computed from these definitions. Any downstream consumer of this data should treat this file as the single source of truth for field semantics.

---

## Contents

1. [Source Data](#1-source-data)
2. [Database Tables](#2-database-tables)
3. [Derived / Computed Fields](#3-derived--computed-fields)
4. [Validation Rules](#4-validation-rules)
5. [KPI Definitions](#5-kpi-definitions)
6. [Hallucination Classification](#6-hallucination-classification)
7. [Model Registry](#7-model-registry)
8. [Null & Sparsity Policy](#8-null--sparsity-policy)

---

## 1. Source Data

### 1.1 `HomeMedianPrices.csv`

**Origin:** California Association of Realtors (CAR) — *Median Prices of Existing Detached Homes*  
**Produced by:** `CA_housing_price.ipynb` (raw CSV cleaned and exported)  
**Coverage:** January 1990 – August 2025 (428 monthly rows)  
**Format:** Wide — one row per month, one column per region  
**Used in:** `lamaClientadv.ipynb`, `kpi_analysis.ipynb`

| Column | Type | Description | Example |
|---|---|---|---|
| `Mon-Yr` | string | Original month label before date parsing. Format varies: `Jan-1990`, `9-Sep`. Cleaned by `normalize_mon_year()`. | `Jan-2023` |
| `Date` | string `YYYY-MM` | Parsed, normalized month string. Used as the join key with `ca_median_prices.month`. | `2023-01` |
| `CA` | float | Statewide California median price (USD). Represents all property types statewide. | `835000.0` |
| `Los Angeles` | float | County-level median price for Los Angeles County. **Primary comparison column** in this project. | `800000.0` |
| `LA Metro` | float | Metro-area aggregate covering Los Angeles metro region. Slightly different geographic boundary than `Los Angeles` county column. | `760000.0` |
| `S.F. Bay Area` | float | Bay Area metro aggregate. | `1250000.0` |
| `San Diego` | float | San Diego County median price. | `880000.0` |
| `Orange` | float | Orange County median price. | `950000.0` |
| `Sacramento` | float | Sacramento County median price. | `510000.0` |
| `Riverside` | float | Riverside County (Inland Empire) median price. | `490000.0` |
| `San Francisco` | float | City/County of San Francisco median price. | `1400000.0` |
| `Central Coast` | float | Regional aggregate: Santa Barbara, San Luis Obispo, Santa Cruz, Monterey. | `820000.0` |
| `Central Valley` | float | Regional aggregate: Fresno, Kern, Kings, Madera, Merced, Stanislaus, Tulare. | `370000.0` |
| `Inland Empire` | float | Regional aggregate: Riverside and San Bernardino counties. | `495000.0` |
| `SoCal` | float | Southern California regional aggregate. | `720000.0` |
| `Far North` | float | Northern rural regional aggregate. High null rate (312/428 months missing). | `380000.0` |
| `Condo` | float | Statewide median price for condominiums (not detached homes). | `550000.0` |
| *(county columns)* | float | 40+ individual county columns (Alameda, Butte, Fresno, etc.). Sparsity varies — rural counties have large null gaps in early years. | — |

**Price range (validated):**

| Region | Min (USD) | Max (USD) |
|---|---|---|
| CA statewide | 167,790 | 910,160 |
| Los Angeles county | 154,313 | 960,370 |
| LA Metro | 163,596 | 855,000 |

**Sparsity notes:** Trinity (349/428 null), Imperial (348/428 null), Far North (312/428 null) have large gaps and should not be used as primary analysis columns without imputation or explicit acknowledgment.

---

### 1.2 `rotten_tomatoes_movies.csv`

**Origin:** Kaggle — Rotten Tomatoes Movies & Critic Reviews dataset  
**Used in:** `movie_analysis.ipynb` (validation comparison)  
**Role:** Ground-truth source for movie metadata. Used to look up `rotten_tomatoes_link` by `movie_title`, which then joins to the critic reviews dataset.

| Column | Type | Description |
|---|---|---|
| `movie_title` | string | Full movie title as listed on Rotten Tomatoes. Case-sensitive for joins. |
| `rotten_tomatoes_link` | string | URL path segment — serves as a unique movie identifier (e.g. `/m/percy_jackson`). Used as foreign key to join critic reviews. |
| *(other columns)* | mixed | Genre, directors, release dates, audience scores — present but not used in this project's primary analysis. |

**Key usage pattern:**
```python
movie_id = movie_df.loc[movie_df["movie_title"] == movie_name, "rotten_tomatoes_link"].iloc[0]
val_sub  = val_df[val_df["rotten_tomatoes_link"] == movie_id]
```

---

## 2. Database Tables

### 2.1 `ca_median_prices`

**Database:** `locharv_cap1`  
**Purpose:** Stores every LLM-generated housing price record produced by the Flask API pipeline.  
**Populated by:** `store_in_db_prices()` in `lamaClientadv.ipynb`  
**Primary key:** `(run_id, month)`

| Column | Type | Nullable | Description | Example |
|---|---|---|---|---|
| `run_id` | `VARCHAR(14)` | NO | Timestamp-based generation run identifier. Format: `YYYYMMDDHHmmSS`. Each API call that produces a batch of prices shares one `run_id`. Enables run-level reproducibility and auditability. | `20250115143022` |
| `month` | `CHAR(7)` | NO | Month of the generated price. Format: `YYYY-MM`. Matches `HomeMedianPrices.csv`'s `Date` column exactly — this is the join key for actual-vs-synthetic comparisons. | `2023-01` |
| `median_price_usd` | `INT` | NO | LLM-generated median housing price in USD (whole dollars). Validated range: 100,000–5,000,000. Values outside this range are flagged in `vw_kpi_run_quality`. | `765000` |
| `source` | `VARCHAR(64)` | YES | Identifies which API endpoint produced the record. `'flask_primary'` = port 5001, `'flask_fallback'` = port 5000. Populated from `source_used` flag in the client. | `flask_primary` |
| `version` | `VARCHAR(32)` | YES | The Ollama model string that generated this record. See [Model Registry](#7-model-registry) for valid values. | `llama3.1:8b` |
| `source_used` | `BOOLEAN` | YES | `TRUE` if the primary endpoint (port 5001) was used; `FALSE` if the fallback (port 5000) was used. Useful for filtering runs that may have degraded model behavior. | `TRUE` |
| `inserted_at` | `TIMESTAMP` | NO | UTC timestamp of DB insertion. Default: `CURRENT_TIMESTAMP`. Used for temporal drift analysis — ordering runs chronologically. | `2025-01-15 14:30:22` |
| `Area` | `VARCHAR(50)` | YES | Geographic area for the generated price. In this project always `'Los Angeles'`. Included for future multi-area extensibility. | `Los Angeles` |

**Indexes:**
- `PRIMARY KEY (run_id, month)` — prevents duplicate months per run; `ON DUPLICATE KEY UPDATE` overwrites on re-run
- `KEY idx_month (month)` — optimizes joins against `ca_actual_prices` on `month`

---

### 2.2 `ca_actual_prices`

**Database:** `locharv_cap1`  
**Purpose:** Stores real CAR housing prices loaded from `HomeMedianPrices.csv`. Acts as the ground-truth reference for all accuracy and error KPIs.  
**Populated by:** ETL cell in `kpi_analysis.ipynb` (`ca_actual_prices` ETL section)  
**Unique constraint:** `(month, area)` — one actual price per month per region

| Column | Type | Nullable | Description | Example |
|---|---|---|---|---|
| `id` | `INT AUTO_INCREMENT` | NO | Surrogate primary key. | `1` |
| `month` | `VARCHAR(10)` | NO | Month in `YYYY-MM` format. **Join key** to `ca_median_prices.month`. | `2023-01` |
| `area` | `VARCHAR(150)` | NO | Geographic area name. Must match `ca_median_prices.Area` exactly for joins. `'Los Angeles'` maps from the `Los Angeles` column in the CSV (county-level, not metro aggregate). | `Los Angeles` |
| `actual_price_usd` | `DECIMAL(12,2)` | NO | Real-world median price in USD from CAR data. Stored as-is after validation (100,000–5,000,000 range filter applied at load time). | `800000.00` |
| `data_source` | `VARCHAR(200)` | YES | Documents origin of the actual data. Default: `'CAR Median Prices of Existing Detached Homes'`. | `CAR Median Prices of Existing Detached Homes` |
| `loaded_at` | `TIMESTAMP` | NO | UTC timestamp of ETL load. Useful for detecting stale reference data. | `2026-05-01 10:00:00` |

---

### 2.3 `movie_reviews`

**Database:** `locharv_cap1`  
**Purpose:** Stores every LLM-generated movie review and rating produced by the Flask review API.  
**Populated by:** `store_in_db_reviews()` in `movie_analysis.ipynb`  
**Primary key:** `movie_id` (auto-increment)

| Column | Type | Nullable | Description | Example |
|---|---|---|---|---|
| `movie_id` | `INT AUTO_INCREMENT` | NO | Surrogate primary key. Auto-generated by MySQL; excluded from inserts. | `142` |
| `run_id` | `VARCHAR(14)` | NO | Timestamp-based generation run identifier. Format: `YYYYMMDDHHmmSS`. All 10 reviews in a single API batch share one `run_id`. | `20250120091500` |
| `model` | `VARCHAR(64)` | NO | Ollama model that generated this review. Truncated to 64 chars at insert. See [Model Registry](#7-model-registry). | `gemma3` |
| `movie_title` | `VARCHAR(256)` | YES | Full movie title passed to the LLM prompt. Stored verbatim — used for grouping and validation joins. | `Percy Jackson & the Olympians: The Lightning Thief` |
| `ratings` | `VARCHAR(10)` | YES | **Raw LLM output** for the rating field — stored as-is before cleaning. May contain formats like `"4"`, `"4/5"`, `"3.5/5"`, `"Rating: 4 out of 10"`, or non-numeric strings. Never assume this is a clean float. | `4/5` |
| `review_text` | `TEXT` | YES | Full generated review body (50–100 words target). Stored verbatim. | `"A fun adventure film..."` |
| `inserted_at` | `TIMESTAMP` | NO | UTC timestamp of DB insertion. Used for temporal drift analysis across runs. | `2025-01-20 09:15:00` |

**Important:** `ratings` is always raw. All numeric analysis uses the `clean_rating()` function in `movie_analysis.ipynb` to produce a normalized float before any computation.

---

### 2.4 `ca_quality_audit`

**Database:** `locharv_cap1`  
**Purpose:** Audit log — one row per data quality check per run. Written by `log_quality_check()` in `kpi_analysis.ipynb` after each generation batch.  
**Primary key:** `log_id` (auto-increment)

| Column | Type | Nullable | Description | Example |
|---|---|---|---|---|
| `log_id` | `INT AUTO_INCREMENT` | NO | Surrogate primary key. | `1` |
| `run_id` | `INT` | NO | References the run being audited. | `20250115143022` |
| `model` | `VARCHAR(100)` | YES | Model version being audited. | `llama3.1:8b` |
| `area` | `VARCHAR(150)` | YES | Geographic area being audited. | `Los Angeles` |
| `check_name` | `VARCHAR(150)` | NO | Name of the validation check performed. Standardized values: `null_price_check`, `out_of_range_check`. | `out_of_range_check` |
| `records_checked` | `INT` | YES | Total records evaluated in this check. | `28` |
| `records_failed` | `INT` | YES | Count of records that failed the check. | `0` |
| `failure_rate` | `DECIMAL(7,4)` | YES | `records_failed / records_checked`. Stored as a decimal (0.0714 = 7.14%). | `0.0000` |
| `severity` | `ENUM` | NO | `'info'` — check passed or informational. `'warning'` — failure rate > 0, non-critical. `'critical'` — failure rate exceeds threshold or structural issue. | `info` |
| `logged_at` | `TIMESTAMP` | NO | UTC timestamp of audit record creation. | `2026-05-01 10:05:00` |

---

## 3. Derived / Computed Fields

These fields do not exist in the database. They are computed in notebooks or KPI views at query time.

### Housing domain

| Field name | Computed in | Formula | Description |
|---|---|---|---|
| `price_difference` | `kpi_analysis.ipynb`, `vw_kpi_monthly_accuracy` | `actual_price_usd − avg(median_price_usd)` | Signed difference between real and LLM price. Positive = LLM undershot; negative = LLM overshot. |
| `abs_error` | `lamaClientadv.ipynb` | `\|median_price_usd − actual_price\|` | Absolute prediction error in USD for a single record. |
| `pct_error` | `lamaClientadv.ipynb` | `abs_error / actual_price × 100` | Percentage error for a single record. |
| `percent_error` | `vw_kpi_monthly_accuracy` | `(actual − avg_llm) / actual × 100` | Signed percentage error at the monthly aggregate level. |
| `abs_pct_error` | `vw_kpi_monthly_accuracy` | `\|percent_error\|` | Unsigned percentage error — basis for MAPE. |
| `overall_mape_pct` | `vw_kpi_model_leaderboard` | `AVG(abs_pct_error)` across all months and areas | Mean Absolute Percentage Error — primary model accuracy KPI. Lower is better. |
| `avg_bias_dollars` | `vw_kpi_model_leaderboard` | `AVG(actual − llm_price)` | Average signed price bias in USD. Positive = systematic underestimation. |
| `actual_qoq_growth_pct` | `vw_kpi_quarterly_trend` | `(current_qtr_avg − prev_qtr_avg) / prev_qtr_avg × 100` | Quarter-over-quarter price growth rate using SQL `LAG()` window function. |
| `variance_suppression_ratio` | `vw_kpi_variance_suppression` | `1 − STDDEV(llm) / STDDEV(actual)` | Measures how much real-world price volatility the LLM smooths out. 0 = no smoothing; 1 = LLM produces constant values. Values > 0.3 are flagged `HIGH_SMOOTHING`. |
| `block` | `lamaClientadv.ipynb` | `row_index // block_size` | Groups rows into sequential era-blocks (20 or 50 observations) for block-level bias analysis — avoids needing exact date cut points. |

### Movie domain

| Field name | Computed in | Formula | Description |
|---|---|---|---|
| `ratings` (cleaned) | `movie_analysis.ipynb`, `clean_rating()` | See parsing rules below | Normalized float from raw `ratings` string. |
| `is_hallucination` | `movie_analysis.ipynb` | `cleaned_rating < 1 OR cleaned_rating > 5` | Boolean flag. Ratings outside 1–5 are structurally invalid for the defined scale and are classified as hallucinations. |
| `word_count` | `movie_analysis.ipynb` | `len(review_text.split())` | Word count of the generated review body. Target range: 50–100 words. |
| `stability_score` | `movie_analysis.ipynb` | `1 / STDDEV(ratings)` per model | Higher = more consistent ratings across reviews. A model with zero variance produces an infinite stability score (constant rating). |
| `rating_entropy` | `movie_analysis.ipynb`, `scipy.stats.entropy` | Shannon entropy (base 2) of rating value distribution | Measures diversity of ratings per model. High entropy = varied ratings; low entropy = model clusters on a few values; 0 entropy = single repeated rating. |
| `val_rating` | `movie_analysis.ipynb`, `clean_review_score_to_float()` | Parsed from critic `review_score` field | Normalized float from Rotten Tomatoes critic review scores, on a 0–5 scale after normalization. Used as ground truth for validation comparison. |

---

## 4. Validation Rules

These rules are applied at ingestion time (in pipeline functions) and re-checked at query time (in KPI views). Records that fail are not deleted — they are flagged.

### Housing prices

| Rule | Logic | Action on failure |
|---|---|---|
| Non-null price | `median_price_usd IS NOT NULL` | Record inserted with NULL price; flagged in `vw_kpi_run_quality` as `null_prices`. |
| Positive price | `median_price_usd > 0` | Prices ≤ 0 excluded from all KPI view joins (`is_valid` filter). |
| Plausible range | `100,000 ≤ median_price_usd ≤ 5,000,000` | Values outside this range are counted as `out_of_range` in `vw_kpi_run_quality` and excluded from accuracy KPIs. Threshold rationale: no California county median has been below $100K since the late 1990s; no county median has exceeded $5M. |
| Valid month format | `month LIKE 'YYYY-MM'` | Enforced at client side before insert; non-conforming values raise a parse error. |
| No duplicate month per run | `PRIMARY KEY (run_id, month)` | Duplicate insert triggers `ON DUPLICATE KEY UPDATE` — latest value wins. |

### Movie ratings

| Rule | Logic | Action on failure |
|---|---|---|
| Non-null rating | `ratings IS NOT NULL` | Stored as NULL; excluded from all numeric analysis after `clean_rating()` returns `NaN`. |
| Parseable as number | `clean_rating()` must return a float | Returns `NaN` on failure; excluded downstream. |
| Valid scale (1–5) | `1.0 ≤ cleaned_rating ≤ 5.0` | Values outside range are classified as **hallucinations** (see [Section 6](#6-hallucination-classification)). Retained in DB but flagged. |
| IQR outlier check | Standard IQR method: values below `Q1 − 1.5×IQR` or above `Q3 + 1.5×IQR` | Flagged as statistical outliers in `movie_analysis.ipynb`. Not excluded — reported separately from hallucinations. |

### Quality gate thresholds

Applied in `vw_kpi_run_quality`:

| Gate status | Condition |
|---|---|
| `PASS` | `validity_rate_pct ≥ 95%` |
| `WARN` | `80% ≤ validity_rate_pct < 95%` |
| `FAIL` | `validity_rate_pct < 80%` |

---

## 5. KPI Definitions

All KPIs are materialized as SQL views in `schema.sql`. They are the authoritative definitions — any notebook calculation that produces the same metric must match these formulas exactly.

### Housing KPIs

| KPI | View | Formula summary | Business question answered |
|---|---|---|---|
| Monthly MAPE | `vw_kpi_monthly_accuracy` | `AVG(|actual − llm| / actual × 100)` per model per month | How accurate is each model month by month? |
| Price bias | `vw_kpi_monthly_accuracy` | `actual − AVG(llm)` | Does the model systematically undershoot or overshoot? |
| Model leaderboard | `vw_kpi_model_leaderboard` | Overall MAPE across all months; ranked with `RANK()` | Which model is most accurate overall? |
| QoQ growth rate | `vw_kpi_quarterly_trend` | `(current_qtr − prev_qtr) / prev_qtr × 100` using `LAG()` | Does the LLM capture real quarter-over-quarter price trends? |
| Variance suppression | `vw_kpi_variance_suppression` | `1 − STDDEV(llm) / STDDEV(actual)` | How much real-world volatility does the LLM flatten out? |
| Run quality score | `vw_kpi_run_quality` | `valid_records / total_records × 100` | Are there data quality issues in a given generation run? |
| Seasonal bias | `vw_kpi_seasonal_bias` | Average `price_difference` grouped by calendar month | Do LLM errors concentrate in specific months? |
| Annual MAPE | `vw_kpi_annual_summary` | MAPE aggregated to full year | How does accuracy trend year over year? |

### Movie KPIs

| KPI | Computed in | Formula summary | Business question answered |
|---|---|---|---|
| Avg rating per model | `movie_analysis.ipynb` | `AVG(cleaned_rating)` grouped by model | Is each model biased toward high or low ratings? |
| Rating std dev | `movie_analysis.ipynb` | `STDDEV(cleaned_rating)` grouped by model | How consistent is each model's scoring? |
| Hallucination rate | `movie_analysis.ipynb` | `count(is_hallucination) / total × 100` | What share of ratings are outside the valid 1–5 scale? |
| Stability score | `movie_analysis.ipynb` | `1 / STDDEV(cleaned_rating)` | How repeatable is a model's rating behavior? |
| Rating entropy | `movie_analysis.ipynb` | Shannon entropy (base 2) of rating distribution | Does the model use the full rating range or cluster on a few values? |
| Validation delta | `movie_analysis.ipynb` | `AVG(gen_rating) − AVG(val_rating)` | How far is the LLM's average rating from the Rotten Tomatoes critic benchmark? |
| Temporal drift | `movie_analysis.ipynb` | Moving average of `avg_rating` across `run_id` order | Do ratings shift systematically across generation runs? |

---

## 6. Hallucination Classification

A hallucination is defined as a generated value that is **structurally impossible** given the stated schema — not merely inaccurate.

### Housing hallucinations

| Type | Definition | Example |
|---|---|---|
| Non-numeric price | LLM returned a string or null where an integer was required | `"approximately $750K"` |
| Out-of-range price | `median_price_usd < 100,000` or `median_price_usd > 5,000,000` | `12000` or `15000000` |
| Wrong month | `month` value does not match the requested generation window | LLM generates `2019-03` when asked for 2023 data |
| Missing field | Required JSON field absent from LLM response | `{}` instead of `{"area": ..., "month": ..., "median_price_usd": ...}` |

### Movie hallucinations

| Type | Definition | Example |
|---|---|---|
| `out_of_range` | `cleaned_rating < 1.0` or `cleaned_rating > 5.0` | Raw: `"7/5"` → cleaned: `7.0` |
| `non_numeric` | `clean_rating()` cannot extract any float | Raw: `"great movie"` |
| Scale confusion | Model generates a 10-point rating on a 5-point prompt | Raw: `"8/10"` → `clean_rating()` extracts `8.0` → flagged as out-of-range |

**Note:** Hallucinations are retained in the database with their raw values intact. They are excluded from accuracy KPIs but counted separately in hallucination rate metrics. This ensures the audit trail is complete.

---

## 7. Model Registry

All LLM models evaluated in this project, hosted locally via [Ollama](https://ollama.com/).

### Housing models (`ca_median_prices.version`)

| Model string | Architecture | Quantization | Bias direction | Overall reliability |
|---|---|---|---|---|
| `llama3.1:8b` | LLaMA 3.1 | None (full precision) | Underestimation | Best overall |
| `llama3.1:8b-instruct-q4_0` | LLaMA 3.1 instruction-tuned | 4-bit | Underestimation | Unstable — high run variance |
| `llama3.1:8b-instruct-q8_0` | LLaMA 3.1 instruction-tuned | 8-bit | Underestimation | Consistent but highest bias (~−112K USD) |
| `llama3.1:latest` | LLaMA 3.1 (latest tag) | Varies | **Overestimation** | Unreliable — linear drift pattern |

### Movie models (`movie_reviews.model`)

| Model string | Notes |
|---|---|
| `llama2` | High stability score; limited rating diversity |
| `llama3.1` | Zero variance — assigns identical rating every run |
| `llama3.1:latest` | Low entropy; constrained output patterns |
| `codellama:7b` | Highest entropy; most diverse rating behavior |
| `gemma3` | Moderate variance; lower stability than llama2 |

---

## 8. Null & Sparsity Policy

### CSV source data

Null values in `HomeMedianPrices.csv` indicate that CAR did not publish a median price for that county in that month — typically because transaction volume was too low for a statistically reliable estimate. These are **true missing values**, not data errors.

Policy:
- Null county values are propagated as-is into `ca_actual_prices` if that county is loaded.
- Only `Los Angeles` and `LA Metro` columns are loaded by default; both have complete coverage from 1990 onward.
- Sparse county columns (Trinity, Imperial, Far North, Lassen, Plumas) should not be used as primary analysis columns without explicit imputation or filtering.

### Database tables

| Table | Column | Null policy |
|---|---|---|
| `ca_median_prices` | `median_price_usd` | Should not be null; flagged in `vw_kpi_run_quality` if null |
| `ca_median_prices` | `source`, `version`, `Area` | Nullable — populated from API response; absence logged but not blocking |
| `movie_reviews` | `ratings` | Nullable at DB level; treated as hallucination (non-numeric type) in analysis |
| `movie_reviews` | `review_text` | Nullable; excluded from word count analysis if null |
| `ca_actual_prices` | `actual_price_usd` | NOT NULL — enforced at load time; rows with null prices are dropped during ETL |

---

*This data dictionary covers all tables, fields, and metrics as of the project's current state. When new models, areas, or data sources are added, this file should be updated in the same commit as the schema or notebook change.*
