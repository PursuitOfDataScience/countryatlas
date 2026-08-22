# Gini coefficient (population-weightable)

The Gini index of inequality across countries, optionally weighted
(weight by population and the statistic describes inequality between
*people* assigned their country's mean, not between country units).

## Usage

``` r
gini(x, weights = NULL, na.rm = TRUE)
```

## Arguments

- x:

  A numeric vector (e.g. GDP per capita by country).

- weights:

  Optional non-negative weights (e.g. population), either the same
  length as `x` or length 1. `NULL` (default) weights all values
  equally.

- na.rm:

  Whether to drop `NA` values (pairwise with their weight; default
  `TRUE`).

## Value

A single number in `[0, 1]`: `0` is perfect equality.

## See also

[`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md),
which adds a between/within-group decomposition.

## Examples

``` r
snap <- countryatlas::world_snapshot$countries
gini(snap$gdp_per_capita)                          # between countries
#> [1] 0.635143
gini(snap$gdp_per_capita, weights = snap$population)  # between people
#> [1] 0.6094909
```
