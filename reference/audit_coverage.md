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

- `unmatched` – one row per input value that did not resolve to an ISO
  code. Empty is the good case.

- `na_rates` – one row per indicator: `n` is the number of countries
  *considered*, `n_missing` how many of them lack a value, and `na_rate`
  is `n_missing / n`. An infinite value counts as lacking one: no map
  can draw it, and
  [`coverage_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/coverage_map.md)
  shows it as missing too.

- `by_group` – one row per group: `n_countries` is how many countries
  are *in that group*, and `na_rate` is the share of those lacking a
  value. The counts sum to `n`.

Both `n` and `by_group`'s `n_countries` are **denominators** –
everything counted, not everything present. That is the opposite
orientation from
[`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md),
whose `n_countries` is the numerator (countries drawn *with* a value)
and whose `n_total` is the denominator. The two verbs report the same
coverage from opposite ends, so on 216 countries with 17 missing this
gives `n = 216` where
[`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md)
gives `n_countries = 199`.

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
#> 1 gdp_per_capita    216        17  0.0787
#> 2 population        216         0  0     
#> 3 life_expectancy   216         0  0     
#> 4 co2_per_capita    216        13  0.0602
#> ── Coverage by group ──
#> 
#> # A tibble: 7 × 4
#>   region                     n_countries indicator      na_rate
#>   <chr>                            <int> <chr>            <dbl>
#> 1 East Asia & Pacific                 37 gdp_per_capita  0.135 
#> 2 Middle East & North Africa          21 gdp_per_capita  0.0952
#> 3 Europe & Central Asia               57 gdp_per_capita  0.0877
#> 4 Latin America & Caribbean           42 gdp_per_capita  0.0714
#> 5 Sub-Saharan Africa                  48 gdp_per_capita  0.0417
#> 6 North America                        3 gdp_per_capita  0     
#> 7 South Asia                           8 gdp_per_capita  0     
```
