## Submission

This is a major release, 4.0.0. 3.0.0 passed the incoming checks on
2026-10-01; this release implements the plan written after it.

The headline change is that maps are equal-area by default on both backends,
with nothing extra to install: the polygon backend now draws bundled Natural
Earth 1:50m polygons (public domain, 0.5 MB in `R/sysdata.rda`) in Equal
Earth, through `coord_sf()` when `sf` loads and with the package's own
spherical Equal Earth when it does not. Around it: dated World Bank income
groups and regions, group memberships with spells, pinnable World Bank
releases, a source record carried with every fetched column, a generic SDMX
reader, multiple-testing control in the local spatial statistics, and maps
that state their coverage and source and describe themselves in alt text.

## Breaking changes

Every one is listed in `NEWS.md` with the argument that restores the old
behaviour. The ones that change output for existing code:

* The polygon backend is projected (Equal Earth by default); way back
  `projection = "none"`.
* The polygon backend draws the bundled Natural Earth polygons rather than
  `maps::map_data("world")`; way back `geometry = "maps"`, deprecated for
  one release.
* Map verbs default to `style = "quantile"` (way back `style =
  "continuous"`), add a coverage-and-source caption (`footnote = FALSE`), and
  draw small states as points (`small_states = "none"`).
* Lags, differences and year-on-year growth are keyed on the year, `NA`
  across a gap (way back `by = "row"`).
* `country_join()` also joins on a shared `year` (`also_by = character()`);
  partial-coverage regional aggregates are `NA` below two-thirds coverage
  (`min_coverage = 0`); spatial statistics default to k-nearest-neighbour
  weights and adjust local p-values for the false discovery rate.

## Removed and renamed

* Removed after warning for a release: `wdj_overrides()` (use
  `country_overrides()`) and `options(countryatlas.gdp_compat)`.
* Renamed, the old names deprecated through lifecycle and still working until
  5.0.0: `convert_country(from)` is `origin`, `classify_compare(n)` is
  `n_bins`, `flow_map(n)` is `arc_points`, `repair_country_names(verbose)` is
  `quiet`. `clear_wdi_cache()` is deprecated in favour of
  `clear_country_cache()`.

## Dependencies

* New in `Imports`: `curl` (one HTTP client with timeouts and bounded
  retries for every fetch) and `lifecycle` (deprecations, already installed
  with `dplyr`, `ggplot2` and `tibble`).
* New in `Suggests`: `colorspace` (colour-vision simulation in
  `check_palette()`).
* Removed from `Suggests`: `owidR` and `OECD`. Neither could return data:
  Our World in Data changed its API, and OECD.Stat, which the `OECD` package
  targets, has been offline since 2024-07-01. Both sources are rebuilt on the
  providers' current APIs.

## R CMD check results

`R CMD check --as-cran --run-donttest` of the 4.0.0 tarball on R 4.4.1, with
every Suggest that installs there, gives 0 errors. The URL and spelling checks
are clean, and the rest is the maintainer's machine or `--run-donttest`:

* WARNING, `qpdf` is not installed on the maintainer's machine.
* NOTEs of the machine: `ggsql` and `magick` cannot be installed there, no
  `tidy` binary, "unable to verify current time".
* NOTE, examples over 5 s under `--run-donttest`: `cartogram_diagnostics()`
  (18 s, building a contiguous cartogram) and `spin_globe()` (7 s). Both are
  inside `\donttest{}`.
* NOTE, new files in other directories: `~/.cache/fontconfig` only, which the
  system fontconfig library creates the first time R's cairo PNG device draws
  (here, while the vignettes are rebuilt). It appears because the check ran
  with an empty `HOME` so that any stray write would show; the package writes
  nothing outside `tempdir()`.

The depends-only configuration (R 4.6.0, every Suggest absent,
`_R_CHECK_DEPENDS_ONLY_=true`) passes the tests, examples and vignettes.

## Reverse dependencies

There are none.

## The marked-UTF-8 strings note

On older R (4.1.x) the check reports `Note: found 263 marked UTF-8 strings`.
They are intentional and correctly marked: the flag emoji in
`country_meta$flag`, behind `convert_country(x, to = "flag")`, and accented
country names ("Curacao", "Cote d'Ivoire", "Reunion", "St. Barthelemy", "Sao
Tome & Principe", "Aland Islands") in `country_meta`, `world_tiles` and
`historical_codes`. Every name in the curated override table is plain ASCII
by design, so name matching does not depend on the locale.

## Notes

* Examples: of the 121 documented topics with an `\examples{}` block, 60 run
  unconditionally, 51 use `\donttest{}` and 12 use `\dontrun{}` (two use
  both). No example needs the network to succeed: a failed fetch degrades to
  a warning and an empty result, as CRAN policy asks.
* Tests that need the network are skipped on CRAN, and the slowest tests carry
  `skip_on_cran()` so the CRAN-mode test step stays short; every CI leg sets
  `NOT_CRAN=true` and runs all of them.
* The persistent cache lives in `tools::R_user_dir("countryatlas", "cache")`
  with an expiry and a size cap, and under `tempdir()` whenever
  `_R_CHECK_PACKAGE_NAME_` is set, so a check writes nothing outside it.
