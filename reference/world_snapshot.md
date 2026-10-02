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

  A tibble, one row per country, with `iso3c`, `iso2c`, `country`, the
  classifications `continent`, `region` and `income`, and the curated
  indicators `gdp_per_capita`, `population`, `life_expectancy` and
  `co2_per_capita`.

- sf:

  `NULL` in the released package – geometry is not bundled twice. Attach
  it on demand with
  [`attach_geometry()`](https://pursuitofdatascience.github.io/countryatlas/reference/attach_geometry.md):
  `attach_geometry(world_snapshot$countries, geometry = "sf")` pulls the
  same Natural Earth 110m polygons from `rnaturalearth`.

- year:

  The reference year.

`country` carries the World Bank's own names, which differ from the
`countrycode` names used by
[country_meta](https://pursuitofdatascience.github.io/countryatlas/reference/country_meta.md)
for 39 countries.

`income` and `region` are the World Bank's classifications in force on 1
January of the snapshot year (fiscal year 2024), from
[country_classifications](https://pursuitofdatascience.github.io/countryatlas/reference/country_classifications.md):
the regions are therefore the ones before the July 2025 change, with
Afghanistan and Pakistan in South Asia. Data fetched with
[`world_data()`](https://pursuitofdatascience.github.io/countryatlas/reference/world_data.md)
carries the current fiscal year's instead, and
[`source_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_info.md)
says which each frame holds.

The `"provenance"` attribute records the World Development Indicators
release the values come from, the build date, the package versions used,
and why the snapshot is on its year: it moves to a newer year only when
every indicator's coverage there is within five percentage points of the
current year's. The indicator columns carry a
[`source_info()`](https://pursuitofdatascience.github.io/countryatlas/reference/source_info.md)
record.

## Source

World Bank World Development Indicators, release 2026-07 (CC BY 4.0),
and the World Bank's classifications. Snapshot year: 2024.
