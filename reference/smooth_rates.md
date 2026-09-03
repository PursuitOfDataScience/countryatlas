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
  method = c("eb", "none"),
  suffix = "_smoothed"
)
```

## Arguments

- data:

  A country-level frame.

- numerator, denominator:

  The count and its denominator (unquoted).

- method:

  `"eb"` (default) for empirical-Bayes shrinkage, or `"none"` to compute
  the raw rate only.

- suffix:

  Suffix for the new columns (default `"_smoothed"`).

## Value

`data` with `<numerator>_rate` and `<numerator>_smoothed` columns added,
plus `<numerator>_shrinkage` – the weight given to the country's own
rate, between 0 (fully shrunk to the global rate) and 1 (untouched).

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
