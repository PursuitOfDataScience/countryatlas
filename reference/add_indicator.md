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
  `countries` defaults to the codes already in `data`, so only what you
  need is fetched.

## Value

`data` with the indicator column(s) added.

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
