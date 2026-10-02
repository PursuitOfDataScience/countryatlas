# Markov transitions between income classes

How countries move between classes of a variable from one year to the
next: the discrete Markov chain of Quah's distribution dynamics. Class 1
is the lowest.

## Usage

``` r
transition_matrix(
  data,
  value,
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

A tibble of `from`, `to`, `n` (transitions observed) and `p` (the
probability of moving from `from` to `to`, `NA` for a class nothing
left), with attributes `ergodic` (the steady-state share of countries in
each class, if the chain ran on) and `first_passage` (the matrix of mean
first-passage times, in steps).

## References

Quah, D. (1993). Empirical cross-section dynamics in economic growth.
*European Economic Review* 37(2-3), 426-434.
[doi:10.1016/0014-2921(93)90031-5](https://doi.org/10.1016/0014-2921%2893%2990031-5)

Quah, D. T. (1996). Twin peaks: growth and convergence in models of
distribution dynamics. *The Economic Journal* 106(437), 1045-1055.
[doi:10.2307/2235377](https://doi.org/10.2307/2235377)

## See also

[`spatial_markov()`](https://pursuitofdatascience.github.io/countryatlas/reference/spatial_markov.md),
[`rank_mobility()`](https://pursuitofdatascience.github.io/countryatlas/reference/rank_mobility.md),
[`beta_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/beta_convergence.md),
[`sigma_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/sigma_convergence.md),
[`convergence_club()`](https://pursuitofdatascience.github.io/countryatlas/reference/convergence_club.md)

## Examples

``` r
set.seed(1)
pan <- expand.grid(iso3c = c("FRA", "DEU", "BRA", "IND", "CHN", "NGA"),
                   year = 2000:2010, stringsAsFactors = FALSE)
pan$gdp <- exp(stats::rnorm(nrow(pan), 9, 1))
transition_matrix(pan, gdp, n_classes = 3)
#> # A tibble: 9 × 4
#>    from    to     n     p
#>   <int> <int> <int> <dbl>
#> 1     1     1     6  0.3 
#> 2     2     1     4  0.2 
#> 3     3     1    10  0.5 
#> 4     1     2     7  0.35
#> 5     2     2    10  0.5 
#> 6     3     2     3  0.15
#> 7     1     3     7  0.35
#> 8     2     3     6  0.3 
#> 9     3     3     7  0.35
```
