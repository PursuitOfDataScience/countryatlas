# Geometry without the data

Sometimes you just want the canvas: country polygons, label-ready
centroids, coastlines, internal borders, a graticule or an ocean
rectangle – already projected, region-subset and antimeridian-safe. This
is the building block the plotting functions sit on, exposed for power
users.

## Usage

``` r
world_geometry(
  what = c("countries", "centroids", "coastline", "borders", "graticule", "ocean"),
  geometry = c("polygon", "sf"),
  scale = "small",
  region = NULL,
  projection = "equal_earth",
  recenter = NULL,
  year = NULL,
  worldview = NULL
)
```

## Arguments

- what:

  What to return: `"countries"` (default), `"centroids"`, `"coastline"`,
  `"borders"`, `"graticule"` or `"ocean"`.

- geometry:

  `"polygon"` (a tibble of `long`/`lat`/`group`: the bundled Natural
  Earth 1:50m countries, which need no extra package) or `"sf"`.
  `"maps"` draws the polygon backend from the `maps` package as releases
  before 4.0.0 did; it is deprecated.

- scale:

  Natural Earth resolution for the `sf` backend: `"small"` (110m),
  `"medium"` (50m) or `"large"` (10m). The polygon backend draws its one
  bundled resolution, 1:50m, and warns if asked for `"large"`. `"large"`
  additionally needs the `rnaturalearthhires` package, which is not on
  CRAN (`install.packages("rnaturalearthhires", repos =`
  `"https://ropensci.r-universe.dev")`); `"small"` and `"medium"` need
  nothing beyond `rnaturalearthdata`. Coarser scales carry fewer
  countries as well as less detail – see
  [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md).

- region:

  Optional subset: a continent, a group name, a vector of `iso3c` codes,
  or a bounding box `c(xmin, ymin, xmax, ymax)`. A box is the one form
  that clips the shapes themselves rather than selecting whole countries
  – properly, via
  [`sf::st_crop()`](https://r-spatial.github.io/sf/reference/st_crop.html),
  on the `sf` backend. The polygon backend can only drop the vertices
  outside the box, which leaves a country straddling the edge with an
  approximate outline, so it warns.

- projection:

  Projection for the `sf` backend (see
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)).
  The polygon backend returns longitude/latitude, which the map verbs
  project when they draw, and warns if asked to project here.

- recenter:

  Optional central meridian (e.g. `150`). On the polygon backend every
  ring is cut at the new antimeridian and shifted, so the longitudes run
  from `recenter - 180` to `recenter + 180`.

- year:

  Draw the world as it was in this year, via
  [`historical_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/historical_geometry.md)
  and CShapes (1886-2019). Returns `sf` keyed on `gwcode`; only
  `what = "countries"` is available, and `region` cannot be combined
  with it.

- worldview:

  Draw the boundaries as one country's government draws them: the
  viewing country's ISO alpha-3 code (`"IND"`, `"CHN"`, ...) or `"ISO"`,
  for one of the 31 points of view Natural Earth publishes. Needs
  `geometry = "sf"`; the file is Natural Earth's 1:10m, downloaded once
  (about 5 MB) into the package's cache. `NULL` (default) is the
  worldview set with
  [`dispute_policy()`](https://pursuitofdatascience.github.io/countryatlas/reference/dispute_policy.md),
  if any, and otherwise Natural Earth's own de facto boundaries. The
  package takes no position: you choose, and
  [`map_provenance()`](https://pursuitofdatascience.github.io/countryatlas/reference/map_provenance.md)
  records the choice.

## Value

A tibble (polygon backend) or `sf` object (sf backend), with columns
depending on `what`:

- `"countries"`:

  polygon: `long`, `lat`, `group`, `order`, `region`, `subregion`,
  `iso3c`, `iso2c`. sf: `iso3c`, `iso2c`, `name_long`.

- `"centroids"`:

  the same identifier columns plus `centroid_lon` and `centroid_lat`.

- `"coastline"`, `"borders"`, `"ocean"`, `"graticule"`:

  sf only.

**The centroid columns are in the coordinate system of the object
returned**, so on the sf backend they are projected metres, not degrees
– `centroid_lon` for France is `174097`, not `2.1`. For centroids in
degrees use
[country_meta](https://pursuitofdatascience.github.io/countryatlas/reference/country_meta.md)`$centroid_lon`
/ `$centroid_lat`, which is also what the polygon backend returns.

A few Natural Earth features have no ISO code and so come back with
`iso3c` `NA` – Somaliland at every scale, plus the Indian Ocean
Territories and Ashmore and Cartier Islands from `"medium"` on. They are
kept so the land is still drawn; drop or
[`country_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/country_overrides.md)
them if you group by `iso3c`.

`"orthographic"` is the one genuinely hemispheric projection: the
countries on the far side have no image and come back as empty
geometries, and the ones on the horizon are cut there (correctly, but
[`sf::st_coordinates()`](https://r-spatial.github.io/sf/reference/st_coordinates.html)
cannot read a column that mixes empty and non-empty – drop them first).
The other three azimuthal projections (`"azimuthal_equal_area"`,
`"north_polar"`, `"south_polar"`) are Lambert equal-area and draw the
*whole* globe, the far side stretched around the rim rather than
dropped, so pass `region` if you want a polar view of the northern
countries alone. `"north_polar"` leaves out what lies wholly south of 60
degrees S (Antarctica), whose pole is its antipode: an empty geometry on
the sf backend, no rows on the polygon backend.

`"ocean"` is a whole-globe background rectangle. It is unavailable in
all four azimuthal projections – `"orthographic"` has no image for it,
and the Lambert three cut the globe at the antipode, which collapses the
rectangle's outline – and it cannot be recentred; both cases error
rather than returning an invisible layer.

## Examples

``` r
# \donttest{
head(world_geometry("countries", geometry = "polygon"))
#> # A tibble: 6 × 8
#>    long   lat group order region subregion iso3c iso2c
#>   <dbl> <dbl> <int> <int> <chr>  <chr>     <chr> <chr>
#> 1  131.  42.3     1     1 Russia NA        RUS   RU   
#> 2  131.  42.3     1     2 Russia NA        RUS   RU   
#> 3  131.  42.4     1     3 Russia NA        RUS   RU   
#> 4  131.  42.4     1     4 Russia NA        RUS   RU   
#> 5  131.  42.5     1     5 Russia NA        RUS   RU   
#> 6  131.  42.5     1     6 Russia NA        RUS   RU   
# }
```
