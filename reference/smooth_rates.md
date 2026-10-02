# Shrink unreliable rates toward the global rate

Empirical-Bayes smoothing: a rate computed over a small denominator is
pulled toward the overall rate in proportion to how little information
stands behind it, while a rate over a large denominator is left
essentially alone. Standard practice in disease mapping, and the
statistical counterpart to
[`value_by_alpha_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/value_by_alpha_map.md)'s
visual answer.

## Usage

``` r
smooth_rates(
  data,
  numerator,
  denominator,
  method = c("eb", "local_eb", "none"),
  suffix = "_smoothed",
  weights = NULL
)
```

## Arguments

- data:

  A country-level frame.

- numerator, denominator:

  The count and its denominator (unquoted).

- method:

  `"eb"` (default) shrinks each rate toward the global rate;
  `"local_eb"` toward its neighbourhood's – its own and its neighbours'
  pooled rate – so a rate is compared with the places around it rather
  than the whole world (Marshall 1991; Anselin, Lozano & Koschinsky
  2006); `"none"` computes the raw rate only.

- suffix:

  Suffix for the new columns (default `"_smoothed"`).

- weights:

  For `"local_eb"`: who a country's neighbours are, as a
  [`country_weights()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_weights.md)
  object; `NULL` (default) is k-nearest neighbours (k = 5). A country
  with no usable neighbour has no neighbourhood rate, so it is `NA`,
  with a warning.

## Value

`data` with `<numerator>_rate` and `<numerator>_smoothed` columns added,
plus `<numerator>_shrinkage` – the weight given to the country's own
rate, between 0 (fully shrunk to the global rate) and 1 (untouched). A
row with no finite, positive denominator or with a negative count has no
rate: all three are `NA` there, with a warning.

## The model

A Poisson-gamma model: counts \\y_i \sim \mathrm{Poisson}(d_i
\theta_i)\\ with \\\theta_i \sim \mathrm{Gamma}\\, whose mean and
variance are estimated from the data by the method of moments. The
posterior mean is \\w_i r_i + (1 - w_i)\bar{r}\\ with \\w_i = d_i /
(d_i + \alpha)\\, so the shrinkage weight is exactly the "how much do we
believe this country" quantity that
[`rate_check()`](https://pursuitofdatascience.github.io/countryatlas/reference/rate_check.md)
flags. Where the between-country variance is estimated as non-positive
(rates no more dispersed than Poisson noise alone), every rate shrinks
fully to the global mean, which is the right answer: the data contain no
evidence of real between-country variation.

On a panel the prior is estimated separately for each `year`, so every
rate is shrunk toward its own year's global rate and every row is kept.

`"local_eb"` estimates the same two moments in each country's
neighbourhood (itself and its neighbours): the local rate \\m_i\\ and
the local between-country variance \\a_i\\, computed from the deviations
of the neighbourhood's rates from \\m_i\\. It agrees with
`spdep::EBlocal(geoda = TRUE)` on the same neighbours.

## References

Marshall, R. J. (1991). Mapping disease and mortality rates using
empirical Bayes estimators. *Journal of the Royal Statistical Society,
Series C* 40(2), 283-294.
[doi:10.2307/2347593](https://doi.org/10.2307/2347593)

Anselin, L., Lozano, N. & Koschinsky, J. (2006). Rate transformations
and smoothing. Spatial Analysis Laboratory, University of Illinois.

## See also

[`rate_check()`](https://pursuitofdatascience.github.io/countryatlas/reference/rate_check.md),
[`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md),
[`value_by_alpha_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/value_by_alpha_map.md)

## Examples

``` r
d <- data.frame(
  iso3c = c("CHN", "IND", "TUV", "NRU"),
  cases = c(50000, 42000, 3, 1),
  pop   = c(1.41e9, 1.39e9, 11000, 12000)
)
smooth_rates(d, cases, pop)
#> # A tibble: 4 × 6
#>   iso3c cases        pop cases_rate cases_smoothed cases_shrinkage
#>   <chr> <dbl>      <dbl>      <dbl>          <dbl>           <dbl>
#> 1 CHN   50000 1410000000  0.0000355      0.0000355         0.997  
#> 2 IND   42000 1390000000  0.0000302      0.0000302         0.997  
#> 3 TUV       3      11000  0.000273       0.0000334         0.00236
#> 4 NRU       1      12000  0.0000833      0.0000330         0.00257
```
