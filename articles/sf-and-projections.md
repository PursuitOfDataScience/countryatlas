# Modern maps with sf & projections

The legacy `maps` polygons are an unprojected plate carrée: they badly
distort area and split Russia, Fiji and New Zealand across the
antimeridian. The `sf` backend fixes all of this — real projections,
equal-area options, and an antimeridian-safe pipeline. These features
require the optional `sf` and `rnaturalearth` packages.

``` r

install.packages(c("sf", "rnaturalearth", "rnaturalearthdata"))
```

## An equal-area, projected choropleth

``` r

world_data(2020, c(gdp = "NY.GDP.PCAP.KD"), geometry = "sf") |>
  world_map(gdp, style = "quantile", projection = "equal_earth",
            title = "GDP per capita (Equal Earth projection)")
```

[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
auto-detects the `sf` backend and applies the projection through
[`ggplot2::coord_sf()`](https://ggplot2.tidyverse.org/reference/ggsf.html).
Available projections are `"equal_earth"` (the default — equal-area and
good-looking), `"robinson"`, `"mollweide"`, `"natural_earth"`,
`"plate_carree"`, `"mercator"`, `"winkel_tripel"`, `"eckert4"`,
`"gall_peters"`, `"orthographic"`, `"azimuthal_equal_area"`,
`"north_polar"` and `"south_polar"`.

[`projection_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_info.md)
says what each one preserves, so you do not have to remember:

``` r

projection_info()[, c("projection", "property", "equal_area")]
#> # A tibble: 13 × 3
#>    projection           property    equal_area
#>    <chr>                <chr>       <lgl>     
#>  1 equal_earth          equal-area  TRUE      
#>  2 robinson             compromise  FALSE     
#>  3 mollweide            equal-area  TRUE      
#>  4 natural_earth        compromise  FALSE     
#>  5 plate_carree         equidistant FALSE     
#>  6 mercator             conformal   FALSE     
#>  7 winkel_tripel        compromise  FALSE     
#>  8 eckert4              equal-area  TRUE      
#>  9 gall_peters          equal-area  TRUE      
#> 10 orthographic         perspective FALSE     
#> 11 azimuthal_equal_area equal-area  TRUE      
#> 12 north_polar          equal-area  TRUE      
#> 13 south_polar          equal-area  TRUE
```

For a choropleth the equal-area ones are the honest choice, because the
reader reads coloured area as quantity.
[`projection_compare()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_compare.md)
draws your own data under several at once and
[`tissot_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tissot_map.md)
shows the distortion directly — see the *Honest maps* vignette.

## The world as a globe

[`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)
draws an orthographic globe centred on `lon`/`lat`. The default `"sf"`
backend gives the cleanest limb; the `"polygon"` backend below needs
only `maps` + `mapproj` (no `sf`):

``` r

globe_map(world_snapshot$countries, continent, backend = "polygon",
          style = "categorical", lon = 10, lat = 20)
```

![Orthographic globe centred on the Indian Ocean, countries coloured by
continent.](sf-and-projections_files/figure-html/globe-1.png)

``` r

# With the sf backend (smoother limb, real great circles):
world_data(2020, geometry = "sf") |>
  globe_map(gdp_per_capita, lon = 10, lat = 30)
```

[`spin_globe()`](https://pursuitofdatascience.github.io/countryatlas/reference/spin_globe.md)
turns that into a rotating animation — one
[`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md)
frame per central longitude, assembled into a looping GIF with `gifski`
(or `magick`):

``` r

spin_globe(world_snapshot$countries, continent, backend = "polygon",
           style = "categorical", n_frames = 60)
```

## Just the canvas

[`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md)
returns projected, region-subset, antimeridian-safe geometry without any
data — country polygons, label-ready centroids, coastlines, a graticule
or an ocean rectangle:

``` r

africa <- world_geometry("countries", geometry = "sf", region = "Africa",
                         projection = "equal_earth")
ggplot(africa) +
  geom_sf(fill = "grey85", colour = "grey40", linewidth = 0.1) +
  theme_world_map()
```

![Africa drawn on its own under an Equal Earth
projection.](sf-and-projections_files/figure-html/unnamed-chunk-7-1.png)

## Recentring and the antimeridian

A Pacific-centred world is one argument away; the `sf` pipeline runs
[`sf::st_break_antimeridian()`](https://r-spatial.github.io/sf/reference/st_break_antimeridian.html)
before projecting, so nothing streaks across the frame:

``` r

world_geometry("countries", geometry = "sf", recenter = 150)
```

## Region subsetting

`region` accepts a continent, a group name (`"EU"`, `"OECD"`, …), a
vector of `iso3c` codes, or a bounding box `c(xmin, ymin, xmax, ymax)`.
Pair it with a `projection` suited to the subset
(e.g. `"azimuthal_equal_area"` for a single continent, the polar
projections for the Arctic) so the crop stays area-honest.

A box is the one form that clips the shapes themselves, which is what
you want for a region that is neither a continent nor a group — the
Mediterranean basin, say. Use the `sf` backend for it: that clip is a
real
[`sf::st_crop()`](https://r-spatial.github.io/sf/reference/st_crop.html),
whereas the polygon backend can only drop the vertices outside the box
and warns that a country crossing the edge comes back with an
approximate outline.

``` r

med <- world_geometry("countries", geometry = "sf",
                      region = c(-10, 30, 40, 48), projection = "equal_earth")
ggplot(med) +
  geom_sf(fill = "grey85", colour = "grey40", linewidth = 0.1) +
  theme_world_map()
```

![The Mediterranean basin cropped by bounding box under an Equal Earth
projection.](sf-and-projections_files/figure-html/unnamed-chunk-10-1.png)

## Simplifying for the web

High-resolution geometry can be thinned for fast plotting with
[`simplify_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/simplify_geometry.md)
(which uses `rmapshaper` when available). `scale = "medium"` is the 50m
Natural Earth data; `"large"` is 10m and additionally needs the
`rnaturalearthhires` package, which is not on CRAN.

``` r

world_geometry(geometry = "sf", scale = "medium") |>
  simplify_geometry(keep = 0.1)
```
