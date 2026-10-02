# Reconcile and join two messy country tables

The generic two-table version of the package's whole reason for being:
join *any* two data frames that each key on country names or codes, by
reconciling both sides to `iso3c` first. Tables keyed on
`"Czech Republic"` vs `"Czechia"`, or `"South Korea"` vs
`"Korea, Rep."`, just work.

## Usage

``` r
country_join(
  x,
  y,
  by_x,
  by_y,
  origin_x = "country.name",
  origin_y = "country.name",
  type = c("left", "inner", "full"),
  suffix = c(".x", ".y"),
  key = c("iso3c", "cowc", "cown", "gwn"),
  warn = TRUE,
  also_by = NULL
)
```

## Arguments

- x, y:

  Data frames to join.

- by_x, by_y:

  The country columns in `x` and `y` (unquoted).

- origin_x, origin_y:

  How to read each key (countrycode origin schemes).

- type:

  Join type: `"left"` (default), `"inner"` or `"full"`.

- suffix:

  Suffix for clashing non-key columns (default `c(".x", ".y")`).

- key:

  Which code system to join on. `"iso3c"` (default) is the package's
  spine and the right choice for anything contemporary.
  `"cowc"`/`"cown"` (Correlates of War) and `"gwn"` (Gleditsch-Ward) are
  the alternate spines historical work needs – see the section below.

- warn:

  Whether to report values that resolve to no country (default `TRUE`).
  They join to nothing, so a silent reconciliation failure is the one
  thing this verb exists to prevent. Each side is reported separately.

- also_by:

  Key columns to join on besides the country: a character vector of
  columns present in both tables, or a named one when the names differ
  (`c(year = "yr")` joins `x$year` to `y$yr`). `NULL` (default) joins on
  `year` as well whenever both tables have one, and says so;
  [`character()`](https://rdrr.io/r/base/character.html) joins on the
  country alone.

## Value

A tibble joined on a reconciled `iso3c` key.

## Panels

one row per country-year: Two country-year panels are joined
country-year to country-year: when both tables have a `year` column it
becomes part of the key, with a message, so France 2019 meets France
2019 rather than every year of France meeting every other. A panel
joined to a cross-section (one side has no `year`) repeats the
cross-section's values across the panel's years, and says that too. Pass
`also_by` to key on other columns, or `also_by = character()` to join on
the country alone.

Whatever the keys, a key that appears more than once on *both* sides
pairs every copy with every copy. dplyr warns about that many-to-many
join only when it is called from the console, never from inside a
package, so this verb checks for itself and warns with class
`countryatlas_many_to_many`, naming the keys.

## Joining historical data

the second spine: ISO 3166 was first published in 1974 and never covered
colonies, so `iso3c` cannot key anything before about 1970. Correlates
of War and Gleditsch-Ward codes can, they run back to the nineteenth
century, and
[`historical_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/historical_geometry.md)
is keyed on `gwn`. Setting `key` switches the join onto one of those:

    country_join(a, b, country, nation, key = "gwn")

The trade-off is real and worth stating: COW/GW codes cover states ISO
never did, but they omit the dependencies and non-sovereign territories
ISO does cover, so a modern dataset joined on `gwn` loses Hong Kong,
Puerto Rico and the rest – which the join warns about. Use `iso3c`
unless you are working before 1970.

## Examples

``` r
a <- data.frame(country = c("Czechia", "South Korea"), gdp = c(1, 2))
b <- data.frame(nation = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
country_join(a, b, country, nation)
#> # A tibble: 2 × 5
#>   country       gdp iso3c nation           pop
#>   <chr>       <dbl> <chr> <chr>          <dbl>
#> 1 Czechia         1 CZE   Czech Republic    10
#> 2 South Korea     2 KOR   Korea, Rep.       51
```
