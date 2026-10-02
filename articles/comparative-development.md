# The comparative-development toolkit

## Inequality, concept by concept

Milanovic separates inequality between countries as units (concept 1)
from inequality between countries weighted by their populations (concept
2).
[`inequality()`](https://pursuitofdatascience.github.io/countryatlas/reference/inequality.md)
gives every standard measure under either:

``` r

inequality(snap$gdp_per_capita)
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
inequality(snap$gdp_per_capita, weights = snap$population)
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

How much of it lies between continents? Theil’s L decomposes without
depending on the order:

``` r

theil(snap$gdp_per_capita, snap$population, groups = snap$continent, type = "L")
#> # A tibble: 3 × 3
#>   component value share
#>   <chr>     <dbl> <dbl>
#> 1 total     0.774 1    
#> 2 between   0.349 0.451
#> 3 within    0.425 0.549
```

## Convergence and mobility

[`beta_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/beta_convergence.md)
and
[`sigma_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/sigma_convergence.md)
summarise a distribution in one number each.
[`transition_matrix()`](https://pursuitofdatascience.github.io/countryatlas/reference/transition_matrix.md)
shows how countries move within it (Quah):

``` r

set.seed(4)
pan <- expand.grid(iso3c = snap$iso3c[1:60], year = 2000:2010,
                   stringsAsFactors = FALSE)
pan$gdp <- exp(9 + stats::ave(stats::rnorm(nrow(pan), 0, 0.05), pan$iso3c,
                              FUN = cumsum) + rep(stats::rnorm(60), 11))
tm <- transition_matrix(pan, gdp, n_classes = 3, classes = "relative")
tm
#> # A tibble: 9 × 4
#>    from    to     n      p
#>   <int> <int> <int>  <dbl>
#> 1     1     1   189 0.940 
#> 2     2     1    12 0.0594
#> 3     3     1     0 0     
#> 4     1     2    12 0.0597
#> 5     2     2   180 0.891 
#> 6     3     2     5 0.0254
#> 7     1     3     0 0     
#> 8     2     3    10 0.0495
#> 9     3     3   192 0.975
attr(tm, "ergodic")
#> [1] 0.2521957 0.2534504 0.4943538
rank_mobility(pan, gdp, from = 2000, to = 2010)
#> # A tibble: 1 × 4
#>       n   tau  p_value share_moved
#>   <int> <dbl>    <dbl>       <dbl>
#> 1    60 0.879 3.27e-23       0.217
```

## Money across countries and years

[`deflate()`](https://pursuitofdatascience.github.io/countryatlas/reference/deflate.md)
turns current prices into constant ones, and
[`to_ppp()`](https://pursuitofdatascience.github.io/countryatlas/reference/to_ppp.md)
converts exchange-rate dollars to purchasing-power parity; a
cross-country panel over time usually needs both. Both fetch their price
series from the World Bank:

``` r

d <- country_data(2010:2020, c(gdp = "NY.GDP.MKTP.CN"), panel = TRUE)
d |> deflate(gdp, base_year = 2015) |> to_ppp(gdp_real)
```
