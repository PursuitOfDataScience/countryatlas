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

  Optional non-negative weights (e.g. population), either the same
  length as `x` or length 1.

- groups:

  Optional grouping vector (e.g. continent), the same length as `x` (or
  length 1). When supplied, the decomposition is returned instead of the
  scalar. A row whose group is missing is dropped along with the rows
  whose value is missing, so the decomposition's `total` is computed
  over the grouped subset and can differ from the ungrouped `theil(x)`.
  For `world_snapshot`, Puerto Rico has no `region`, which is the whole
  of the difference there.

- na.rm:

  Whether to drop `NA` values (default `TRUE`).

## Value

Without `groups`: a single non-negative number (`0` = perfect equality).
With `groups`: a tibble with components `"total"`, `"between"` and
`"within"` (`total = between + within`) and each component's `share` of
the total (`NA` when the total is `0`, i.e. perfect equality, and the
shares are undefined).

When there is nothing to compute – no values left after `na.rm`, a zero
total weight, or an infinity in `x` or `weights` – the result is a
single `NA` whatever `groups` says, so reach for the components only
after checking
[`is.data.frame()`](https://rdrr.io/r/base/as.data.frame.html).

## See also

[`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)
for the more familiar single-number summary, which does not decompose.

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
