# Measure the three budgets and fail when one is over its ceiling.
scale <- as.numeric(Sys.getenv("COUNTRYATLAS_BUDGET_SCALE", "1"))
budget <- c(tests = 40, vignettes = 50, check = 270) * scale
took <- c(tests = NA, vignettes = NA, check = NA)

# CRAN-mode tests: NOT_CRAN unset, so skip_on_cran() skips as it does there.
# test_dir() rather than test_local(), which sets NOT_CRAN=true itself and so
# timed the whole suite.
Sys.unsetenv("NOT_CRAN")
took[["tests"]] <- system.time(
  testthat::test_dir("tests/testthat", package = "countryatlas",
                     load_package = "source", reporter = "summary",
                     stop_on_failure = TRUE)
)[["elapsed"]]

took[["vignettes"]] <- system.time(
  tools::buildVignettes(dir = ".", quiet = TRUE, clean = FALSE)
)[["elapsed"]]

took[["check"]] <- system.time(
  rcmdcheck::rcmdcheck(".", args = c("--as-cran", "--no-manual"),
                       error_on = "never", quiet = TRUE)
)[["elapsed"]]

report <- data.frame(step = names(took), seconds = round(took),
                     budget = round(budget[names(took)]),
                     over = took > budget[names(took)])
print(report, row.names = FALSE)
if (any(report$over)) {
  stop("Over budget: ", paste(report$step[report$over], collapse = ", "),
       ". Mark slow tests with skip_slow_on_cran(), or move long vignette ",
       "material to a pkgdown-only article.", call. = FALSE)
}
