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
  [`world_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_map.md)
  (either engine),
  [`bubble_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bubble_map.md),
  [`spike_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/spike_map.md),
  [`tile_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md),
  [`flow_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/flow_map.md),
  [`od_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/od_map.md),
  [`globe_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/globe_map.md),
  [`bivariate_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/bivariate_map.md),
  [`cartogram_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/cartogram_map.md),
  [`dorling_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/dorling_map.md),
  [`gridded_cartogram()`](https://pursuitofdatascience.github.io/countryatlas/reference/gridded_cartogram.md),
  [`value_by_alpha_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/value_by_alpha_map.md),
  [`coverage_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/coverage_map.md),
  [`classify_compare()`](https://pursuitofdatascience.github.io/countryatlas/reference/classify_compare.md),
  [`facet_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/facet_map.md),
  [`lisa_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/lisa_map.md),
  [`subnational_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/subnational_map.md)
  or
  [`projection_compare()`](https://pursuitofdatascience.github.io/countryatlas/reference/projection_compare.md)
  – or a map-ready data frame, for which the data-side facts are
  reported and the drawing-side ones are `NA`.

  [`tissot_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tissot_map.md)
  is the one map verb that carries no provenance: it draws distortion
  ellipses for a projection and takes no data of yours.

- value:

  For a data frame, the column whose coverage to report (unquoted).
  Ignored for a plot, which already knows its own fill.

## Value

A one-row tibble of provenance fields, invisibly printed in a
human-readable block. Fields: `countryatlas`, `fill`, `backend`,
`projection`, `style`, `modified`, `n_bins`, `na_style`, `n_countries`,
`n_missing`, `n_total`, `uncertainty`, `disputes`, `dispute_policy`,
`worldview`, `n_imputed`, `breaks`, `missing_iso3c`, `snapshot_year`,
and `sources`, the
[`source_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_info.md)
record of the fill column when the data carried one – which the print
names: "World Bank WDI NY.GDP.PCAP.KD (constant 2015 US\$), release
2026-07, fetched 2026-10-01".

`projection` and `style` describe the plot as it is now, read from its
coordinate system and fill scale: a map given `+ coord_sf(crs = 3035)`
after the verb drew it reports `"custom"`, and `modified = TRUE` says
the plot no longer matches what the verb recorded.

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
p <- attach_geometry(snap, geometry = "polygon") |>
  world_map(gdp_per_capita, style = "quantile")
map_provenance(p)
#> 
#> ── countryatlas map provenance 
#> package: countryatlas 4.0.0 (snapshot 2024)
#> fill: gdp_per_capita
#> geometry: polygon backend, equal_earth
#> classification: quantile, 5 bins
#> missing data: grey
#> coverage: 199 countries shown, 39 missing
#> breaks: 268.7 | 1684 | 4655 | 10250 | 30130 | 247200
#> data: World Bank WDI NY.GDP.PCAP.KD (constant 2015 US$), release 2026-07,
#> fetched 2026-10-02
# }
```
