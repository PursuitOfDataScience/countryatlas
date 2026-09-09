# Beta convergence (growth regression)

Do poor countries grow faster than rich ones? The classic unconditional
beta-convergence test: each country's average log growth rate is
regressed on its log *initial* level. A significantly negative `beta` is
convergence; the implied convergence `speed` and `half_life` (years to
close half the gap) are derived from it.

## Usage

``` r
beta_convergence(data, value)
```

## Arguments

- data:

  A panel with `iso3c` and `year`.

- value:

  The value column (unquoted); must be positive (log scale).

## Value

A one-row tibble: `beta`, `se`, `t_value`, `p_value`, `r_squared`, `n`
(countries), `speed` (annual convergence rate) and `half_life` (years).

`speed` and `half_life` are `NA` in two cases: when `beta >= 0`, because
there is no convergence to put a rate on; and when the panel's
per-country spans are too heterogeneous for any single span to reconcile
with the fitted slope, which is warned about. `beta` and its inference
are unaffected in both – only the annualised figures need one common
span, so restrict the panel to a shared window if you need them. The
fitted [`stats::lm()`](https://rdrr.io/r/stats/lm.html) object is
attached as the `"model"` attribute.

## See also

[`sigma_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/sigma_convergence.md)
for the dispersion-over-time counterpart.

## Examples

``` r
set.seed(1)
start <- runif(20, 6, 11)                              # log initial level
growth <- 0.05 - 0.004 * start + rnorm(20, 0, 0.002)   # poorer grow faster
panel <- data.frame(
  iso3c = rep(sprintf("C%02d", 1:20), each = 2),
  year  = rep(c(2000L, 2020L), 20),
  gdp   = as.vector(rbind(exp(start), exp(start + growth * 20)))
)
beta_convergence(panel, gdp)
#> # A tibble: 1 × 8
#>       beta       se t_value  p_value r_squared     n   speed half_life
#>      <dbl>    <dbl>   <dbl>    <dbl>     <dbl> <int>   <dbl>     <dbl>
#> 1 -0.00464 0.000296   -15.7 6.14e-12     0.932    20 0.00487      142.
```
