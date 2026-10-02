# The registered data sources

What
[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md)
can reach, whether each one's backing package is actually installed, and
how to cite it.

## Usage

``` r
country_sources()
```

## Value

A tibble: `source`, `meta`, `key_col`, `key_type`, `cache`, `available`
(is the backing package installed?) and `citation`.

## See also

[`register_country_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/register_country_source.md),
[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md)

## Examples

``` r
country_sources()
#> # A tibble: 7 × 7
#>   source   meta                        key_col key_type cache available citation
#>   <chr>    <chr>                       <chr>   <chr>    <lgl> <lgl>     <chr>   
#> 1 comtrade UN Comtrade bilateral trad… iso3c   iso3c    TRUE  TRUE      United …
#> 2 eurostat Eurostat (via eurostat); E… iso3c   iso3c    TRUE  TRUE      Eurosta…
#> 3 ilo      ILOSTAT (SDMX); indicator … iso3c   iso3c    TRUE  TRUE      Interna…
#> 4 imf      IMF data portal (SDMX), e.… iso3c   iso3c    TRUE  TRUE      Interna…
#> 5 oecd     OECD Data Explorer (SDMX);… iso3c   iso3c    TRUE  TRUE      OECD. O…
#> 6 owid     Our World in Data (Chart A… iso3c   iso3c    TRUE  TRUE      Our Wor…
#> 7 wdi      World Bank World Developme… iso3c   iso3c    TRUE  TRUE      World B…
```
