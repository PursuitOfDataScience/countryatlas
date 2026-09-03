# Flag rates computed over tiny denominators

The small-number problem, named: a rate over a very small population is
mostly noise, and on a map it shouts as loudly as a rate over a very
large one. This reports which countries' rates you should not trust
before you plot them.

## Usage

``` r
rate_check(data, numerator, denominator, min_denominator = NULL, rate = NULL)
```

## Arguments

- data:

  A country-level frame.

- numerator, denominator:

  The count and the population it is over (unquoted).

- min_denominator:

  Denominators below this are flagged. `NULL` (default) uses the 10th
  percentile of the observed denominators, which adapts to the data
  rather than imposing a threshold that suits one indicator.

- rate:

  An existing rate column (unquoted), if you already computed it.
  Otherwise the rate is `numerator / denominator`.

## Value

A tibble of `iso3c`, `numerator`, `denominator`, `rate`, `expected_se`
(the Poisson standard error of the rate, \\\sqrt{r/d}\\) and `flagged`,
sorted with the least reliable first.

## What to do about it

Three answers, in rough order of preference:
[`smooth_rates()`](https://pursuitofdatascience.github.io/countryatlas/reference/smooth_rates.md)
shrinks the unreliable rates toward the global rate;
[`value_by_alpha_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/value_by_alpha_map.md)
leaves them alone but fades them out; or drop them and say so in the
caption. Plotting them raw and unremarked is the one option that
misleads.

## References

Roth, R. E., Woodruff, A. W. & Johnson, Z. F. (2010). Value-by-alpha
maps: an alternative technique to the cartogram. *The Cartographic
Journal* 47(2), 130-140.
[doi:10.1179/000870409X12488753453372](https://doi.org/10.1179/000870409X12488753453372)

## See also

[`smooth_rates()`](https://pursuitofdatascience.github.io/countryatlas/reference/smooth_rates.md),
[`per_capita()`](https://pursuitofdatascience.github.io/countryatlas/reference/per_capita.md),
[`value_by_alpha_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/value_by_alpha_map.md)

## Examples

``` r
d <- data.frame(
  iso3c = c("CHN", "IND", "TUV", "NRU"),
  cases = c(50000, 42000, 3, 1),
  pop   = c(1.41e9, 1.39e9, 11000, 12000)
)
rate_check(d, cases, pop)
#> # A tibble: 4 × 6
#>   iso3c numerator denominator      rate expected_se flagged
#>   <chr>     <dbl>       <dbl>     <dbl>       <dbl> <lgl>  
#> 1 TUV           3       11000 0.000273  0.000157    TRUE   
#> 2 NRU           1       12000 0.0000833 0.0000833   FALSE  
#> 3 CHN       50000  1410000000 0.0000355 0.000000159 FALSE  
#> 4 IND       42000  1390000000 0.0000302 0.000000147 FALSE  
```
