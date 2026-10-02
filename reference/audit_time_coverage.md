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

A tibble of the offending rows: `iso3c`, `country`, `year`, `issue`,
`existed` (a human-readable span) and `basis` (where the dates come
from). `issue` is `"before_existence"` or `"after_dissolution"` – the
country did not exist – or the milder `"before_independence"`: it
existed, but was not yet (or not then) an independent state. Zero rows
means the panel is clean.

## What it can and cannot see

Dissolution dates come from
[historical_codes](https://pursuitofdatascience.github.io/countryatlas/reference/historical_codes.md),
which covers the entities the package curates (USSR, Yugoslavia,
Czechoslovakia and the rest), and a successor state is treated as not
existing before its predecessor dissolved
(`basis = "historical_codes"`).

Independence comes from Gleditsch & Ward's list of independent states
since 1816 (Gleditsch & Ward 1999, through the `states` package), with
every spell of independence: Namibia from 1990, Eritrea from 1993,
Timor-Leste from 2002, and Estonia from 1918 to 1940 and again from
1991. A year inside an earlier spell also corrects the crosswalk for a
state it dates from a later succession (Estonia's interwar years). A
year outside every spell is `"before_independence"`
(`basis = "gleditsch_ward"`). That is statehood, not data availability –
a colony often reports statistics before independence, and a World Bank
series may legitimately start there – so it is a separate,
lower-severity issue, for the caller to judge. Territories that are not
on the list are assumed to have existed throughout, so a clean result
still means "nothing these lists know about is wrong", not "every date
is right".

## References

Gleditsch, K. S. & Ward, M. D. (1999). A revised list of independent
states since the congress of Vienna. *International Interactions* 25(4),
393-413.
[doi:10.1080/03050629908434958](https://doi.org/10.1080/03050629908434958)

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
#> ! 1 row falls outside the country's existence or independence.
#> ℹ Inspect the returned table; `dissolve_country()` resolves historical entities
#>   to successors.
#> # A tibble: 1 × 6
#>   iso3c country      year issue            existed   basis           
#>   <chr> <chr>       <int> <chr>            <chr>     <chr>           
#> 1 SSD   South Sudan  1995 before_existence from 2011 historical_codes
```
