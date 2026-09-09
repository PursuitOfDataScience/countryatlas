# Fetch an indicator and join it to your data

[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md)
plus
[`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md)
in one step: pull an indicator from any registered source and attach it
to a frame you already have, matched on the ISO spine (and on `year`
too, when both sides are panels).

## Usage

``` r
add_indicator(data, source, indicator, countries = NULL, years = NULL, ...)
```

## Arguments

- data:

  A frame with `iso3c` (or a country column
  [`join_world()`](https://pursuitofdatascience.github.io/countryatlas/reference/join_world.md)
  would recognise).

- source, indicator, countries, years, ...:

  Passed to
  [`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md).
  `countries` defaults to the codes already in `data`, so you never have
  to restate them. How much that saves depends on the source – see
  below.

## Value

`data` with the indicator column(s) added.

## How much `countries` actually saves

`countries` bounds the *result*, not necessarily the download. Only some
providers accept a country filter in the request:

|  |  |
|----|----|
| Source | `countries` reaches the provider? |
| `comtrade` | yes – sent as `reporter` |
| `wdi` | partly – the year range is sent, countries are filtered here |
| `owid`, `eurostat`, `oecd` | no – the full dataset is downloaded, then filtered |

So `add_indicator(one_row, "owid", "life-expectancy")` still transfers
every country and year that dataset holds in order to keep a single
value. When that matters, narrow with `years` (which the `wdi` and
`comtrade` adapters do push down), or fetch once into a variable and
reuse it rather than calling this per subset. The on-disk cache means a
repeated `wdi` fetch is free; the other sources are memoised for the
session only.

## See also

[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md),
[`country_join()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_join.md)

## Examples

``` r
if (FALSE) { # \dontrun{
world_snapshot$countries |>
  add_indicator("wdi", c(unemployment = "SL.UEM.TOTL.ZS"), years = 2020)
} # }
```
