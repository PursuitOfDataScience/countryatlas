# Map subnational data

A choropleth below the country level, joining your data to NUTS geometry
on the region code. The subnational counterpart to
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md),
scoped to where a maintained code system and free geometry actually
exist.

## Usage

``` r
subnational_map(
  data,
  fill,
  by = "nuts_id",
  level = 2,
  year = 2021,
  countries = NULL,
  resolution = "60",
  ...
)
```

## Arguments

- data:

  A frame with a NUTS/ISO 3166-2 code column.

- fill:

  The fill column (unquoted).

- by:

  The code column in `data` (default `"nuts_id"`; use `"iso_3166_2"` if
  you came through
  [`standardize_subnational()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_subnational.md)).

- level, year, countries, resolution:

  Passed to
  [`nuts_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/nuts_geometry.md).

- ...:

  Passed to
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md).

## Value

A `ggplot` object.

## See also

[`nuts_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/nuts_geometry.md),
[`standardize_subnational()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_subnational.md),
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)

## Examples

``` r
if (FALSE) { # \dontrun{
d <- data.frame(nuts_id = c("DE21", "DE22"), value = c(1, 2))
subnational_map(d, value, level = 2, countries = "DEU")
} # }
```
