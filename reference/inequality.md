# Inequality, every standard measure at once

The usual inequality measures for one variable, in one tibble, so a
report does not rest on whichever index came to hand. Weight by
population for inequality between people rather than between countries.

## Usage

``` r
inequality(
  x,
  weights = NULL,
  measures = c("gini", "theil_t", "theil_l", "atkinson", "cv", "palma", "p90_p10"),
  epsilon = 1
)
```

## Arguments

- x:

  A numeric vector, such as GDP per capita.

- weights:

  Optional non-negative weights (population), the same length as `x` or
  length 1.

- measures:

  Any of `"gini"`, `"theil_t"`, `"theil_l"` (the mean log deviation),
  `"atkinson"`, `"cv"` (the coefficient of variation), `"palma"` (the
  top 10%'s share over the bottom 40%'s) and `"p90_p10"` (the 90th
  percentile over the 10th). All by default.

- epsilon:

  The Atkinson index's inequality aversion (default `1`): larger values
  weigh the bottom of the distribution more.

## Value

A tibble of `measure` and `value`, one row per measure, every one
computed on the same values: the finite, positive values of `x` with a
non-missing weight. The Theil and Atkinson indices need positive values,
so a zero or negative value is dropped from all of them, with a warning
(class `countryatlas_nonpositive_dropped`). A measure that is undefined
on the data (too few values) is `NA`.

## Which inequality

Milanovic (2005) separates three concepts. *Concept 1* is inequality
between countries as units, each counting once: `weights = NULL`.
*Concept 2* weights each country by its population but still gives
everyone their country's mean: `weights = population`. *Concept 3*,
inequality between all the world's people, needs each country's internal
distribution, which a country-level table does not have, so it is out of
scope here; concept 2 understates it by exactly the within-country
inequality it cannot see.

## References

Atkinson, A. B. (1970). On the measurement of inequality. *Journal of
Economic Theory* 2(3), 244-263.
[doi:10.1016/0022-0531(70)90039-6](https://doi.org/10.1016/0022-0531%2870%2990039-6)

Milanovic, B. (2005). *Worlds Apart: Measuring International and Global
Inequality*. Princeton University Press.

Palma, J. G. (2011). Homogeneous middles vs. heterogeneous tails, and
the end of the "inverted-U". *Development and Change* 42(1), 87-153.
[doi:10.1111/j.1467-7660.2011.01694.x](https://doi.org/10.1111/j.1467-7660.2011.01694.x)

## See also

[`gini()`](https://pursuitofdatascience.github.io/countryatlas/reference/gini.md),
[`theil()`](https://pursuitofdatascience.github.io/countryatlas/reference/theil.md),
[`sigma_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/sigma_convergence.md)

## Examples

``` r
snap <- countryatlas::world_snapshot$countries
inequality(snap$gdp_per_capita)                            # concept 1
#> # A tibble: 7 × 2
#>   measure   value
#>   <chr>     <dbl>
#> 1 gini      0.638
#> 2 theil_t   0.746
#> 3 theil_l   0.916
#> 4 atkinson  0.600
#> 5 cv        1.54 
#> 6 palma     9.36 
#> 7 p90_p10  43.7  
inequality(snap$gdp_per_capita, weights = snap$population) # concept 2
#> # A tibble: 7 × 2
#>   measure   value
#>   <chr>     <dbl>
#> 1 gini      0.612
#> 2 theil_t   0.686
#> 3 theil_l   0.774
#> 4 atkinson  0.539
#> 5 cv        1.40 
#> 6 palma     7.70 
#> 7 p90_p10  32.7  
```
