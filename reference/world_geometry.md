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
  recenter = NULL
)
```

## Arguments

- what:

  What to return: `"countries"` (default), `"centroids"`, `"coastline"`,
  `"borders"`, `"graticule"` or `"ocean"`.

- geometry:

  `"polygon"` (a tibble of `long`/`lat`/`group`) or `"sf"`.

- scale:

  Natural Earth resolution for the `sf` backend: `"small"` (110m),
  `"medium"` (50m) or `"large"` (10m). `"large"` additionally needs the
  `rnaturalearthhires` package, which is not on CRAN
  (`install.packages("rnaturalearthhires", repos =`
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

- recenter:

  Optional central meridian for a recentred map (e.g. `150`).

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
[`country_overrides()`](https://pursuitofdatascience.github.io/countryatlas/reference/wdj_overrides.md)
them if you group by `iso3c`.

`"orthographic"` is the one genuinely hemispheric projection: the
countries on the far side have no image and come back as empty
geometries (correctly, but
[`sf::st_coordinates()`](https://r-spatial.github.io/sf/reference/st_coordinates.html)
cannot read a column that mixes empty and non-empty – drop them first).
The other three azimuthal projections (`"azimuthal_equal_area"`,
`"north_polar"`, `"south_polar"`) are Lambert equal-area and draw the
*whole* globe, the far side stretched around the rim rather than
dropped, so pass `region` if you want a polar view of the northern
countries alone.

`"ocean"` is a whole-globe background rectangle. It is unavailable in
all four azimuthal projections – `"orthographic"` has no image for it,
and the Lambert three cut the globe at the antipode, which collapses the
rectangle's outline – and it cannot be recentred; both cases error
rather than returning an invisible layer.

## Examples

``` r
# \donttest{
if (requireNamespace("maps", quietly = TRUE)) {
  head(world_geometry("countries", geometry = "polygon"))
}
#> # A tibble: 6 × 8
#>    long   lat group order region subregion iso3c iso2c
#>   <dbl> <dbl> <dbl> <int> <chr>  <chr>     <chr> <chr>
#> 1 -69.9  12.5     1     1 Aruba  NA        ABW   AW   
#> 2 -69.9  12.4     1     2 Aruba  NA        ABW   AW   
#> 3 -69.9  12.4     1     3 Aruba  NA        ABW   AW   
#> 4 -70.0  12.5     1     4 Aruba  NA        ABW   AW   
#> 5 -70.1  12.5     1     5 Aruba  NA        ABW   AW   
#> 6 -70.1  12.6     1     6 Aruba  NA        ABW   AW   
# }
```
