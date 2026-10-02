# Local Moran's I (LISA)

Local Indicators of Spatial Association (Anselin 1995): one Moran
statistic per country, plus the cluster type it belongs to. Where
[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)
answers "is there clustering anywhere", this answers "where, and of what
kind".

## Usage

``` r
local_morans(
  data,
  value,
  weights = NULL,
  n_perm = 9999,
  alpha = 0.05,
  p_adjust = c("fdr", "bonferroni", "holm", "none")
)
```

## Arguments

- data:

  A country-level frame with `iso3c` and the value column.

- value:

  The value column (unquoted).

- weights:

  A
  [`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)
  object. `NULL` (default) uses `country_weights("knn", k = 5)`: every
  country's five nearest neighbours, islands included.
  `country_weights("contiguity")` gives the land-border default of
  earlier versions, which leaves every island out.

- n_perm:

  Permutations for the pseudo-p-value (default `9999`; use `0` to skip
  the test, which leaves `p_value` as `NA`). The smallest p-value a
  permutation test can give is \\1/(n\_{perm}+1)\\, and false-discovery
  control across about 190 countries needs a finer floor than 999
  permutations give; see the section below.

- alpha:

  Significance threshold for the `cluster` label (default `0.05`).

- p_adjust:

  How to adjust the per-country p-values for testing about 190 countries
  at once: `"fdr"` (default; Benjamini-Hochberg false discovery rate),
  `"bonferroni"`, `"holm"` or `"none"`. See the section below.

## Value

A tibble, one row per country: `iso3c`, `value`, `lag` (the neighbour
average), `ii` (the local statistic), `p_value`, `p_adjusted` and
`cluster` (`"High-High"`, `"Low-Low"`, `"High-Low"`, `"Low-High"` or
`"Not significant"`, judged on `p_adjusted`). The method is recorded as
the `"countryatlas_p_adjust"` attribute.

## One test per country

A local statistic runs one test per country, about 190 of them, so at
`alpha = 0.05` roughly ten countries are expected to look significant
when nothing is going on at all. `p_adjust = "fdr"` controls the false
discovery rate instead – the share of flagged countries that are false
alarms – which is the standard remedy for exactly this setting (Caldas
de Castro & Singer 2006) and what GeoDa offers. `"bonferroni"` and
`"holm"` control the chance of any false alarm, which is stricter;
`"none"` reproduces the unadjusted labels of earlier versions. `p_value`
itself is never adjusted, so it still matches `spdep`.

Adjustment needs resolution. A permutation p-value cannot go below
\\1/(n\_{perm}+1)\\, and Benjamini-Hochberg flags the most significant
of 190 tests only when its p-value is below \\0.05/190 \approx
0.00026\\. With 999 permutations the floor, 0.001, is above that, so
nothing short of several countries all reaching the floor can be
flagged, and an empty map would say "no clusters" when it means "not
enough permutations". Hence the default of 9,999, which takes about a
second for the whole world.

`p_value` is a **two-sided** pseudo-p from conditional permutation:
\\(1 + \\\\\|I_i^{\*}\| \ge \|I_i\|\\) / (n\_{perm} + 1)\\, so it is
never exactly zero and its floor is \\1/(n\_{perm}+1)\\ – with the
default 999 permutations, 0.001. Two-sided because a local statistic is
interesting at both ends: a country surrounded by unlike neighbours is
as much a finding as one surrounded by like ones. `cluster` is
`"Not significant"` wherever `p_value > alpha`, and everywhere when
`n_perm = 0` leaves it `NA`. Set a seed beforehand for a reproducible
`p_value`.

## References

Anselin, L. (1995). Local Indicators of Spatial Association – LISA.
*Geographical Analysis* 27(2), 93-115.
[doi:10.1111/j.1538-4632.1995.tb00338.x](https://doi.org/10.1111/j.1538-4632.1995.tb00338.x)

Caldas de Castro, M. & Singer, B. H. (2006). Controlling the false
discovery rate: a new application to account for multiple and dependent
tests in local statistics of spatial association. *Geographical
Analysis* 38(2), 180-208.
[doi:10.1111/j.0016-7363.2006.00682.x](https://doi.org/10.1111/j.0016-7363.2006.00682.x)

## See also

[`lisa_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/lisa_map.md),
[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md),
[`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
set.seed(1)
local_morans(snap, gdp_per_capita, weights = country_weights("knn", k = 5),
             n_perm = 99)
#> # A tibble: 199 × 7
#>    iso3c  value     lag       ii p_value p_adjusted cluster        
#>    <chr>  <dbl>   <dbl>    <dbl>   <dbl>      <dbl> <fct>          
#>  1 ABW   33939.  14923. -0.0605     0.86      0.940 Not significant
#>  2 AFG     374.   3453.  0.333      0.14      0.353 Not significant
#>  3 AGO    2799.   2911.  0.298      0.1       0.353 Not significant
#>  4 ALB    6549.  10175.  0.113      0.34      0.588 Not significant
#>  5 AND   41224. 102279.  2.71       0.01      0.353 Not significant
#>  6 ARE   41605.  30978.  0.433      0.2       0.433 Not significant
#>  7 ARG   12774.  10839.  0.0452     0.6       0.786 Not significant
#>  8 ARM    5378.   8014.  0.161      0.45      0.678 Not significant
#>  9 ATG   18305.  28266.  0.00927    0.63      0.799 Not significant
#> 10 AUS   61486.   1841. -0.941      0.13      0.353 Not significant
#> # ℹ 189 more rows
# }
```
