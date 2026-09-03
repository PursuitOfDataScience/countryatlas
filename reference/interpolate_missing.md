# Fill missing values, and say that you did

Interpolate or carry forward missing observations in a panel. Every
value this invents is flagged in a companion column, and that flag is
**not optional** – an imputed value that travels through a pipeline
looking like data is exactly the failure this package exists to prevent.

## Usage

``` r
interpolate_missing(
  data,
  value = NULL,
  method = c("linear", "locf", "none"),
  max_gap = 3
)
```

## Arguments

- data:

  A panel with `iso3c` and `year`.

- value:

  Column(s) to fill (character). `NULL` fills every numeric column
  except `year`.

- method:

  `"linear"` (default, interior gaps only), `"locf"` (carry the last
  observation forward) or `"none"`.

- max_gap:

  Longest run of consecutive missing years to fill. Gaps longer than
  this are left alone, because interpolating across a decade is not
  interpolation. Default `3`.

## Value

`data` with the gaps filled and, for each filled column, a logical
`<column>_imputed` companion. The map verbs count those *columns* when
they write provenance, so they keep working through any verb that
preserves columns. An `"countryatlas_imputed"` attribute lists the flag
columns for convenience, but nothing in the package reads it, and
`dplyr` drops it as it drops most attributes – rely on the columns, not
the attribute. Rows come back sorted by `iso3c` then `year`.

## The hard rule

The flag cannot be turned off.
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
reads it and refuses to draw imputed values as though they were observed
without at least noting it in the caption. If you need values with no
flag, compute them yourself – the package will not hand you a frame
where invented numbers are indistinguishable from measured ones.

## See also

[`complete_years()`](https://pursuitofdatascience.github.io/countryatlas/reference/complete_years.md),
[`rate_check()`](https://pursuitofdatascience.github.io/countryatlas/reference/rate_check.md),
[`coverage_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/coverage_map.md)

## Examples

``` r
p <- data.frame(iso3c = "USA", year = 2000:2005,
                gdp = c(1, NA, NA, 4, NA, 6))
interpolate_missing(p, "gdp")
#> # A tibble: 6 × 4
#>   iso3c  year   gdp gdp_imputed
#>   <chr> <int> <dbl> <lgl>      
#> 1 USA    2000     1 FALSE      
#> 2 USA    2001     2 TRUE       
#> 3 USA    2002     3 TRUE       
#> 4 USA    2003     4 FALSE      
#> 5 USA    2004     5 TRUE       
#> 6 USA    2005     6 FALSE      
```
