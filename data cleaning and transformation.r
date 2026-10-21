# Databricks notebook source
# Load FRED-MD from Databricks table
fred_raw <- SparkR::sql(
  "SELECT * FROM hive_metastore.default.fred_md_202609"
)

# Preview
SparkR::showDF(fred_raw, 5)

# Convert Spark DataFrame to R DataFrame
fred_raw <- SparkR::collect(fred_raw)

# Check dimensions
dim(fred_raw)

# Preview
head(fred_raw)

# COMMAND ----------

# Check column names
names(fred_raw)[1:10]

# Check first 5 rows
head(fred_raw, 5)

# Check last 5 rows
tail(fred_raw, 5)

# COMMAND ----------

# DBTITLE 1,2.1.Extract transformation codes and clean dates
# STEP 2.1: Extract transformation codes

# Save the transformation codes from the first row
tcodes <- as.numeric(
  unlist(fred_raw[1, -1], use.names = FALSE)
)

# Assign variable names to transformation codes
names(tcodes) <- names(fred_raw)[-1]

# Remove the transformation row
fred_data <- fred_raw[-1, ]

# Convert dates
fred_data$sasdate <- as.Date(
  fred_data$sasdate,
  format = "%m/%d/%Y"
)

# Convert all economic variables to numeric
fred_data[-1] <- lapply(
  fred_data[-1],
  function(x) as.numeric(as.character(x))
)

# Sort dates
fred_data <- fred_data[
  order(fred_data$sasdate),
]

rownames(fred_data) <- NULL

# Verify cleaned dataset

cat("Start date:",
    as.character(min(fred_data$sasdate)), "\n")

cat("End date:",
    as.character(max(fred_data$sasdate)), "\n")

cat("Number of observations:",
    nrow(fred_data), "\n")

cat("Number of indicators:",
    ncol(fred_data) - 1, "\n")

cat("Transformation codes:",
    length(tcodes), "\n")

cat("Missing codes:",
    sum(is.na(tcodes)), "\n")

cat("Duplicate dates:",
    sum(duplicated(fred_data$sasdate)), "\n")

# Preview
head(fred_data, 3)

# COMMAND ----------

# DBTITLE 1,Step 2.2 — Transform all 126 economic indicators
# STEP 2.2: FRED-MD transformation function

transform_fred <- function(x, code) {

  x <- as.numeric(x)

  if (code == 1) {
    # Level
    return(x)

  } else if (code == 2) {
    # First difference
    return(c(NA_real_, diff(x)))

  } else if (code == 3) {
    # Second difference
    return(c(NA_real_, NA_real_, diff(x, differences = 2)))

  } else if (code == 4) {
    # Natural logarithm
    x[x <= 0] <- NA_real_
    return(log(x))

  } else if (code == 5) {
    # First log difference
    x[x <= 0] <- NA_real_
    return(c(NA_real_, diff(log(x))))

  } else if (code == 6) {
    # Second log difference
    x[x <= 0] <- NA_real_
    return(c(NA_real_, NA_real_,
             diff(log(x), differences = 2)))

  } else if (code == 7) {
    # Difference of percentage changes
    growth <- c(NA_real_, diff(x) / head(x, -1))
    growth[!is.finite(growth)] <- NA_real_
    return(c(NA_real_, diff(growth)))

  } else {
    stop(paste("Unknown transformation code:", code))
  }
}

# Create transformed dataset
fred_transformed <- data.frame(
  sasdate = fred_data$sasdate
)

# Apply the correct transformation to each variable
for (var in names(tcodes)) {

  fred_transformed[[var]] <- transform_fred(
    fred_data[[var]],
    tcodes[[var]]
  )

}

# Verify dimensions
dim(fred_transformed)

# Preview
head(fred_transformed[, 1:8])

# Verify transformation codes
tcodes[c("RPI", "UNRATE", "FEDFUNDS")]

# Compare raw and transformed values
comparison <- data.frame(
  Date = fred_data$sasdate[1:5],
  RPI_Raw = fred_data$RPI[1:5],
  RPI_Transformed = fred_transformed$RPI[1:5],
  UNRATE_Raw = fred_data$UNRATE[1:5],
  UNRATE_Transformed = fred_transformed$UNRATE[1:5],
  FEDFUNDS_Raw = fred_data$FEDFUNDS[1:5],
  FEDFUNDS_Transformed = fred_transformed$FEDFUNDS[1:5]
)

print(comparison)

# COMMAND ----------

# DBTITLE 1,STEP 2.3: Missing value analysis
# STEP 2.3: Missing value analysis

missing_count <- colSums(
  is.na(fred_transformed[, -1])
)

missing_summary <- data.frame(
  Variable = names(missing_count),
  Missing_Count = as.integer(missing_count),
  Missing_Percent = round(
    as.numeric(missing_count) / nrow(fred_transformed) * 100,
    2
  )
)

missing_summary <- missing_summary[
  order(-missing_summary$Missing_Percent),
]

# Display 20 variables with the most missing values
head(missing_summary, 20)

# Total missing values
sum(is.na(fred_transformed[, -1]))

# Number of months with complete data
sum(complete.cases(fred_transformed))

# Show 20 variables with most missing values
print(head(missing_summary, 20))

# Total missing values
cat(
  "Total missing values:",
  sum(is.na(fred_transformed[, -1])),
  "\n"
)

# Complete months
cat(
  "Complete months:",
  sum(complete.cases(fred_transformed)),
  "\n"
)

# Months with missing values
cat(
  "Months with missing values:",
  sum(!complete.cases(fred_transformed)),
  "\n"
)

# COMMAND ----------

# DBTITLE 1,Step 2.4 — Identify missing-value patterns
# STEP 2.5: Examine missing-value patterns

important_vars <- c(
  "ACOGNO",
  "UMCSENTx",
  "TWEXAFEGSMTHx",
  "ANDENOx",
  "VIXCLSx",
  "PERMIT",
  "CPIAUCSL"
)

missing_pattern <- data.frame(
  Variable = character(),
  First_Valid_Date = as.Date(character()),
  Last_Valid_Date = as.Date(character()),
  Missing_Before_First = integer(),
  Missing_After_First = integer()
)

for (var in important_vars) {

  x <- fred_transformed[[var]]

  valid_idx <- which(!is.na(x))

  if (length(valid_idx) == 0) next

  first_idx <- min(valid_idx)
  last_idx <- max(valid_idx)

  missing_pattern <- rbind(
    missing_pattern,
    data.frame(
      Variable = var,
      First_Valid_Date = fred_transformed$sasdate[first_idx],
      Last_Valid_Date = fred_transformed$sasdate[last_idx],
      Missing_Before_First = first_idx - 1,
      Missing_After_First = sum(
        is.na(x[first_idx:length(x)])
      )
    )
  )
}

print(missing_pattern)

# COMMAND ----------

# MAGIC %md
# MAGIC Step 2.5 — Interpretation of missing-value patterns
# MAGIC 1. Most variables have continuous coverage after their first observation.
# MAGIC
# MAGIC For example, VIXCLSx has 42 missing months at the beginning but no missing values afterward. We can retain this variable without removing early observations.
# MAGIC
# MAGIC 2. ACOGNO has a particularly short history.
# MAGIC
# MAGIC It only becomes available in 1992. Including it in a complete-case analysis would eliminate over 30 years of historical data.
# MAGIC
# MAGIC 3. CPIAUCSL requires further investigation.
# MAGIC
# MAGIC Its first two missing values are expected because transformation code 6 requires two previous observations.
# MAGIC
# MAGIC However, its three additional missing values need to be examined. Since several CPI variables have five missing values, they may share a common missing-data pattern.

# COMMAND ----------

# DBTITLE 1,Investigate CPI missing observations
# STEP 2.7: Investigate CPI missing observations

cpi_missing_dates <- fred_transformed$sasdate[
  is.na(fred_transformed$CPIAUCSL)
]

print(cpi_missing_dates)

# Compare raw and transformed CPI
cpi_check <- data.frame(
  Date = fred_data$sasdate,
  CPI_Raw = fred_data$CPIAUCSL,
  CPI_Transformed = fred_transformed$CPIAUCSL
)

print(
  cpi_check[
    is.na(cpi_check$CPI_Transformed),
  ]
)

# Check missing values around October 2025

check_dates <- as.Date(c(
  "2025-09-01",
  "2025-10-01",
  "2025-11-01",
  "2025-12-01",
  "2026-01-01"
))

# Count missing indicators by month
missing_by_month <- data.frame(
  Date = fred_transformed$sasdate,
  Missing_Count = rowSums(
    is.na(fred_transformed[, -1])
  )
)

print(
  missing_by_month[
    missing_by_month$Date %in% check_dates,
  ]
)

# Identify raw variables missing in October 2025
oct_missing <- names(fred_data)[-1][
  is.na(
    fred_data[
      fred_data$sasdate == as.Date("2025-10-01"),
      -1
    ]
  )
]

cat("Variables missing in October 2025:\n")
print(oct_missing)

# COMMAND ----------

# DBTITLE 1,Finalize the transformed dataset
#Save transformed master dataset

fred_master <- fred_transformed

# Confirm dimensions
stopifnot(nrow(fred_master) == 812)
stopifnot(ncol(fred_master) == 127)

# Check date range
range(fred_master$sasdate)

# Save locally in R format
saveRDS(
  fred_master,
  file = "/tmp/fred_md_transformed.rds"
)

cat("Transformed master dataset saved.\n")

# COMMAND ----------

# DBTITLE 1,Step 3 — Prepare macroeconomic and financial predictors
# Display transformations for key indicators

selected_vars <- c(
  "RPI", "INDPRO", "PAYEMS",
  "UNRATE", "CPIAUCSL", "HOUST",
  "S&P 500", "FEDFUNDS", "GS10",
  "T10YFFM", "BAAFFM", "VIXCLSx"
)

transformation_check <- data.frame(
  Variable = selected_vars,
  Transformation_Code = tcodes[selected_vars],
  row.names = NULL
)

print(transformation_check)

# COMMAND ----------

# DBTITLE 1,Create model predictor datasets
# STEP 3.2: Create model predictor datasets

# Model A: Macro only
X_macro <- fred_transformed[
  , c("sasdate", macro_vars),
  drop = FALSE
]

# Model B: Macro + Financial
X_full <- fred_transformed[
  , c("sasdate", macro_vars, financial_vars),
  drop = FALSE
]

# Verify dimensions
cat("Macro-only dataset:", dim(X_macro), "\n")
cat("Macro + Financial dataset:", dim(X_full), "\n")

# Check that both use identical dates
stopifnot(
  identical(X_macro$sasdate, X_full$sasdate)
)

# Confirm all indicators are included
stopifnot(
  length(macro_vars) == 100,
  length(financial_vars) == 26
)

cat("Both predictor datasets created successfully!\n")

# COMMAND ----------

# STEP 4: Final data quality checks

# 1. Check invalid numeric values
invalid_count <- sum(
  sapply(
    fred_transformed[-1],
    function(x) sum(is.infinite(x))
  )
)

cat("Infinite values:", invalid_count, "\n")

# 2. Check duplicate dates
cat(
  "Duplicate dates:",
  sum(duplicated(fred_transformed$sasdate)),
  "\n"
)

# 3. Check monthly continuity
expected_dates <- seq(
  from = min(fred_transformed$sasdate),
  to = max(fred_transformed$sasdate),
  by = "month"
)

cat(
  "Missing calendar months:",
  length(setdiff(
    expected_dates,
    fred_transformed$sasdate
  )),
  "\n"
)

# 4. Check transformed data dimensions
cat(
  "Transformed dataset:",
  dim(fred_transformed),
  "\n"
)

# COMMAND ----------

# STEP 5.1: Create variable dictionary

variable_dictionary <- data.frame(
  Variable = names(tcodes),
  Group = ifelse(
    names(tcodes) %in% financial_vars,
    "Financial",
    "Macroeconomic"
  ),
  Transformation_Code = as.integer(tcodes),
  Missing_Count = as.integer(
    colSums(is.na(fred_transformed[, -1]))[
      names(tcodes)
    ]
  ),
  stringsAsFactors = FALSE
)

variable_dictionary$Missing_Percent <- round(
  variable_dictionary$Missing_Count /
    nrow(fred_transformed) * 100,
  2
)

# Verify
print(head(variable_dictionary, 10))

print(table(variable_dictionary$Group))

# COMMAND ----------

# STEP 5.2: Export cleaned datasets

output_dir <- "/tmp/fred_md_project"

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

write.csv(
  fred_transformed,
  file.path(output_dir, "fred_md_transformed.csv"),
  row.names = FALSE,
  na = ""
)

write.csv(
  X_macro,
  file.path(output_dir, "fred_md_macro.csv"),
  row.names = FALSE,
  na = ""
)

write.csv(
  X_full,
  file.path(output_dir, "fred_md_macro_financial.csv"),
  row.names = FALSE,
  na = ""
)

write.csv(
  variable_dictionary,
  file.path(output_dir, "fred_md_variable_dictionary.csv"),
  row.names = FALSE
)

# Verify exported files
print(list.files(output_dir))

# COMMAND ----------

# STEP 5.2: Verify exported CSV files

output_dir <- "/tmp/fred_md_project"

files <- list.files(
  output_dir,
  full.names = TRUE
)

file_info <- data.frame(
  File = basename(files),
  Size_KB = round(file.size(files) / 1024, 2)
)

print(file_info)

# COMMAND ----------

# STEP 5.4: Verify table dimensions

table_names <- c(
  "default.fred_md_macro_clean",
  "default.fred_md_macro_financial_clean",
  "default.fred_md_transformed_clean",
  "default.fred_md_variable_dictionary"
)

for (tbl in table_names) {

  df <- SparkR::tableToDF(tbl)

  cat(
    "\nTable:", tbl,
    "\nRows:", SparkR::count(df),
    "\nColumns:", length(SparkR::columns(df)),
    "\n"
  )
}

# COMMAND ----------

# STEP 5.5: Final verification

df <- SparkR::tableToDF(
  "default.fred_md_transformed_clean"
)

# Convert to R DataFrame
saved_data <- SparkR::collect(df)

# Check dimensions
print(dim(saved_data))

# Check date range
cat("Start date:",
    as.character(min(as.Date(saved_data$sasdate))),
    "\n")

cat("End date:",
    as.character(max(as.Date(saved_data$sasdate))),
    "\n")

# Check missing values
cat("Total missing values:",
    sum(is.na(saved_data[, -1])),
    "\n")

# COMMAND ----------

# Final verification of all four tables

table_names <- c(
  "default.fred_md_macro_clean",
  "default.fred_md_macro_financial_clean",
  "default.fred_md_transformed_clean",
  "default.fred_md_variable_dictionary"
)

for (tbl in table_names) {
  df <- SparkR::tableToDF(tbl)

  cat(
    "\n", tbl,
    "\nRows:", SparkR::count(df),
    "\nColumns:", length(SparkR::columns(df)),
    "\n"
  )
}

# COMMAND ----------

# Export four Databricks tables to CSV

table_names <- c(
  fred_md_macro_clean = "default.fred_md_macro_clean",
  fred_md_macro_financial_clean = "default.fred_md_macro_financial_clean",
  fred_md_transformed_clean = "default.fred_md_transformed_clean",
  fred_md_variable_dictionary = "default.fred_md_variable_dictionary"
)

# Save to Databricks FileStore
output_dir <- "/dbfs/FileStore/fred_md_project"

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

for (name in names(table_names)) {

  # Read table
  spark_df <- SparkR::tableToDF(table_names[[name]])

  # Convert to R dataframe
  r_df <- SparkR::collect(spark_df)

  # Export CSV
  write.csv(
    r_df,
    file = file.path(output_dir, paste0(name, ".csv")),
    row.names = FALSE,
    na = ""
  )

  cat(
    "Exported:", name,
    "| Rows:", nrow(r_df),
    "| Columns:", ncol(r_df),
    "\n"
  )
}

# COMMAND ----------

cat("FileStore files:\n")
print(list.files("/dbfs/FileStore/fred_md_project"))

cat("\nTemporary files:\n")
print(list.files("/tmp/fred_md_project"))