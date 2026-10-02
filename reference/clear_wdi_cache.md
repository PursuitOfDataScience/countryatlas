# Clear the World Bank cache (deprecated)

**\[deprecated\]**

`clear_wdi_cache()` was generalised into
[`clear_country_cache()`](https://pursuitofdatascience.github.io/countryatlas/reference/clear_country_cache.md)
in 3.0.0, which clears any source's cache; `clear_wdi_cache(disk)` is
`clear_country_cache("wdi", disk)`. It now says so, and goes in 5.0.0.

## Usage

``` r
clear_wdi_cache(disk = FALSE)
```

## Arguments

- disk:

  Whether to also delete the persistent on-disk cache.

## Value

Invisibly `TRUE`.

## Examples

``` r
clear_country_cache("wdi")   # instead of clear_wdi_cache()
```
