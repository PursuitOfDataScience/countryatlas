# What a projection preserves

Look up the properties of the projections
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
understands: the construction family, whether it is equal-area (a
choropleth's ink is proportional to ground area) or conformal (shapes
are locally right), and the PROJ string the package builds. Called with
no arguments it returns the whole table, which is the quickest way to
see what is available.

## Usage

``` r
projection_info(projection = NULL)
```

## Arguments

- projection:

  A projection name, or `NULL` (the default) for every one.

## Value

A tibble with one row per projection: `projection`, `family`,
`property`, `equal_area`, `conformal`, `note` and `proj4`.

## Choosing one

For a world choropleth the honest choice is **equal-area**, because the
eye reads coloured area as quantity: a projection that inflates
Greenland makes Greenland's value look more important than it is. Equal
Earth is the recommended default (and the package's own) – it is
equal-area, close to Robinson in appearance, and cheap to evaluate
(Savric, Patterson & Jenny 2019). `"mercator"` is conformal, not
equal-area, and should not be used for choropleths. Use
[`projection_compare()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_compare.md)
to see the difference on your own data, and
[`tissot_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tissot_map.md)
to see it on the graticule.

## References

Savric, B., Patterson, T. & Jenny, B. (2019). The Equal Earth map
projection. *International Journal of Geographical Information Science*
33(3), 454-465.
[doi:10.1080/13658816.2018.1504949](https://doi.org/10.1080/13658816.2018.1504949)

## See also

[`projection_compare()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_compare.md),
[`tissot_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tissot_map.md),
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)

## Examples

``` r
projection_info()
#> # A tibble: 13 × 7
#>    projection           family         property equal_area conformal note  proj4
#>    <chr>                <chr>          <chr>    <lgl>      <lgl>     <chr> <chr>
#>  1 equal_earth          pseudocylindr… equal-a… TRUE       FALSE     Reco… +pro…
#>  2 robinson             pseudocylindr… comprom… FALSE      FALSE     Neit… +pro…
#>  3 mollweide            pseudocylindr… equal-a… TRUE       FALSE     Equa… +pro…
#>  4 natural_earth        pseudocylindr… comprom… FALSE      FALSE     Comp… +pro…
#>  5 plate_carree         cylindrical    equidis… FALSE      FALSE     Equi… +pro…
#>  6 mercator             cylindrical    conform… FALSE      TRUE      Conf… +pro…
#>  7 winkel_tripel        pseudoazimuth… comprom… FALSE      FALSE     Comp… +pro…
#>  8 eckert4              pseudocylindr… equal-a… TRUE       FALSE     Equa… +pro…
#>  9 gall_peters          cylindrical    equal-a… TRUE       FALSE     Equa… +pro…
#> 10 orthographic         azimuthal      perspec… FALSE      FALSE     A vi… +pro…
#> 11 azimuthal_equal_area azimuthal      equal-a… TRUE       FALSE     Equa… +pro…
#> 12 north_polar          azimuthal      equal-a… TRUE       FALSE     Lamb… +pro…
#> 13 south_polar          azimuthal      equal-a… TRUE       FALSE     Lamb… +pro…
projection_info("mercator")
#> # A tibble: 1 × 7
#>   projection family      property  equal_area conformal note               proj4
#>   <chr>      <chr>       <chr>     <lgl>      <lgl>     <chr>              <chr>
#> 1 mercator   cylindrical conformal FALSE      TRUE      Conformal, and fa… +pro…
# every equal-area projection the package can build
subset(projection_info(), equal_area)$projection
#> [1] "equal_earth"          "mollweide"            "eckert4"             
#> [4] "gall_peters"          "azimuthal_equal_area" "north_polar"         
#> [7] "south_polar"         
```
