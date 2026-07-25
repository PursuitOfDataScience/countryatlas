# Theil index, with between/within decomposition

The Theil T inequality index – less famous than Gini, but it decomposes
*exactly* into a between-group and a within-group component, answering
"how much of world inequality is between continents vs within them?" in
one call. Weight by population to describe inequality between people
rather than between country units.

## Usage

``` r
theil(x, weights = NULL, groups = NULL, na.rm = TRUE)
```

## Arguments

- x:

  A positive numeric vector (log scale; zero/negative values are dropped
  with a warning).

- weights:

  Optional non-negative weights (e.g. population).

- groups:

  Optional grouping vector (e.g. continent). When supplied, the
  decomposition is returned instead of the scalar.

- na.rm:

  Whether to drop `NA` values (default `TRUE`).

## Value

Without `groups`: a single non-negative number (`0` = perfect equality).
With `groups`: a tibble with components `"total"`, `"between"` and
`"within"` (`total = between + within`) and each component's `share` of
the total (`NA` when the total is `0`, i.e. perfect equality, and the
shares are undefined).

## Examples

``` r
snap <- countryatlas::world_snapshot$countries
theil(snap$gdp_per_capita, weights = snap$population)
#> [1] 0.6779156
theil(snap$gdp_per_capita, weights = snap$population, groups = snap$continent)
#> # A tibble: 3 × 3
#>   component value share
#>   <chr>     <dbl> <dbl>
#> 1 total     0.678 1    
#> 2 between   0.310 0.458
#> 3 within    0.368 0.542
```
