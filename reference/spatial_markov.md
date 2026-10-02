# Markov transitions conditioned on the neighbours

Rey's (2001) spatial Markov chain: one transition matrix for each class
of a country's spatial lag – the average class of its neighbours – so
you can ask whether a poor country among poor neighbours is less likely
to move up than one among rich neighbours. A homogeneity test says
whether the conditional matrices differ from the pooled one.

## Usage

``` r
spatial_markov(
  data,
  value,
  weights = NULL,
  n_classes = 5,
  classes = c("quantile", "relative"),
  step = 1
)
```

## Arguments

- data:

  A panel with `iso3c`, `year` and the value column.

- value:

  The column to classify (unquoted), such as GDP per capita.

- weights:

  A
  [`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)
  object; `NULL` (default) is k-nearest neighbours (k = 5), so islands
  take part.

- n_classes:

  Number of classes (default `5`).

- classes:

  `"quantile"` (default) cuts each year at its own quantiles, so a class
  is a rank band; `"relative"` divides each value by its year's
  cross-country mean and cuts at the pooled quantiles of those ratios,
  so a class is a band of relative income that can fill or empty over
  time.

- step:

  Years between the two observations of a transition (default `1`);
  keyed on the year, so a gap in a country's series gives no transition
  rather than a longer one.

## Value

A tibble of `lag_class`, `from`, `to`, `n` and `p`, with the attribute
`test`: a tibble of the likelihood-ratio and chi-square homogeneity
statistics, their degrees of freedom and p-values (Bickenbach & Bode
2003), where cells with no transitions do not count toward the degrees
of freedom (Kang & Rey 2018).

## References

Rey, S. J. (2001). Spatial empirics for economic growth and convergence.
*Geographical Analysis* 33(3), 195-214.
[doi:10.1111/j.1538-4632.2001.tb00444.x](https://doi.org/10.1111/j.1538-4632.2001.tb00444.x)

Bickenbach, F. & Bode, E. (2003). Evaluating the Markov property in
studies of economic convergence. *International Regional Science Review*
26(3), 363-392.
[doi:10.1177/0160017603253789](https://doi.org/10.1177/0160017603253789)

Kang, W. & Rey, S. J. (2018). Conditional and joint tests for spatial
effects in discrete Markov chain models of regional income distribution
dynamics. *The Annals of Regional Science* 61(1), 73-93.
[doi:10.1007/s00168-017-0859-9](https://doi.org/10.1007/s00168-017-0859-9)

## See also

[`transition_matrix()`](https://pursuitofdatascience.github.io/countryatlas/reference/transition_matrix.md),
[`spatial_lag()`](https://pursuitofdatascience.github.io/countryatlas/reference/spatial_lag.md)

## Examples

``` r
# \donttest{
set.seed(1)
iso <- countryatlas::world_snapshot$countries$iso3c
pan <- expand.grid(iso3c = iso, year = 2010:2015, stringsAsFactors = FALSE)
pan$v <- exp(stats::rnorm(nrow(pan)))
spatial_markov(pan, v, n_classes = 3)
#> # A tibble: 27 × 5
#>    lag_class  from    to     n     p
#>        <int> <int> <int> <int> <dbl>
#>  1         1     1     1    48 0.397
#>  2         1     2     1    35 0.28 
#>  3         1     3     1    40 0.351
#>  4         1     1     2    40 0.331
#>  5         1     2     2    46 0.368
#>  6         1     3     2    41 0.360
#>  7         1     1     3    33 0.273
#>  8         1     2     3    44 0.352
#>  9         1     3     3    33 0.289
#> 10         2     1     1    33 0.282
#> # ℹ 17 more rows
# }
```
