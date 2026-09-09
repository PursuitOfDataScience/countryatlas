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
The directory itself is created the first time a cached fetch is
attempted, whether or not the World Bank answers; only a successful
fetch leaves a response in it, and reading the bundled
[world_snapshot](https://pursuitofdatascience.github.io/countryatlas/reference/world_snapshot.md)
never goes near it. Under `R CMD check` the whole cache moves to the
session temp directory, so a check never writes to the user's file
space.

## How the cache is managed

The persistent cache expires its own contents, so it does not grow
without bound and does not serve stale figures indefinitely: an entry is
dropped once it is 30 days old, and if the directory exceeds 50 MB the
least-recently-used entries go first. Both limits are adjustable with
`options(countryatlas.cache_max_age = )` (seconds) and
`options(countryatlas.cache_max_size = )` (bytes). A dropped entry costs
a re-fetch, nothing more.

Expiry matters beyond disk space: World Bank observations are revised,
so a figure cached long ago is not necessarily the figure the API would
return today.

## Examples

``` r
clear_wdi_cache()              # forget the in-session memo
if (FALSE) { # \dontrun{
clear_wdi_cache(disk = TRUE)   # also delete the persistent cache
} # }
```
