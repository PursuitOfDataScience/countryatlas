# Equal-area world tile-grid layout

A statebins-style equal-area tile layout: one square per country,
positioned on a `row`/`col` grid derived from country centroids. Used by
[`tile_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md).

## Usage

``` r
world_tiles
```

## Format

A tibble with columns `iso3c`, `country`, `row`, `col`; one row per
country, with `row`/`col` unique across the grid.

## Source

Derived from Natural Earth country centroids.

## Details

The grid holds one row for each of the 239 countries in
[country_meta](https://pursuitofdatascience.github.io/countryatlas/reference/country_meta.md)
that has a bundled centroid; the 10 without one (`ALA`, `BVT`, `GIB`,
`HKG`, `MAC`, `SJM`, `TKL`, `TUV`, `UMI`, `VGB` – see
[country_meta](https://pursuitofdatascience.github.io/countryatlas/reference/country_meta.md))
have no tile and so cannot be drawn by
[`tile_map()`](https://pursuitofdatascience.github.io/countryatlas/reference/tile_map.md).
