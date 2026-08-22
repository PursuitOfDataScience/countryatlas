# Tag coordinates with the country that contains them

Point-in-polygon lookup: given longitude / latitude vectors (or an `sf`
POINT object), return the `iso3c` of the country each point falls in –
the bridge for getting point data (events, stations, observations) onto
the country spine so it can be joined, aggregated and mapped like
everything else.

## Usage

``` r
locate_country(
  lon = NULL,
  lat = NULL,
  points = NULL,
  scale = "small",
  add = "country",
  tolerance_km = 25
)
```

## Arguments

- lon, lat:

  Equal-length numeric vectors of longitude / latitude, giving one point
  per element (ignored if `points` is supplied).

- points:

  Optional `sf` POINT object to use instead of `lon`/`lat`.

- scale:

  Natural Earth resolution for the lookup geometry. `"large"` needs the
  non-CRAN `rnaturalearthhires` package; see
  [`world_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_geometry.md).

- add:

  Extra attributes to return alongside `iso3c` (any
  [`convert_country()`](https://pursuitofdatascience.github.io/countryatlas/reference/convert_country.md)
  destination, e.g. `"country"`, `"continent"`).

- tolerance_km:

  Snap an unmatched point to the nearest country when it lies within
  this many kilometres of one (default `25`). Coarse (110m) coastlines
  place some genuinely-onshore coastal points just outside their country
  (New York sits ~0.5 km beyond the simplified US coast); this rescues
  them while leaving open-ocean points `NA` (the nearest land is
  hundreds of km away). Set `0` for a strict point-in-polygon lookup.

## Value

A tibble with one row per point: `iso3c` plus any `add` columns (`NA`
for points that fall in no country, e.g. open ocean).

## Examples

``` r
# \donttest{
if (requireNamespace("sf", quietly = TRUE) &&
    requireNamespace("rnaturalearth", quietly = TRUE)) {
  locate_country(lon = c(2.35, -74.0), lat = c(48.85, 40.7))  # Paris, NYC
}
#> # A tibble: 2 × 2
#>   iso3c country      
#>   <chr> <chr>        
#> 1 FRA   France       
#> 2 USA   United States
# }
```
