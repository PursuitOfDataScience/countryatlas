# Friendly country-code conversion

A discoverable wrapper around
[`countrycode::countrycode()`](https://rdrr.io/pkg/countrycode/man/countrycode.html)
exposing the full set of schemes with first-class shortcuts for the
high-value ones: flag emoji, currency, top-level domain,
continent/region and research codes (Correlates of War, Polity,
Gleditsch-Ward, V-Dem, IMF, FAO, FIPS, GAUL).

## Usage

``` r
convert_country(
  x,
  to = "iso3c",
  from = "country.name",
  custom_match = wdj_overrides(),
  warn = TRUE
)
```

## Arguments

- x:

  A vector of country names or codes.

- to:

  Destination scheme. A shortcut (`"iso3c"`, `"flag"`, `"currency"`,
  `"tld"`, `"continent"`, `"region"`, `"cown"`, ...), a localized name
  `"name_<lang>"` (`"name_fr"`, `"name_es"`, `"name_zh"`, ... – any
  language in countrycode's CLDR tables), or any raw countrycode
  destination.

- from:

  Origin scheme (default `"country.name"`).

- custom_match:

  Optional overrides (default
  [`wdj_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)).

- warn:

  Whether to warn about inputs that match no country (default `TRUE`). A
  recognised country whose destination value is genuinely missing –
  countrycode has no currency for Kosovo – returns `NA` without warning.

## Value

A vector of converted codes.

## Examples

``` r
convert_country(c("Japan", "Brazil"), to = "flag")
#> [1] "🇯🇵" "🇧🇷"
convert_country("Germany", to = "currency")
#> [1] "EUR"
convert_country(c("USA", "France"), to = "continent")
#> [1] "Americas" "Europe"  
convert_country(c("Germany", "United States"), to = "name_fr")
#> [1] "Allemagne"  "États-Unis"
```
