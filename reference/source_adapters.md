# Built-in source adapters

Thin wrappers that put a provider's data on the ISO spine. Our World in
Data and the OECD are read straight from their public APIs through the
package's own HTTP client, with a timeout and bounded retries; Eurostat
and UN Comtrade go through their own client packages, which are
`Suggests`. All are registered as sources, so the usual route is
[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md)`("owid", ...)`
rather than calling these directly; they are exported because calling
them directly is sometimes what you want.

## Usage

``` r
fetch_owid(indicator, countries = NULL, years = NULL, ...)

fetch_eurostat(indicator, countries = NULL, years = NULL, ...)

fetch_oecd(indicator, countries = NULL, years = NULL, key = NULL, ...)

fetch_comtrade(indicator, countries = NULL, years = NULL, ...)
```

## Arguments

- indicator:

  Indicator code(s), optionally named to rename the output columns. For
  `fetch_owid()`, a grapher chart slug (`"life-expectancy"`), or
  `"slug/column"` to take one column of a chart that has several; for
  `fetch_oecd()`, an SDMX dataflow, `"AGENCY,DATAFLOW,VERSION"`.

- countries:

  Optional `iso3c` vector.

- years:

  Optional numeric year vector.

- ...:

  Passed to the underlying client (`fetch_eurostat()`,
  `fetch_comtrade()`); `fetch_owid()` and `fetch_oecd()` take nothing
  more.

- key:

  For `fetch_oecd()`, the SDMX key selecting the series within the
  dataflow (`"A..B1GQ_R_GR.."`); see
  [`fetch_sdmx()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_sdmx.md).
  `countries` goes into its country position, so the OECD filters on its
  server.

## Value

A tibble on the ISO spine: `iso3c`, `year` and one column per indicator.

## Which provider needs what

|  |  |  |
|----|----|----|
| Adapter | Needs | Notes |
| `fetch_owid()` | nothing | OWID's Chart API; `indicator` is a grapher slug, keyed on OWID's ISO codes |
| `fetch_oecd()` | nothing | the OECD's SDMX service; `indicator` is a dataflow, `key` selects the series |
| `fetch_eurostat()` | `eurostat` | European coverage only; geo codes are harmonised to `iso3c` |
| `fetch_comtrade()` | `comtradr` | UN trade flows; needs an API token (see [`comtradr::set_primary_comtrade_key()`](https://docs.ropensci.org/comtradr/reference/set_primary_comtrade_key.html)) |

The IMF and the ILO are reachable as
`fetch_indicator("imf", flow, key = )` and
`fetch_indicator("ilo", flow, key = )`, through
[`fetch_sdmx()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_sdmx.md).

## Our World in Data

A chart's data comes from
`https://ourworldindata.org/grapher/<slug>.csv` and its metadata –
title, unit, citation, last update – from the matching `.metadata.json`,
which feeds
[`source_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_info.md).
Rows are keyed on OWID's `code` column, which is ISO 3166-1 alpha-3 for
countries; OWID's own aggregates (`OWID_WRL`, the continents, the income
groups) are not countries and are dropped, except `OWID_KOS`, which is
Kosovo (`XKX`). A chart with several value columns returns them all,
named `<indicator>_<column>` (or by OWID's short column names when
`indicator` is unnamed), unless `"slug/column"` picks one.

## The OECD

OECD.Stat, which the OECD package's client targets, went offline on
2024-07-01, so the 3.0.0 adapter could not return data. The OECD Data
Explorer's dataflow ids replace the old dataset codes; find a flow and
its key at `https://data-explorer.oecd.org` (its "Developer API" panel
shows both). The old codes do not exist anywhere any more.

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
