# Read any SDMX statistics service

One reader for the statistical agencies that publish through SDMX, the
standard for statistical data exchange: the OECD, the IMF, the ILO,
Eurostat, the European Central Bank, the BIS and UNICEF, or any other
SDMX REST service by URL. It asks for SDMX-CSV, which needs no client
package, and returns the result on the ISO spine.
[`fetch_oecd()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_adapters.md)
is this with `provider = "oecd"`, and the `"imf"` and `"ilo"` sources of
[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md)
go through it too.

## Usage

``` r
fetch_sdmx(provider, flow, key = NULL, countries = NULL, years = NULL, ...)
```

## Arguments

- provider:

  One of `"oecd"`, `"imf"`, `"ilo"`, `"eurostat"`, `"ecb"`, `"bis"` or
  `"unicef"`, or the base URL of an SDMX 2.1 REST service.

- flow:

  The dataflow, as SDMX writes one: `"AGENCY,ID,VERSION"`
  (`"OECD.SDD.NAD,DSD_NAAG@DF_NAAG_I,1.0"`), `"AGENCY,ID"` or `"ID"`.
  Name it to name the value column (default `value`).

- key:

  The SDMX key: one code (or several joined by `+`) per dimension,
  separated by dots, empty for all values – `"A..B1GQ_R_GR.."`. `NULL`
  (default) asks for every series.

- countries:

  Optional `iso3c` vector. Where the provider publishes the dataflow's
  structure (the OECD, the IMF and the ILO), the codes go into the
  country position of `key`, so the filter is applied by the server;
  elsewhere they are applied after the download.

- years:

  Optional numeric year vector, sent as `startPeriod` and `endPeriod`.

- ...:

  Unused; named so a call written for another adapter says what it
  passed.

## Value

A tibble of `iso3c`, `year` and the value column, with a
[`source_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_info.md)
record (the unit and its power of ten, from `UNIT_MEASURE` and
`UNIT_MULT` where the provider sends them). The provider's aggregates
(`"OECD"`, `"EA20"`) are not countries and are dropped.

## One row per country-year

The package keys on country and year, so every other dimension has to be
pinned. When a dimension still varies – several measures, both sexes, or
quarterly periods – a country-year has several rows, and keeping the
first would be a silent choice; the reader aborts instead and names the
dimensions that vary, so the key can be narrowed. A failed request is a
warning and no rows, unless `options(countryatlas.strict = TRUE)`.

## See also

[`fetch_oecd()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_adapters.md),
[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md),
[`register_country_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/register_country_source.md)

## Examples

``` r
# \donttest{
# Real GDP growth for three countries, filtered by the OECD's server:
fetch_sdmx("oecd", c(gdp_growth = "OECD.SDD.NAD,DSD_NAAG@DF_NAAG_I,1.0"),
           key = "A..B1GQ_R_GR..", countries = c("FRA", "DEU", "JPN"),
           years = 2020:2023)
#> # A tibble: 12 × 3
#>    iso3c  year gdp_growth
#>    <chr> <int>      <dbl>
#>  1 JPN    2020     -4.28 
#>  2 FRA    2021      6.88 
#>  3 DEU    2021      3.96 
#>  4 JPN    2021      3.56 
#>  5 FRA    2022      2.72 
#>  6 DEU    2022      1.87 
#>  7 JPN    2022      1.33 
#>  8 FRA    2023      1.63 
#>  9 JPN    2023      0.721
#> 10 DEU    2023     -1.01 
#> 11 FRA    2020     -7.44 
#> 12 DEU    2020     -4.03 
# }
```
