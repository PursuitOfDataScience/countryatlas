# One call: your data, on a map

Auto-detects the country column, standardises it to ISO codes (via
[`standardize_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_country.md)),
attaches geometry and returns a plot-ready frame – the function that
fulfils the package's promise for *your* own data. Pipe the result
straight into
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md).

## Usage

``` r
join_world(
  data,
  country_col = NULL,
  origin = "country.name",
  geometry = c("polygon", "sf", "none"),
  scale = "small",
  region = NULL,
  projection = "equal_earth",
  recenter = NULL,
  warn = TRUE
)
```

## Arguments

- data:

  A data frame keyed on country names or codes.

- country_col:

  The country column (unquoted). If omitted, it is auto-detected.

- origin:

  How to read `country_col` (any countrycode origin scheme).

- geometry:

  `"polygon"` (default), `"sf"` or `"none"`.

- scale:

  Natural Earth resolution for the `sf` backend. `"large"` needs the
  non-CRAN `rnaturalearthhires` package; see
  [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md).

- region:

  Optional region subset (see
  [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md)).

- projection, recenter:

  Projection, and optional central meridian, for the `sf` backend (see
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  for the projections available).

- warn:

  Whether to report unmatched countries (default `TRUE`); also surfaces
  a
  [`check_country_match()`](https://pursuitofdatascience.github.io/countryatlas/reference/check_country_match.md)
  summary.

## Value

A plot-ready frame: polygon tibble, `sf` object, or (for
`geometry = "none"`) the standardised table.

## Examples

``` r
rates <- data.frame(country = c("United States", "Brazil", "Kenya"),
                    vaccination_pct = c(0.7, 0.8, 0.6))
# \donttest{
if (requireNamespace("maps", quietly = TRUE)) {
  joined <- join_world(rates, country)
}
# }
```
