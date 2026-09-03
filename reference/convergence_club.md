# Convergence clubs

Countries do not all converge to one steady state; they converge in
groups. This implements the Phillips-Sul (2007) log-t procedure: a
regression test for whether a set of countries is converging, applied
iteratively to peel off clubs that converge internally even when the
whole sample does not.

## Usage

``` r
convergence_club(data, value, min_size = 2, alpha = 0.05)
```

## Arguments

- data:

  A panel with `iso3c`, `year` and the value column.

- value:

  The value column (unquoted); usually income per head.

- min_size:

  Smallest club to report (default `2`). Countries left over are
  returned as club `NA`.

- alpha:

  Significance level for the one-sided log-t test (default `0.05`; the
  critical value is \\-1.65\\).

## Value

A tibble: `iso3c`, `club` (an integer, 1 = highest-level club, `NA` =
not classified), and the club's `log_t` statistic. The per-club test
results are attached as the `"countryatlas_clubs"` attribute.

## The test

For each country form the relative transition path \\h\_{it} = y\_{it} /
\bar{y}\_t\\, then regress \\\log(H_1/H_t) - 2\log(\log t)\\ on \\\log
t\\ over the last part of the sample, where \\H_t\\ is the
cross-sectional mean of \\(h\_{it}-1)^2\\. The one-sided *t* statistic
on \\\log t\\ is the log-t statistic: above \\-1.65\\ the group is
converging. Clubs are then formed by sorting countries on their
final-period value and growing a core group while the test still passes.

A panel needs a reasonable number of periods for this to mean anything –
below roughly fifteen the test has very little power, and the function
warns.

## References

Phillips, P. C. B. & Sul, D. (2007). Transition modeling and econometric
convergence tests. *Econometrica* 75(6), 1771-1855.
[doi:10.1111/j.1468-0262.2007.00811.x](https://doi.org/10.1111/j.1468-0262.2007.00811.x)

## See also

[`beta_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/beta_convergence.md),
[`sigma_convergence()`](https://pursuitofdatascience.github.io/countryatlas/reference/sigma_convergence.md)

## Examples

``` r
set.seed(1)
# two groups converging to different levels
panel <- expand.grid(iso3c = c(paste0("A", 1:5), paste0("B", 1:5)),
                     year = 2000:2024)
panel$y <- ifelse(startsWith(as.character(panel$iso3c), "A"), 100, 30) +
  rnorm(nrow(panel), 0, 2)
convergence_club(panel, y)
#> # A tibble: 10 × 3
#>    iso3c  club  log_t
#>    <chr> <int>  <dbl>
#>  1 A1        1 -1.21 
#>  2 A2        1 -1.21 
#>  3 A3        1 -1.21 
#>  4 A5        1 -1.21 
#>  5 B4        2 -0.140
#>  6 B5        2 -0.140
#>  7 B2        3 -0.880
#>  8 B3        3 -0.880
#>  9 A4       NA NA    
#> 10 B1       NA NA    
```
