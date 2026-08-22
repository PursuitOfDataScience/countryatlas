# Sigma convergence (dispersion over time)

Is the cross-country distribution actually narrowing? Reports the
dispersion of a (positive) indicator across countries for every year of
a panel – falling dispersion is sigma convergence. The natural companion
to
[`beta_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/beta_convergence.md):
beta convergence is necessary but not sufficient for sigma convergence.

## Usage

``` r
sigma_convergence(data, value, measure = c("sd_log", "cv"))
```

## Arguments

- data:

  A panel with `iso3c` and `year`.

- value:

  The value column (unquoted).

- measure:

  `"sd_log"` (default; standard deviation of log values, the standard
  choice) or `"cv"` (coefficient of variation).

## Value

A tibble with one row per year: `year`, `n` (countries with positive
values) and `sigma`.

## See also

[`beta_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/beta_convergence.md)
for the growth-regression counterpart.

## Examples

``` r
df <- data.frame(
  iso3c = rep(c("A", "B", "C"), 2),
  year = rep(c(2000L, 2010L), each = 3),
  gdp = c(1, 10, 100, 2, 11, 60)   # dispersion falls
)
sigma_convergence(df, gdp)
#> # A tibble: 2 × 3
#>    year     n sigma
#>   <int> <int> <dbl>
#> 1  2000     3  2.30
#> 2  2010     3  1.70
```
