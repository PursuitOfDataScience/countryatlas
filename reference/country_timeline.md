# A country's existence span, predecessors and successors

When did this country exist, and what came before and after it? Reads
the bundled
[historical_codes](https://pursuitofdatascience.github.io/countryatlas/reference/historical_codes.md)
crosswalk in both directions – so it answers both "what did the USSR
become" and "what was Estonia part of".

## Usage

``` r
country_timeline(x, origin = "country.name")
```

## Arguments

- x:

  Country names or codes, current or historical (`"USSR"`,
  `"Yugoslavia"`, `"Estonia"`, `"DEU"`).

- origin:

  How to read `x` (default `"country.name"`).

## Value

A tibble, one row per input: `input`, `iso3c`, `country`, `dissolved`
(the year it ceased to exist, or `NA` if it still does), `predecessors`
and `successors` (list-columns of `iso3c` codes).

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
