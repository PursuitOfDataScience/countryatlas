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
assigned – see below), `status`, `from`, `to` and geometry. Two further
CShapes columns are passed through when the installed version supplies
them, since they answer the questions this verb is usually asked:

- `owner` – the `gwcode` of the sovereign a dependency belonged to; a
  sovereign state carries its own `gwcode` here. This is the column that
  makes `dependencies = TRUE` legible: without it a colony and its
  metropole are two unrelated rows. `owner != gwcode` picks out the
  dependencies.

- `capname` – the capital's name at that date.

Both were returned but undocumented. Neither is guaranteed: `cshapes`
decides what its own table holds, so check with
[`names()`](https://rdrr.io/r/base/names.html) rather than assuming.

## The ISO spine does not reach back

ISO 3166 was first published in 1974 and never covered colonies, so a
historical map cannot be keyed on `iso3c`. CShapes uses
**Gleditsch-Ward** codes, which is why `gwcode` is the key here and
`iso3c` is a best-effort extra, read off the GW code: the modern code of
the state that holds it. So it is `NA` for an entity with no modern
counterpart (the German Democratic Republic, Czechoslovakia, Yugoslavia,
the two Yemens), and also where
[historical_codes](https://pursuitofdatascience.github.io/countryatlas/reference/historical_codes.md)
says the modern state did not exist yet – GW give the USSR and Russia
one code, but the 1980 polygon is the Soviet Union, so it carries `NA`
rather than `"RUS"`. A colony carries the code of the state it became:
CShapes names the 1950 Gold Coast "Ghana" and it comes back as `"GHA"`,
with `status` saying it was a colony. Join historical data on `gwcode`,
not on `iso3c`, and use
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
