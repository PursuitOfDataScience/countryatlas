# Bivariate local Moran: high X among high Y

The local Moran statistic for two variables (Anselin, Syabri & Smirnov
2002): each country's standardised `x` against the average standardised
`y` of its neighbours, so "rich countries surrounded by long-lived
neighbours" is a cluster, and a rich country among short-lived
neighbours an outlier.

## Usage

``` r
bivariate_lisa(
  data,
  x,
  y,
  weights = NULL,
  n_perm = 9999,
  alpha = 0.05,
  p_adjust = c("fdr", "bonferroni", "holm", "none")
)
```

## Arguments

- data:

  A country-level frame with `iso3c`.

- x, y:

  The two value columns (unquoted).

- weights, n_perm, alpha, p_adjust:

  As in
  [`local_morans()`](https://pursuitofdatascience.github.io/countryatlas/reference/local_morans.md).

## Value

A tibble with one row per country used: `iso3c`, `x`, `lag_y` (the
neighbours' average `y`), `ii`, `p_value`, `p_adjusted` and `cluster`
(`"High-High"`, `"Low-Low"`, `"High-Low"`, `"Low-High"` or
`"Not significant"`), where the first word is the country's `x` and the
second its neighbours' `y`. A country needs both values to take part.

## References

Anselin, L., Syabri, I. & Smirnov, O. (2002). Visualizing multivariate
spatial correlation with dynamically linked windows. *Proceedings, CSISS
Workshop on New Tools for Spatial Data Analysis*.

## See also

[`local_morans()`](https://pursuitofdatascience.github.io/countryatlas/reference/local_morans.md),
[`lisa_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/lisa_map.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
bivariate_lisa(snap, gdp_per_capita, life_expectancy, n_perm = 499)
#> # A tibble: 199 × 7
#>    iso3c      x lag_y       ii p_value p_adjusted cluster        
#>    <chr>  <dbl> <dbl>    <dbl>   <dbl>      <dbl> <fct>          
#>  1 ABW   33939.  76.4  0.217     0.482     0.689  Not significant
#>  2 AFG     374.  71.0  0.254     0.4       0.615  Not significant
#>  3 AGO    2799.  66.3  0.581     0.018     0.0731 Not significant
#>  4 ALB    6549.  78.1 -0.249     0.166     0.363  Not significant
#>  5 AND   41224.  84.4  1.31      0.002     0.0234 High-High      
#>  6 ARE   41605.  81.6  0.966     0.012     0.0612 Not significant
#>  7 ARG   12774.  75.6 -0.0456    0.648     0.837  Not significant
#>  8 ARM    5378.  74.8 -0.0621    0.792     0.926  Not significant
#>  9 ATG   18305.  74.4  0.00203   0.906     0.964  Not significant
#> 10 AUS   61486.  68.3 -1.26      0.196     0.394  Not significant
#> # ℹ 189 more rows
# }
```
