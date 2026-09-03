# NUTS geometry for Europe

European subnational boundaries from Eurostat's GISCO service via the
optional `giscoR` package. Nothing is bundled – the geometry is
downloaded and cached by `giscoR` itself.

## Usage

``` r
nuts_geometry(
  level = 2,
  year = 2021,
  countries = NULL,
  resolution = "60",
  projection = "equal_earth"
)
```

## Arguments

- level:

  NUTS level: `0` (country), `1`, `2` or `3` (most detailed).

- year:

  NUTS vintage: `2003`, `2006`, `2010`, `2013`, `2016` or `2021`.
  Boundaries and codes are revised between vintages, which is why this
  is explicit – joining 2013 data to 2021 geometry silently loses
  regions.

- countries:

  Optional `iso3c` vector to subset to.

- resolution:

  GISCO resolution: `"60"` (1:60 million, default), `"20"`, `"10"`,
  `"03"` or `"01"`.

- projection:

  Projection for the result (see
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)),
  or `NULL` for unprojected.

## Value

An `sf` frame with `nuts_id`, `iso3c`, `name`, `level` and geometry.

## See also

[`standardize_subnational()`](https://pursuitofdatascience.github.io/countryatlas/reference/standardize_subnational.md),
[`subnational_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/subnational_map.md)

## Examples

``` r
if (FALSE) { # \dontrun{
nuts_geometry(level = 2, countries = c("DEU", "FRA"))
} # }
```
