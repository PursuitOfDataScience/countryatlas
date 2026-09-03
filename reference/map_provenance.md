# What went into this map

Report the provenance of a
[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
(or any plot the package's map verbs produced): the package version, the
geometry backend and projection, the classification method and its
breaks, the fill column, and how many countries are shown versus
missing. These are the questions a reviewer asks first, and the answers
are already known at plot time – this just makes them readable.

## Usage

``` r
map_provenance(x, value = NULL)
```

## Arguments

- x:

  A plot returned by any of the package's map verbs –
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md),
  [`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md),
  [`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md),
  [`tile_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md),
  [`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md),
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md),
  [`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md),
  [`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md),
  [`dorling_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/dorling_map.md),
  [`gridded_cartogram()`](https://pursuitofdatascience.github.io/countryatlas/reference/gridded_cartogram.md),
  [`value_by_alpha_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/value_by_alpha_map.md),
  [`coverage_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/coverage_map.md),
  [`classify_compare()`](https://pursuitofdatascience.github.io/countryatlas/reference/classify_compare.md),
  [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md)
  or
  [`lisa_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/lisa_map.md)
  – or a map-ready data frame, for which the data-side facts are
  reported and the drawing-side ones are `NA`.

- value:

  For a data frame, the column whose coverage to report (unquoted).
  Ignored for a plot, which already knows its own fill.

## Value

A one-row tibble of provenance fields, invisibly printed in a
human-readable block. Fields: `countryatlas`, `fill`, `backend`,
`projection`, `style`, `n_bins`, `na_style`, `n_countries`, `n_missing`,
`n_total`, `uncertainty`, `disputes`, `dispute_policy`, `n_imputed`,
`breaks`, `missing_iso3c` and `snapshot_year`.

The three counts are: `n_countries`, the countries actually drawn with a
value; `n_missing`, those drawn without one; and `n_total`, the two
added together – every country the map covers. `n_countries` is the
numerator, not the denominator, which its name does not say on its own.

## Putting it on the plot

[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)`(footnote = "auto")`
prints the coverage line as a caption, and
`classification_report = TRUE` attaches the per-class counts. Together
they cover what a methods note needs:

    p <- world_map(mapdf, gdp_per_capita, style = "quantile",
                   footnote = "auto", classification_report = TRUE)
    map_provenance(p)
    attr(p, "countryatlas_classification")

## See also

[`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md),
[`audit_coverage()`](https://pursuitofdatascience.github.io/countryatlas/reference/audit_coverage.md),
[`coverage_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/coverage_map.md)

## Examples

``` r
# \donttest{
snap <- countryatlas::world_snapshot$countries
if (requireNamespace("maps", quietly = TRUE)) {
  p <- attach_geometry(snap, geometry = "polygon") |>
    world_map(gdp_per_capita, style = "quantile")
  map_provenance(p)
}
#> 
#> ── countryatlas map provenance 
#> package: countryatlas 3.0.0 (snapshot 2024)
#> fill: gdp_per_capita
#> geometry: polygon backend, coord_quickmap
#> classification: quantile, 5 bins
#> missing data: grey
#> coverage: 189 countries shown, 51 missing
#> breaks: 268.7 | 1662 | 4594 | 10290 | 29370 | 247200
# }
```
