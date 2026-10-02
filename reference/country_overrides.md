# Curated country-name overrides (replaces the silent drop-list)

A documented `custom_match` table for entities that geometry sources
(Natural Earth, and the `maps` package's 2013 copy of it) and data
providers spell in ways name matching gets wrong or leaves without an
ISO code. Earlier versions of the package *deleted* these regions; now
they are *matched* instead, so they stop silently disappearing from
maps.

## Usage

``` r
country_overrides(extra = NULL)
```

## Arguments

- extra:

  An optional named character vector of additional overrides (names are
  country/region names, values are `iso3c` codes). Merged on top of the
  built-in table, so you can extend or override it, e.g.
  `country_overrides(c(Somaliland = "SOM"))`.

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

Accented spellings also come in two Unicode forms that look identical:
the accent can be one precomposed code point (NFC) or a base letter
followed by a combining mark (NFD, which macOS returns for filenames).
Only NFC matches
[`countrycode::countrycode()`](https://rdrr.io/pkg/countrycode/man/countrycode.html)'s
tables, so a name that resolves to nothing is retried with its combining
marks stripped, which turns an NFD spelling into the ASCII spelling that
resolves anywhere. Only unresolved names are retried, so this never
changes a name that already matched.

If your input may contain accented country names, run in a UTF-8 locale.
De-accenting with `iconv(x, to = "ASCII//TRANSLIT")` gives ASCII
spellings that resolve everywhere, but it is not an escape from the
locale problem: `//TRANSLIT` is itself locale-dependent, so under
`LC_CTYPE=C` it returns `NA` (or, given an explicit `from = "UTF-8"`,
replaces each accent with `?`) and nothing resolves. De-accent while
still in a UTF-8 locale, or supply the ASCII spellings directly.

## Examples

``` r
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
#>            Kosovo, Republic of                         Naoero 
#>                          "XKX"                          "NRU" 
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
#>            Kosovo, Republic of                         Naoero 
#>                          "XKX"                          "NRU" 
#>                     Somaliland 
#>                          "SOM" 
```
