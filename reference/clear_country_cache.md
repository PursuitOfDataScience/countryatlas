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

## What a global clear releases

Called with no `source`, this also drops the two cached *geometry*
backends: the Natural Earth `sf` layer held per scale (tens of megabytes
at `scale = "medium"`) and the memoised `map_data("world")` tibble
(about 99,000 rows per override set). Those are the largest things the
package keeps in memory, and in a long-lived process – a Shiny app or a
plumber API – this is the only way to release them. They rebuild on the
next map.

Naming a `source` leaves geometry alone, since it is not a data source.

## See also

[`country_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_sources.md),
[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md)

## Examples

``` r
clear_country_cache()
```
