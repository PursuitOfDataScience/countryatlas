# Theil index, with between/within decomposition

The Theil inequality indices – less famous than Gini, but they decompose
*exactly* into a between-group and a within-group component, answering
"how much of world inequality is between continents vs within them?" in
one call. Weight by population to describe inequality between people
rather than between country units. `type = "T"` (default) is Theil's T,
weighted by income shares; `type = "L"` is Theil's L, the mean log
deviation, weighted by population shares, whose decomposition is
path-independent.

## Usage

``` r
theil(x, weights = NULL, groups = NULL, na.rm = TRUE, type = c("T", "L"))
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

- na.rm:

  Whether to drop `NA` values (default `TRUE`).

- type:

  `"T"` (default) or `"L"`. T is \\\sum_i s_i (x_i/\mu) \log(x_i/\mu)\\
  with population shares \\s_i\\; L is \\\sum_i s_i \log(\mu/x_i)\\.
  Their decompositions differ: T's within-group term weights each group
  by its share of income, L's by its share of population, which is why
  L's between and within parts do not depend on the order in which they
  are taken out.

## Value

Without `groups`: a single non-negative number (`0` = perfect equality).
With `groups`: a tibble with components `"total"`, `"between"` and
`"within"` (`total = between + within`) and each component's `share` of
the total (`NA` when the total is `0`, i.e. perfect equality, and the
shares are undefined).

When there is nothing to compute (no values left after `na.rm`, a zero
total weight, an infinity in `x` or `weights`, or, with `na.rm = FALSE`,
a missing value or group), the result is a single `NA` whatever `groups`
says, so reach for the components only after checking
[`is.data.frame()`](https://rdrr.io/r/base/as.data.frame.html).

## See also

[`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md)
for the more familiar single-number summary, which does not decompose.

## Examples

``` r
snap <- countryatlas::world_snapshot$countries
theil(snap$gdp_per_capita, weights = snap$population)
#> [1] 0.6858193
theil(snap$gdp_per_capita, weights = snap$population, groups = snap$continent)
#> # A tibble: 3 × 3
#>   component value share
#>   <chr>     <dbl> <dbl>
#> 1 total     0.686 1    
#> 2 between   0.312 0.455
#> 3 within    0.374 0.545
```
