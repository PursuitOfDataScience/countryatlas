# Attach geometry to a country-level table

The bridge between a one-row-per-country table (e.g. from
[`country_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_data.md))
and plotting: bolts polygon or `sf` geometry onto your data, keyed on
`iso3c`.

## Usage

``` r
attach_geometry(
  data,
  by = "iso3c",
  geometry = c("polygon", "sf"),
  scale = "small",
  region = NULL,
  projection = "equal_earth",
  recenter = NULL,
  overrides = country_overrides()
)
```

## Arguments

- data:

  A data frame with an `iso3c` (or `by`) column.

- by:

  The join key (default `"iso3c"`).

- geometry:

  `"polygon"` (default) or `"sf"`.

- scale:

  Natural Earth resolution for the `sf` backend. `"large"` needs the
  non-CRAN `rnaturalearthhires` package; see
  [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md).
  It also affects which countries are covered at all – see below.

- region:

  Optional region subset (see
  [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md)).

- projection, recenter:

  Projection, and optional central meridian, for the `sf` backend (see
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  for the projections available).

- overrides:

  Name -\> iso3c overrides applied when matching the geometry backend's
  country names (default
  [`country_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)).
  Pass a custom set built with
  [`country_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)
  to add your own.

## Value

For `"polygon"`, a tibble with `long`/`lat`/`group` plus your columns.
For `"sf"`, an `sf` object.

## One row in, one row out

Geometry is attached once **per row**, not once per country. That is
what a panel wants – one row per country-year, each carrying the shape –
but it means a frame that repeats a country by accident draws that
country more than once, and only the last one painted is visible. The
package cannot tell the two apart (a panel's time column may be called
anything), so reduce to one row per country yourself when that is what
you meant.

## Which countries have geometry

The join keeps only countries the chosen backend actually carries, so
rows of `data` with no matching geometry are dropped silently – worth
checking first when a country you expected is missing from the map.
Coverage differs by backend and, for `"sf"`, by `scale`, which changes
*which* countries are present and not merely how detailed they look. Of
the 215 countries in
[world_snapshot](https://pursuitofdatascience.github.io/countryatlas/reference/world_snapshot.md),
`"polygon"` carries 210, `"sf"` with `scale = "small"` (the default,
110m) carries 169, and `"sf"` with `scale = "medium"` carries 214: the
110m coastlines omit most small states, so `scale = "medium"` is the fix
when microstates matter – Hong Kong, Macao, Tuvalu and the British
Virgin Islands are each in no other backend. Gibraltar alone is in none
of them.

## Examples

``` r
# \donttest{
df <- data.frame(iso3c = c("USA", "CAN"), value = c(1, 2))
if (requireNamespace("maps", quietly = TRUE)) {
  attach_geometry(df, geometry = "polygon")
}
#> # A tibble: 99,338 × 9
#>     long   lat group order region subregion iso3c iso2c value
#>    <dbl> <dbl> <dbl> <int> <chr>  <chr>     <chr> <chr> <dbl>
#>  1 -69.9  12.5     1     1 Aruba  NA        ABW   AW       NA
#>  2 -69.9  12.4     1     2 Aruba  NA        ABW   AW       NA
#>  3 -69.9  12.4     1     3 Aruba  NA        ABW   AW       NA
#>  4 -70.0  12.5     1     4 Aruba  NA        ABW   AW       NA
#>  5 -70.1  12.5     1     5 Aruba  NA        ABW   AW       NA
#>  6 -70.1  12.6     1     6 Aruba  NA        ABW   AW       NA
#>  7 -70.0  12.6     1     7 Aruba  NA        ABW   AW       NA
#>  8 -70.0  12.6     1     8 Aruba  NA        ABW   AW       NA
#>  9 -69.9  12.5     1     9 Aruba  NA        ABW   AW       NA
#> 10 -69.9  12.5     1    10 Aruba  NA        ABW   AW       NA
#> # ℹ 99,328 more rows
# }
```
