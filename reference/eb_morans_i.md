# Moran's I for rates, not fooled by small denominators

Moran's I on raw rates mistakes the noise of small denominators for
clustering: a few small states with extreme rates beside one another
look like a hot spot. The empirical-Bayes index (Assuncao & Reis 1999)
standardises each rate by how much variation its denominator alone would
produce before testing for autocorrelation.

## Usage

``` r
eb_morans_i(data, numerator, denominator, weights = NULL, n_perm = 999)
```

## Arguments

- data:

  A country-level frame with `iso3c`.

- numerator, denominator:

  The counts and their population at risk (unquoted).

- weights:

  A
  [`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)
  object; `NULL` (default) is k-nearest neighbours (k = 5), as for
  [`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md).

- n_perm:

  Permutations for the pseudo p-value (default `999`; `0` skips it).

## Value

A one-row tibble like
[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md)'s:
`i`, `expected`, `n`, `n_excluded`, `n_links`, `p_value` (one-sided, for
positive autocorrelation) and the list-column `excluded`.

## The statistic

With rates \\p_i = y_i / x_i\\, the global rate \\b = \sum y / \sum x\\
and the method-of-moments between-country variance \\a\\ (as in
[`smooth_rates()`](https://pursuitofdatascience.github.io/countryatlas/reference/smooth_rates.md)),
each rate is standardised as \\z_i = (p_i - b) / \sqrt{a + b / x_i}\\
and Moran's I is computed on \\z\\. It agrees with
[`spdep::EBImoran.mc()`](https://r-spatial.github.io/spdep/reference/EBImoran.mc.html)
on the same weights.

## References

Assuncao, R. M. & Reis, E. A. (1999). A new proposal to adjust Moran's I
for population density. *Statistics in Medicine* 18(16), 2147-2162.
[doi:10.1002/(SICI)1097-0258(19990830)18:16\<2147::AID-SIM179\>3.0.CO;2-I](https://doi.org/10.1002/%28SICI%291097-0258%2819990830%2918%3A16%3C2147%3A%3AAID-SIM179%3E3.0.CO%3B2-I)

## See also

[`morans_i()`](https://pursuitofdatascience.github.io/countryatlas/reference/morans_i.md),
[`smooth_rates()`](https://pursuitofdatascience.github.io/countryatlas/reference/smooth_rates.md),
[`rate_funnel()`](https://pursuitofdatascience.github.io/countryatlas/reference/rate_funnel.md)

## Examples

``` r
snap <- countryatlas::world_snapshot$countries
snap$births <- snap$population * 0.02
eb_morans_i(snap, births, population, n_perm = 0)
#> # A tibble: 1 × 7
#>         i expected     n n_excluded n_links p_value excluded 
#>     <dbl>    <dbl> <int>      <int>   <int>   <dbl> <list>   
#> 1 -0.0267 -0.00467   215          1     979      NA <chr [1]>
```
