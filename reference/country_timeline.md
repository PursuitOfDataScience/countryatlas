# A country's existence span, predecessors and successors

When did this country exist, and what came before and after it? Reads
the bundled
[historical_codes](https://pursuitofdatascience.github.io/countryatlas/reference/historical_codes.md)
crosswalk in both directions – so it answers both "what did the USSR
become" and "what was Estonia part of".

## Usage

``` r
country_timeline(x, origin = "country.name", warn = TRUE)
```

## Arguments

- x:

  Country names or codes, current or historical (`"USSR"`,
  `"Yugoslavia"`, `"Estonia"`, `"DEU"`).

- origin:

  How to read `x` (default `"country.name"`).

- warn:

  Whether to report inputs that match neither a historical entity nor a
  modern country (default `TRUE`), as
  [`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md)
  does.

## Value

A tibble, one row per input: `input`, `iso3c`, `country`, `dissolved`
(the year it ceased to exist, or `NA` if it still does), `predecessors`
and `successors` (list-columns of `iso3c` codes). An input that resolves
to neither spine keeps its `input` and gets `NA` elsewhere; with
`warn = TRUE` it is reported rather than left to be spotted.

## Why the two directions are not mirror images

Both columns hold codes, so an entity ISO never coded cannot appear in
either. ISO 3166-3 only records changes from 1974 on, and three entities
in
[historical_codes](https://pursuitofdatascience.github.io/countryatlas/reference/historical_codes.md)
predate it: the United Arab Republic (1961), Tanganyika and Zanzibar
(both 1964). Asking about one of those by name works –
`country_timeline("Tanganyika")` gives `TZA` as a successor, because the
table stores that side as a name – but the reverse does not:
`country_timeline("TZA")` reports no predecessors, since there is no
code to report. The other eleven entities carry codes and round-trip in
both directions. Naming them instead of coding them would break the
column's type; inventing codes for them would be a guess, which this
package does not make.

## See also

[`dissolve_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/dissolve_country.md),
[historical_codes](https://pursuitofdatascience.github.io/countryatlas/reference/historical_codes.md),
[`audit_time_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_time_coverage.md)

## Examples

``` r
country_timeline(c("USSR", "Estonia", "France"))
#> # A tibble: 3 × 6
#>   input   iso3c country      dissolved predecessors successors
#>   <chr>   <chr> <chr>            <int> <list>       <list>    
#> 1 USSR    SUN   Soviet Union      1991 <chr [0]>    <chr [15]>
#> 2 Estonia EST   Estonia             NA <chr [1]>    <chr [0]> 
#> 3 France  FRA   France              NA <chr [0]>    <chr [0]> 
```
