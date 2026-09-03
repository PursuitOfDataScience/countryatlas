# Built-in source adapters

Thin wrappers that put a provider's data on the ISO spine. Each is
`Suggests`-gated on that provider's own client package – `countryatlas`
does not reimplement any of them. All four are registered as sources, so
the usual route is
[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md)`("owid", ...)`
rather than calling these directly; they are exported because calling
them directly is sometimes what you want.

## Usage

``` r
fetch_owid(indicator, countries = NULL, years = NULL, ...)

fetch_eurostat(indicator, countries = NULL, years = NULL, ...)

fetch_oecd(indicator, countries = NULL, years = NULL, ...)

fetch_comtrade(indicator, countries = NULL, years = NULL, ...)
```

## Arguments

- indicator:

  Indicator code(s), optionally named to rename the output columns.

- countries:

  Optional `iso3c` vector.

- years:

  Optional numeric year vector.

- ...:

  Passed to the underlying client.

## Value

A tibble on the ISO spine: `iso3c`, `year` and one column per indicator.

## Which provider needs what

|  |  |  |
|----|----|----|
| Adapter | Needs | Notes |
| `fetch_owid()` | `owidR` | Our World in Data; `indicator` is an OWID chart slug |
| `fetch_eurostat()` | `eurostat` | European coverage only; geo codes are harmonised to `iso3c` |
| `fetch_oecd()` | `OECD` | `indicator` is a dataset id; OECD's own filters go through `...` |
| `fetch_comtrade()` | `comtradr` | UN trade flows; needs an API token (see [`comtradr::set_primary_comtrade_key()`](https://docs.ropensci.org/comtradr/reference/set_primary_comtrade_key.html)) |

## See also

[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md),
[`register_country_source()`](https://pursuitofdatascience.github.io/countryatlas/reference/register_country_source.md),
[`compare_sources()`](https://pursuitofdatascience.github.io/countryatlas/reference/compare_sources.md)

## Examples

``` r
if (FALSE) { # \dontrun{
fetch_owid("life-expectancy", years = 2020)
fetch_eurostat("demo_pjan", years = 2020)
} # }
```
