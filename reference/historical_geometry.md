# Historical country boundaries

Country polygons as they were, from CShapes 2.0 (Schvitz et al. 2022),
which maps states *and* colonies and dependencies for 1886-2019 with
per-polygon validity periods. A 1970 map with 2024 borders is a common
and quiet error; this is the fix.

## Usage

``` r
historical_geometry(year, dependencies = FALSE, projection = "equal_earth")
```

## Arguments

- year:

  The year to draw, or a `Date` for a specific day. CShapes covers
  1886-2019.

- dependencies:

  Include colonies and dependencies (default `FALSE`, matching
  `cshapes`). For any pre-decolonisation map you almost certainly want
  `TRUE` – most of Africa and Asia is otherwise absent.

- projection:

  Projection to return the geometry in (see
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)),
  or `NULL` for unprojected lon/lat.

## Value

An `sf` frame with `gwcode`, `country`, `iso3c` (where one can be
assigned – see below), `status`, `from`, `to` and geometry.

## The ISO spine does not reach back

ISO 3166 was first published in 1974 and never covered colonies, so a
historical map cannot be keyed on `iso3c`. CShapes uses
**Gleditsch-Ward** codes, which is why `gwcode` is the key here and
`iso3c` is a best-effort extra: it is `NA` for every entity that never
had an ISO code (French West Africa, the Gold Coast, the USSR before
1974). Join historical data on `gwcode`, not on `iso3c`, and use
[`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md)`(to = "gwn")`
to get there from a modern code.

## References

Schvitz, G., Girardin, L., Ruegger, S., Weidmann, N. B., Cederman, L.-E.
& Gleditsch, K. S. (2022). Mapping the international system, 1886-2019:
The CShapes 2.0 dataset. *Journal of Conflict Resolution* 66(1),
144-161.
[doi:10.1177/00220027211013563](https://doi.org/10.1177/00220027211013563)

## See also

[`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md),
[`country_timeline()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_timeline.md),
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Africa before decolonisation needs the dependencies
historical_geometry(1950, dependencies = TRUE)
} # }
```
