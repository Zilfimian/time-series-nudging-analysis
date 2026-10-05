# Do Digital Nudges Survive Complexity? Analysis Code

R code for the results reported in the article *Do Digital Nudges Survive Complexity? Cognitive Biases and AI Assistance in Time-Series Financial Decisions* (Journal of Risk and Financial Management).

## Files

| File | Purpose |
|---|---|
| `data_cleaning.R` | Reads the raw survey export and saves the cleaned data (`data/cleaned_data.rda`) |
| `analysis.Rmd` | Loads the cleaned data and reproduces the results, organized by article section, table, and figure |

The data are not included in this repository. They are available from the corresponding author on request.

## Survey Application

A demo version of the survey application used in the experiment is available at <https://behciysu.shinyapps.io/time-series-nudges-test/>. Its source code is kept in a private repository, <https://github.com/Zilfimian/time-series-nudging-survey-demo-codes>, and access is available on request.

## How to Run

1. Place the raw survey export in a folder named `data/` as `data/TS-Nudging-Data.xlsx`.
2. From the repository folder, run `data_cleaning.R`. This creates `data/cleaned_data.rda`.
3. Run or knit `analysis.Rmd`. Each chunk prints the values reported in the corresponding part of the article.

The participant bootstrap for Table 5 (999 replicates, fixed seed) takes a few minutes.

## Requirements

R 4.6.0 with the packages `readxl` (1.4.5), `jsonlite` (2.0.0), `sandwich` (3.1.1), `lmtest` (0.9.40), `nnet` (7.3.20), and, for knitting, `knitr` (1.51) and `rmarkdown` (2.31).
