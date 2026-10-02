# Check a map's colours under colour-vision deficiency

Simulate how the map's fill colours look with deuteranopia, protanopia
and tritanopia – the Machado, Oliveira & Fernandes (2009) model, through
the optional `colorspace` – and report the smallest colour difference
between adjacent classes under each. Two classes a reader cannot tell
apart are two classes the map does not have. Roughly one man in twelve
has a red-green deficiency.

## Usage

``` r
check_palette(p, threshold = 10)
```

## Arguments

- p:

  A map from one of the package's map verbs, or a character vector of
  colours in class order.

- threshold:

  The smallest acceptable difference between adjacent classes (default
  `10`). Below it, a warning of class `countryatlas_palette_cvd` names
  the vision type and the two classes.

## Value

A tibble with one row per vision type (`normal`, `deuteranopia`,
`protanopia`, `tritanopia`): `min_delta_e`, and `between`, the two
classes that come closest.

## Details

The difference is CIE 1976 \\\Delta E^\*\_{ab}\\, the distance between
the two colours in CIELAB. A difference under about 10 is hard to tell
apart at the size of a small country on a map; the package's own
defaults (the viridis family) clear it under all three simulations.

## References

Machado, G. M., Oliveira, M. M. & Fernandes, L. A. F. (2009). A
physiologically-based model for simulation of color vision deficiency.
*IEEE Transactions on Visualization and Computer Graphics* 15(6),
1291-1298.
[doi:10.1109/TVCG.2009.113](https://doi.org/10.1109/TVCG.2009.113)

Crameri, F., Shephard, G. E. & Heron, P. J. (2020). The misuse of colour
in science communication. *Nature Communications* 11, 5444.
[doi:10.1038/s41467-020-19160-7](https://doi.org/10.1038/s41467-020-19160-7)

## Examples

``` r
# \donttest{
if (requireNamespace("colorspace", quietly = TRUE)) {
  snap <- countryatlas::world_snapshot$countries
  check_palette(world_map(attach_geometry(snap), gdp_per_capita))
  # A rainbow fails all three simulations:
  check_palette(grDevices::rainbow(7))
}
#> Warning: Adjacent classes are hard to tell apart under "deuteranopia", "protanopia", and
#> "tritanopia".
#> • deuteranopia, protanopia, and tritanopia: 2 and 3, 2 and 3, and 3 and 4
#>   (difference 8.8, 7.2, and 3.5).
#> ℹ Use fewer classes, or a palette whose lightness changes monotonically, such
#>   as "viridis" or "cividis".
#> # A tibble: 4 × 3
#>   vision       min_delta_e between
#>   <chr>              <dbl> <chr>  
#> 1 normal             46.2  3 and 4
#> 2 deuteranopia        8.82 2 and 3
#> 3 protanopia          7.21 2 and 3
#> 4 tritanopia          3.47 3 and 4
# }
```
