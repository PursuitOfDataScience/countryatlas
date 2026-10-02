# Clear the cached downloads

Empties the memoised in-session cache and, optionally, the on-disk one.

## Usage

``` r
clear_country_cache(source = NULL, disk = FALSE)
```

## Arguments

- source:

  Which source's cache to clear, or `NULL` (default) for all. The
  built-in sources persist to disk, one directory each under the cache
  (`wdi`, `wdi-archive` for pinned World Bank releases, `owid`, `oecd`,
  `imf`, `ilo`, `eurostat`, `comtrade`); a source you registered
  yourself is memoised for the session only.

- disk:

  Also delete that source's on-disk entries (default `FALSE`). Only the
  cache's own files are removed, and a directory only when that leaves
  it empty.

## Value

Invisibly `TRUE`.

## What a global clear releases

Called with no `source`, this also drops the two cached *geometry*
backends: the Natural Earth `sf` layer held per scale (tens of megabytes
at `scale = "medium"`) and the polygon backend's memoised vertex table
(about 98,000 rows per override set). Those are the largest things the
package keeps in memory, and in a long-lived process – a Shiny app or a
plumber API – this is the only way to release them. They rebuild on the
next map.

Naming a `source` leaves geometry alone, since it is not a data source.

## Where the cache lives

The persistent cache goes in the standard per-user cache location,
`tools::R_user_dir("countryatlas", "cache")`. Point it elsewhere with
`options(countryatlas.cache_dir = )`, or skip it by passing
`cache = FALSE` to
[`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
or
[`country_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_data.md).
Under `R CMD check` the whole cache moves to the session temp directory,
so a check never writes to the user's file space.

Entries expire: a fetch from a current release is dropped once it is 30
days old, because providers revise their figures, and past 50 MB per
source the least-recently-used entries go first. Adjust either with
`options(countryatlas.cache_max_age = )` (seconds) and
`options(countryatlas.cache_max_size = )` (bytes). A pinned World Bank
release
([`wdi_vintages()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdi_vintages.md))
never changes, so its entries never expire.

## See also

[`country_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_sources.md),
[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md)

## Examples

``` r
clear_country_cache()
```
