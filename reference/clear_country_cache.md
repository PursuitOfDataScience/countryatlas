# Clear the cached downloads

Empties the memoised in-session cache and, optionally, the on-disk one.

## Usage

``` r
clear_country_cache(source = NULL, disk = FALSE)
```

## Arguments

- source:

  Which source's cache to clear, or `NULL` (default) for all. Only the
  World Bank cache is currently persisted to disk; other sources are
  memoised per session.

- disk:

  Also delete the on-disk cache (default `FALSE`).

## Value

Invisibly `TRUE`.

## See also

[`country_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_sources.md),
[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md)

## Examples

``` r
clear_country_cache()
```
