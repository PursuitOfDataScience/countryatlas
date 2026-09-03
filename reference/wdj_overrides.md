# Curated country-name overrides (replaces the silent drop-list)

A documented `custom_match` table for entities that map backends
([`ggplot2::map_data()`](https://ggplot2.tidyverse.org/reference/map_data.html)
and Natural Earth) get wrong or leave without an ISO code. Earlier
versions of the package *deleted* these regions; now they are *matched*
instead, so they stop silently disappearing from maps.

`country_overrides()` is the current name, as of the package's rename to
countryatlas. **`wdj_overrides()` is deprecated** and warns once per
session; it returns the same table and will be removed. The help page
kept describing it as "a backward-compatible alias" after the code had
started warning.

## Usage

``` r
wdj_overrides(extra = NULL)

country_overrides(extra = NULL)
```

## Arguments

- extra:

  An optional named character vector of additional overrides (names are
  country/region names, values are `iso3c` codes). Merged on top of the
  built-in table, so you can extend or override it, e.g.
  `wdj_overrides(c(Somaliland = "SOM"))`.

## Value

A named character vector suitable for `countrycode(custom_match=)`.

## Details

The table maps a country/region name (as spelled by the geometry
backends) to an ISO 3166-1 alpha-3 code. Pass the result as the
`custom_match` argument to
[`standardize_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_country.md),
[`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
and friends. Every downstream code (`iso2c`, continent, region, flag,
...) is derived from this `iso3c`, so a single override is enough.

## Accented names and locales

Every name in this table is plain ASCII, and that is deliberate: ASCII
spellings match in any locale. Accented spellings (`"Curacao"` with a
cedilla, `"Saint Barthelemy"` with an acute) are matched natively by
[`countrycode::countrycode()`](https://rdrr.io/pkg/countrycode/man/countrycode.html)
*in a UTF-8 locale*, which is why they are not listed here – but in a
non-UTF-8 locale (`LC_CTYPE=C`) they cannot be compared reliably and
resolve to `NA`.

If your input may contain accented country names, run in a UTF-8 locale.
De-accenting with `iconv(x, to = "ASCII//TRANSLIT")` gives ASCII
spellings that resolve everywhere, but it is not an escape from the
locale problem: `//TRANSLIT` is itself locale-dependent, so under
`LC_CTYPE=C` it returns `NA` (or, given an explicit `from = "UTF-8"`,
replaces each accent with `?`) and nothing resolves. De-accent while
still in a UTF-8 locale, or supply the ASCII spellings directly.

## Examples

``` r
# `country_overrides()` is the current name; `wdj_overrides()` warns.
country_overrides()
#>               Ascension Island                         Azores 
#>                          "SHN"                          "PRT" 
#>                        Barbuda                        Bonaire 
#>                          "ATG"                          "BES" 
#>                 Canary Islands             Chagos Archipelago 
#>                          "ESP"                          "IOT" 
#>                     Grenadines                   Heard Island 
#>                          "VCT"                          "HMD" 
#>                         Kosovo                Madeira Islands 
#>                          "XKX"                          "PRT" 
#>                     Micronesia                           Saba 
#>                          "FSM"                          "BES" 
#>                   Saint Martin                Siachen Glacier 
#>                          "MAF"                          "IND" 
#>                 Sint Eustatius                 Virgin Islands 
#>                          "BES"                          "VIR" 
#>               Saint Barthelemy                        Curacao 
#>                          "BLM"                          "CUW" 
#>                        Madeira Federated States of Micronesia 
#>                          "PRT"                          "FSM" 
#>          Micronesia, Fed. Sts.           Virgin Islands, U.S. 
#>                          "FSM"                          "VIR" 
#>         British Virgin Islands                Channel Islands 
#>                          "VGB"                          "GBR" 
#>            Kosovo, Republic of 
#>                          "XKX" 
country_overrides(c(Somaliland = "SOM"))
#>               Ascension Island                         Azores 
#>                          "SHN"                          "PRT" 
#>                        Barbuda                        Bonaire 
#>                          "ATG"                          "BES" 
#>                 Canary Islands             Chagos Archipelago 
#>                          "ESP"                          "IOT" 
#>                     Grenadines                   Heard Island 
#>                          "VCT"                          "HMD" 
#>                         Kosovo                Madeira Islands 
#>                          "XKX"                          "PRT" 
#>                     Micronesia                           Saba 
#>                          "FSM"                          "BES" 
#>                   Saint Martin                Siachen Glacier 
#>                          "MAF"                          "IND" 
#>                 Sint Eustatius                 Virgin Islands 
#>                          "BES"                          "VIR" 
#>               Saint Barthelemy                        Curacao 
#>                          "BLM"                          "CUW" 
#>                        Madeira Federated States of Micronesia 
#>                          "PRT"                          "FSM" 
#>          Micronesia, Fed. Sts.           Virgin Islands, U.S. 
#>                          "FSM"                          "VIR" 
#>         British Virgin Islands                Channel Islands 
#>                          "VGB"                          "GBR" 
#>            Kosovo, Republic of                     Somaliland 
#>                          "XKX"                          "SOM" 
```
