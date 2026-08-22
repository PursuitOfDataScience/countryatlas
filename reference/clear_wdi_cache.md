# Clear the on-disk / in-memory WDI cache

Forget memoised World Bank fetches, both in-session and (optionally) on
disk.

## Usage

``` r
clear_wdi_cache(disk = FALSE)
```

## Arguments

- disk:

  Whether to also delete the persistent on-disk cache.

## Value

Invisibly `TRUE`.

## Where the cache lives

The persistent cache goes in the standard per-user cache location,
`tools::R_user_dir("countryatlas", "cache")`. Point it elsewhere with
`options(countryatlas.cache_dir = )`, or skip the disk entirely by
passing `cache = FALSE` to
[`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
/
[`country_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_data.md).
Nothing is written until a World Bank fetch actually succeeds, so a
purely offline session (examples, tests, the bundled
[world_snapshot](https://pursuitofdatascience.github.io/countryatlas/reference/world_snapshot.md))
never creates it.

## Examples

``` r
clear_wdi_cache()              # forget the in-session memo
if (FALSE) { # \dontrun{
clear_wdi_cache(disk = TRUE)   # also delete the persistent cache
} # }
```
