# Add ISO codes and classifications to any data frame

The package's mission, exposed for *your* data: take a data frame keyed
on messy country names (or codes) and attach standardised ISO codes plus
useful classifications, reconciling spellings via
[`countrycode::countrycode()`](https://rdrr.io/pkg/countrycode/man/countrycode.html)
and the curated
[`wdj_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)
table. The result joins cleanly to anything else keyed on `iso3c`.

## Usage

``` r
standardize_country(
  data,
  country_col,
  origin = "country.name",
  add = c("iso3c", "iso2c", "continent", "region"),
  custom_match = wdj_overrides(),
  warn = TRUE
)
```

## Arguments

- data:

  A data frame / tibble.

- country_col:

  The column holding country names or codes (unquoted, tidy-eval).

- origin:

  How to read `country_col`; any
  [`countrycode::countrycode()`](https://rdrr.io/pkg/countrycode/man/countrycode.html)
  origin scheme such as `"country.name"` (default), `"iso2c"`,
  `"iso3c"`, `"wb"`, `"un"`.

- add:

  Character vector of attributes to add. Defaults to
  `c("iso3c", "iso2c", "continent", "region")`. Any countrycode
  destination is accepted, plus the shortcuts `"flag"`, `"currency"`,
  `"tld"`.

- custom_match:

  A named character vector of name -\> iso3c overrides; defaults to
  [`wdj_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md).
  Merged on top of the built-in matching.

- warn:

  Whether to warn about unmatched countries (default `TRUE`).

## Value

`data` with the requested columns added (and existing same-named columns
overwritten).

## Examples

``` r
df <- data.frame(nation = c("U.S.", "S. Korea", "Czechia"), value = 1:3)
standardize_country(df, nation)
#> # A tibble: 3 × 6
#>   nation   value iso3c iso2c continent region               
#>   <chr>    <int> <chr> <chr> <chr>     <chr>                
#> 1 U.S.         1 USA   US    Americas  North America        
#> 2 S. Korea     2 KOR   KR    Asia      East Asia & Pacific  
#> 3 Czechia      3 CZE   CZ    Europe    Europe & Central Asia
```
