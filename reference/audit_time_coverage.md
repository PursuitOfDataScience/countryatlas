# Does the data respect when countries existed?

The time-aware counterpart to
[`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md).
A join can succeed and still be wrong about history: South Sudan with
1995 data, Czechoslovakia with 2001 data, the USSR with 2010 data. Those
rows survive every check the package had, because the country resolves
and the year is a number.

## Usage

``` r
audit_time_coverage(data, quiet = FALSE)
```

## Arguments

- data:

  A panel with `iso3c` and `year`.

- quiet:

  Suppress the console summary and return the table silently. (Unlike
  [`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md),
  which returns a printable object and emits nothing until you print it,
  this one reports as it goes – a clean panel is the common case and
  worth confirming out loud.)

## Value

A tibble of the offending rows: `iso3c`, `country`, `year`, `issue`
(`"before_existence"` or `"after_dissolution"`) and `existed` (a
human-readable span). Zero rows means the panel is clean.

## What it can and cannot see

Dissolution dates come from
[historical_codes](https://pursuitofdatascience.github.io/countryatlas/reference/historical_codes.md),
which covers the entities the package curates (USSR, Yugoslavia,
Czechoslovakia and the rest). Independence dates come from the same
table read in reverse: a successor state is treated as not existing
before its predecessor dissolved. Countries with no entry in the
crosswalk – most of the world – are assumed to have existed throughout,
so a clean result means "nothing the crosswalk knows about is wrong",
not "every date is right".

## See also

[`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md),
[`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md),
[`country_timeline()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_timeline.md)

## Examples

``` r
panel <- data.frame(
  iso3c = c("SSD", "CZE", "FRA"),
  year  = c(1995L, 2001L, 2001L),
  gdp   = c(1, 2, 3)
)
audit_time_coverage(panel)
#> ! 1 row falls outside the country's existence.
#> ℹ Inspect the returned table; `dissolve_country()` resolves historical entities
#>   to successors.
#> # A tibble: 1 × 5
#>   iso3c country      year issue            existed  
#>   <chr> <chr>       <int> <chr>            <chr>    
#> 1 SSD   South Sudan  1995 before_existence from 2011
```
