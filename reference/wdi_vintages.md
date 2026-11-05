# The World Development Indicators releases the archive holds

Every release in the World Bank's WDI Database Archives (API source 57),
oldest first, so a figure can be pinned to the release it came from with
`vintage =` in
[`fetch_indicator()`](https://pursuitofdatascience.github.io/countryatlas/reference/fetch_indicator.md),
[`country_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_data.md)
and
[`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md).
The list is fetched once a day per session.

## Usage

``` r
wdi_vintages()
```

## Value

A tibble of `vintage` (`"2024-07"`), `id` (the API's `"202407"`) and
`label` (the API's own, `"2024 Jul"`). On a failed request, a warning
and no rows, unless `options(countryatlas.strict = TRUE)`.

## See also

[`compare_vintages()`](https://pursuitofdatascience.github.io/countryatlas/reference/compare_vintages.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Needs the World Bank API.
tail(wdi_vintages())
} # }
```
