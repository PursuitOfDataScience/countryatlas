# Offline snapshot of world data

A small, lazy-loaded, one-row-per-country snapshot of a curated
indicator set for one recent year. It lets every example, test and
vignette run offline and deterministically, without the World Bank API.

## Usage

``` r
world_snapshot
```

## Format

A list with three elements:

- countries:

  A tibble, one row per country, with `iso3c`, `iso2c`, `country`,
  classifications and curated indicators (`gdp_per_capita`,
  `population`, `life_expectancy`, `co2_per_capita`).

- sf:

  `NULL` in the released package – geometry is not bundled twice. Attach
  it on demand with
  [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md)`(world_snapshot$countries,`
  `geometry = "sf")`, which pulls the same Natural Earth 110m polygons
  from `rnaturalearth`.

- year:

  The reference year.

## Source

World Bank via WDI; geometry from Natural Earth via rnaturalearth.
Snapshot year: 2024.
