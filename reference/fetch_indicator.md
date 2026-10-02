# Fetch an indicator from any registered source

One verb, many providers. Whatever the source, the result comes back on
the ISO spine: `iso3c`, `year` where the data is a panel, and one column
per indicator.

## Usage

``` r
fetch_indicator(
  source,
  indicator,
  countries = NULL,
  years = NULL,
  vintage = NULL,
  ...
)
```

## Arguments

- source:

  A registered source name (see
  [`country_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_sources.md)).

- indicator:

  Indicator code(s). Name the vector to rename the columns, as in
  [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md):
  `c(gdp = "NY.GDP.PCAP.KD")`.

- countries:

  Optional `iso3c` vector; `NULL` (default) for all.

- years:

  Optional numeric year vector; `NULL` for the provider's default.

- vintage:

  For `source = "wdi"`, the release of the World Development Indicators
  to read; see
  [`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md).
  Other sources have no releases to pin and refuse it.

- ...:

  Passed to the source's own `fetch` function.

## Value

A tibble keyed on `iso3c` (and `year`, for a panel), with a record of
where each indicator column came from; see
[`source_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_info.md).

## See also

[`add_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/add_indicator.md),
[`compare_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/compare_sources.md),
[`country_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_sources.md)

## Examples

``` r
if (FALSE) { # \dontrun{
fetch_indicator("wdi", c(gdp = "NY.GDP.PCAP.KD"), years = 2020)
fetch_indicator("owid", "life_expectancy", years = 2020)
} # }
```
