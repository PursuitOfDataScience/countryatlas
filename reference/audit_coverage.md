# Coverage / missingness audit

What is missing, before you trust the map: which countries are
unmatched, the `NA` rate per indicator, and which World Bank regions /
income groups are under-covered – so a half-empty map is caught before
it is published.

## Usage

``` r
audit_coverage(data, indicator = NULL, by = c("region", "income", "continent"))
```

## Arguments

- data:

  A country-level (or map-ready) data frame.

- indicator:

  Optional character vector of value columns to report `NA` rates for.
  If `NULL`, all numeric columns are used. `na_rates` covers every one
  of them; the `by_group` breakdown is computed for a single indicator –
  the first – and names it in an `indicator` column so it cannot be
  mistaken for the group's overall coverage.

- by:

  Grouping for the coverage breakdown: `"region"` (default), `"income"`
  or `"continent"`.

## Value

A list of class `countryatlas_coverage`, with elements `unmatched`,
`na_rates` and `by_group`. It has a
[`print()`](https://rdrr.io/r/base/print.html) method, so at the console
you see a formatted report rather than the raw list; reach into the
elements by name to use the numbers programmatically.

## Examples

``` r
audit_coverage(countryatlas::world_snapshot$countries)
#> 
#> ── Coverage audit ──────────────────────────────────────────────────────────────
#> ✔ All countries matched to an ISO code.
#> 
#> ── Missingness by indicator ──
#> 
#> # A tibble: 4 × 4
#>   indicator           n n_missing na_rate
#>   <chr>           <int>     <int>   <dbl>
#> 1 gdp_per_capita    215        24  0.112 
#> 2 population        215         0  0     
#> 3 life_expectancy   215         0  0     
#> 4 co2_per_capita    215        12  0.0558
#> ── Coverage by group ──
#> 
#> # A tibble: 8 × 4
#>   region                     n_countries indicator      na_rate
#>   <chr>                            <int> <chr>            <dbl>
#> 1 South Asia                           8 gdp_per_capita  0.25  
#> 2 East Asia & Pacific                 37 gdp_per_capita  0.216 
#> 3 Middle East & North Africa          21 gdp_per_capita  0.143 
#> 4 Latin America & Caribbean           41 gdp_per_capita  0.0976
#> 5 Europe & Central Asia               56 gdp_per_capita  0.0893
#> 6 Sub-Saharan Africa                  48 gdp_per_capita  0.0417
#> 7 North America                        3 gdp_per_capita  0     
#> 8 NA                                   1 gdp_per_capita  0     
```
