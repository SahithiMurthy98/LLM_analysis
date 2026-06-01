# LLM-Based Synthetic Data Generation & Evaluation

### 📌 Project Overview

This project investigates the use of Large Language Models (LLMs) as synthetic data generators within end-to-end data science pipelines.
The goal is to evaluate whether LLMs can produce realistic, structured, and analytically useful synthetic data when combined with proper validation, storage, and statistical evaluation frameworks.

The project is implemented as a single unified system with two complementary parts, each targeting a different data modality:

Part I – Numerical Time-Series Data (Housing Prices)

Part II – Textual + Numerical Data (Movie Reviews & Ratings)

Together, these parts demonstrate how LLM-generated data behaves across structured, semi-structured, and unstructured formats.

### 🏗️ Unified System Architecture

```
LLM (Ollama-hosted models)
        ↓
Flask API Layer
        ↓
JSON Validation & Cleaning
        ↓
MySQL Database (Run-level Tracking)
        ↓
Exploratory Analysis & Statistical Testing
        ↓
Model Evaluation & Visualization
        ↓
SQL KPI Layer (schema.sql — 7 reporting views)
        ↓
KPI Reporting & Quality Scorecard (kpi_analysis.ipynb)
```

Both parts share the same architectural principles, making the project modular, extensible, and production-oriented.

---

### 🔹 Part I: Synthetic Housing Price Generation (Numerical Time-Series)
### 🎯 Objective

-> To assess whether LLMs can generate realistic monthly median housing prices that capture:

-> Long-term trends

-> Seasonality

-> Market variability

-> and how closely these synthetic values align with real-world housing data.

### 🔹 Key Capabilities

-> Monthly housing price generation per region

-> Enforced realism constraints (trend, seasonality, non-linearity)

-> Multiple LLM versions evaluated under the same pipeline

-> Run-level reproducibility and auditability

-> Direct comparison with actual housing price datasets

### 🔹 Evaluation Methods

-> Monthly aggregation and trend comparison

-> Actual vs. predicted price analysis

-> Error distribution visualization

-> Q-Q plots and normality testing

-> Shapiro–Wilk and Kolmogorov–Smirnov tests

-> Bias detection across model versions

---

### 🔹 Part II: Synthetic Movie Review & Rating Generation (Text + Numeric)
### 🎯 Objective

To evaluate whether LLMs can generate human-like movie reviews along with consistent numerical ratings, and to study variability, bias, and hallucinations across models.

### 🔹 Key Capabilities

-> Generation of diverse audience-style reviews (50–100 words)

-> Ratings produced on a 1–5 scale

-> Detection and correction of malformed or hallucinated ratings

-> Persistent storage with model and run metadata

-> Cross-model behavioral comparison

### 🔹 Evaluation Methods

-> Rating normalization and cleaning

-> Outlier detection using IQR

-> Hallucination detection (ratings outside valid scale)

-> Distribution and boxplot analysis

-> Rating stability, variance, and entropy metrics

-> Temporal drift and moving-average analysis

---

### 🗄️ Part III: SQL KPI Layer & Data Governance

**Files:** `schema.sql` · `kpi_analysis.ipynb` · `data_dictionary.md`

A SQL-backed KPI framework built on top of the existing pipeline tables (`ca_median_prices`, `movie_reviews`). All analytical metrics are defined as database views — enforcing consistent definitions across both notebooks and any future reporting surface.

#### New tables

| Table | Purpose |
|---|---|
| `ca_actual_prices` | Real CAR housing prices (from `HomeMedianPrices.csv`) loaded as a reference table for accuracy joins |
| `ca_quality_audit` | Audit log — one row per validation check per run, with failure rate and severity |

#### KPI views (`schema.sql`)

| View | Business question |
|---|---|
| `vw_kpi_monthly_accuracy` | How accurate is each model month-by-month? (MAPE, % error, signed bias) |
| `vw_kpi_model_leaderboard` | Which model is most accurate overall? Ranked by MAPE with `RANK()` |
| `vw_kpi_quarterly_trend` | Do LLMs capture real quarter-over-quarter price growth? (window functions, `LAG()`) |
| `vw_kpi_variance_suppression` | How much real-world price volatility does each model smooth out? |
| `vw_kpi_run_quality` | Are there null or out-of-range prices per run? (PASS / WARN / FAIL gate) |
| `vw_kpi_seasonal_bias` | Do LLM errors concentrate in specific calendar months? |
| `vw_kpi_annual_summary` | Year-level bias and MAPE per model |

#### What `kpi_analysis.ipynb` covers

-> ETL — loads `HomeMedianPrices.csv` into `ca_actual_prices` for SQL-level joins

-> Queries all 7 KPI views and produces charts

-> Run quality scorecard with PASS / WARN / FAIL gate per generation run

-> Audit logging via `ca_quality_audit`

-> Ad-hoc SQL — seasonal bias, hallucination breakdown, market volatility ranking

---

### 📊 Key Findings Across Both Parts

-> LLMs effectively capture long-term structural patterns but smooth out short-term volatility

-> Synthetic outputs often exhibit lower variance than real-world data

-> Model-specific biases are consistent across domains

-> Numerical hallucinations highlight the importance of post-generation validation

-> Statistical testing is essential to assess analytical reliability of LLM-generated data

---

### 📁 Repository Structure

```
LLM_analysis/
├── README.md
├── schema.sql                 ← SQL schema: 2 new tables + 7 KPI views
├── kpi_analysis.ipynb         ← KPI reporting layer + quality scorecard
├── data_dictionary.md         ← All tables, columns, validation rules, KPI definitions
├── lamaClientadv.ipynb        ← Part I: housing price pipeline + statistical analysis
├── movie analysis.ipynb       ← Part II: movie review pipeline + rating analysis
├── HomeMedianPrices.csv       ← Actual CAR housing data (Jan 1990 – Aug 2025)
└── rotten_tomatoes_movies.csv ← Rotten Tomatoes ground-truth data
```

---

### 🛠️ Technologies & Tools

-> Python

-> Flask

-> MySQL

-> Ollama (Local LLM Inference)

-> pandas / NumPy

-> SciPy

-> Matplotlib / Seaborn

-> Statistical Testing & EDA

-> SQLAlchemy / PyMySQL

-> python-dotenv

---

### 🚀 Why This Project Is Strong

This project demonstrates:

-> LLMs as data generators, not just language models

-> End-to-end data engineering + analytics pipelines

-> Robust handling of LLM uncertainty and hallucinations

-> Real-world statistical validation practices

-> Applicability across multiple data modalities

-> SQL-backed KPI framework with consistent metric definitions across all reporting surfaces

-> Data governance: validation rules, quality gates, audit logging, and a full data dictionary
