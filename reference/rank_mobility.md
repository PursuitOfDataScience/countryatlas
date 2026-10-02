# How much did the ranking change?

Kendall's tau between the ranks of two cross-sections, and the share of
countries that moved at least `k` places: a summary of mobility that
complements
[`transition_matrix()`](https://pursuitofdatascience.github.io/countryatlas/reference/transition_matrix.md).

## Usage

``` r
rank_mobility(data, value, from, to, k = 5)
```

## Arguments

- data:

  A panel with `iso3c`, `year` and the value column.

- value:

  The column to rank (unquoted).

- from, to:

  The two years to compare.

- k:

  The number of places that counts as moving (default `5`).

## Value

A one-row tibble: `n` (countries with a value in both years), `tau`
(Kendall's tau-b of the two rankings: 1 for an unchanged order),
`p_value` (for tau = 0), and `share_moved` (the share of countries whose
rank changed by `k` places or more), with the per-country ranks as the
`"ranks"` attribute.

## See also

[`transition_matrix()`](https://pursuitofdatascience.github.io/countryatlas/reference/transition_matrix.md),
[`rank_countries()`](https://pursuitofdatascience.github.io/countryatlas/reference/rank_countries.md)

## Examples

``` r
set.seed(1)
pan <- expand.grid(iso3c = c("FRA", "DEU", "BRA", "IND", "CHN", "NGA"),
                   year = c(2000, 2010), stringsAsFactors = FALSE)
pan$gdp <- exp(stats::rnorm(nrow(pan), 9, 1))
rank_mobility(pan, gdp, from = 2000, to = 2010, k = 1)
#> # A tibble: 1 × 4
#>       n    tau p_value share_moved
#>   <int>  <dbl>   <dbl>       <dbl>
#> 1     6 0.0667   0.851       0.667
```
