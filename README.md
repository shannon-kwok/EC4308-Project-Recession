# EC4308 Project: Forecasting US Recessions

We investigate if adding financial predictors to macroeconomic predictors improves out-of-sample forecasts of the probability of a US recession at 3, 6 and 12-month horizons using FRED-MD data.
We compare various machine-learning models against probit/logit baselines.

## Research question

At which forecast horizons (3, 6 or 12 months) do financial-market indicators improve out-of-sample prediction of US recessions beyond traditional macroeconomic indicators?

## Data

| Item | Detail |
|---|---|
| Predictors | FRED-MD monthly database, transformed to stationarity with the provided transformation codes |
| Predictor sets | **Macro** (97 series) and **Macro + Financial** (122 series: the macro set plus 25 financial series) |
| Recession indicator | NBER-based `USREC` (`data/raw/USREC.csv`) |
| Sample | 1962-07 to 2026-06 (768 months) |
| Missing values | Four series dropped for short histories; remaining gaps (Apr–May 2020, Oct–Dec 2025) forward-filled using past values only |

## Forecast setup (common to all models)

- **Target:** `Y_h = 1` if a recession occurs at any point in months t+1 to t+h, for h = 3, 6, 12.
- **Predictors:** month-t values only in the baseline specification; no lagged recession indicator.
- **Train/test split:** training data from 1962-07; out-of-sample forecasts from 1986-01 onwards. The test period contains four recessions (1990–91, 2001, 2008–09, 2020).
- **Expanding window:** each model is re-estimated every month. At forecast origin t, training uses rows 1 to t − h − 1, so every training label's window ends before t.
- **Evaluation:** AUC (headline), Brier score, F1 and balanced accuracy (0.5 threshold).
- **Significance:** paired block bootstrap of AUC differences (24-month blocks, 1,000 resamples, seed 1213; Künsch, 1989).
- **Lag extension:** adds lags of UNRATE, PAYEMS, CPIAUCSL, HOUST and S&P 500 (3 and 6 months) and T10YFFM (6 and 12 months), identical across all models.

## Repository structure

```
data/
  raw/USREC.csv                  NBER recession indicator
  processed/*_final.csv          Model-ready datasets (used by all notebooks)
  processed/*_clean.csv, *_usrec.csv, fred_md_transformed_clean.csv
                                 Intermediate pipeline outputs
  results/rf_forecasts*.rds      Saved random forest / bagging forecasts
data_processing/
  data_cleaning_and_transformation_1.r   Step 1: load and transform FRED-MD (Databricks)
  data_processing_2.Rmd                   Step 2: join USREC, trim sample, fill gaps
notebooks/
  baseline models.Rmd            Static probit and logit (benchmarks)
  LASSO.Rmd                      LASSO and post-LASSO logit
  naive_bayes.Rmd                Gaussian naive Bayes
  RandomForest.Rmd               Random forest and bagging
results/
  static_probit_logit_forecasts*.csv     Probit/logit forecasts read by the other notebooks
```

## How to run

Run in this order (each notebook is knitted from the `notebooks/` folder, so paths are relative):

1. `data_processing/data_cleaning_and_transformation_1.r` — runs on Databricks (reads the `fred_md_202609` table via SparkR). Only needed to rebuild the data from scratch.
2. `data_processing/data_processing_2.Rmd` — produces `data/processed/*_final.csv`.
3. `notebooks/baseline models.Rmd` — **must run before the model notebooks**; writes the probit/logit forecast CSVs to `results/`.
4. `notebooks/LASSO.Rmd`, `notebooks/naive_bayes.Rmd`, `notebooks/RandomForest.Rmd` — in any order. Each compares its best model with probit (12-month horizon, Macro + Financial) using the CSVs from step 3.

**Random forest runtime:** the full set of forecasts takes about an hour. Results are cached in `data/results/rf_forecasts.rds` and `rf_forecasts_lagged.rds`; delete these files to force a re-run.

## Packages

```r
install.packages(c("dplyr", "tidyr", "readr", "lubridate", "ggplot2", "knitr",
                   "here", "pROC", "ranger", "hdm", "e1071"))
```

## Notes

- Probit fails to produce forecasts for some months (separation/non-convergence), mainly for the Macro set; logit has no missing forecasts. Comparisons keep only months where both models have a valid forecast.
- Labels assume NBER recession dates are known in real time, and predictors are final revised values. Both are limitations of the setup.

## Team

Vanisha Muthu
Tan Sze Ping
Shannon Kwok
Javier Chin
Wang Yutian

