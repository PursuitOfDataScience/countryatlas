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
* `as_ggsql_source()` returns a ggsql reader by default, the object ggsql
  0.5 executes queries against; way back `format = "duckdb"`.

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
  `check_palette()`) and `shiny (>= 1.6.0)` (a map module,
  `world_map_ui()` / `world_map_server()`).
* `ggsql` gains a version floor, `ggsql (>= 0.5.0)`: the database-side map
  queries are written for, and were checked against, ggsql 0.5.2, the first
  release on CRAN with its spatial layer. The tests and the vignette chunks
  that execute them need a network connection (DuckDB downloads its spatial
  extension into the session's temporary directory), so they are skipped on
  CRAN.
* Removed from `Suggests`: `owidR` and `OECD`. Neither could return data:
  Our World in Data changed its API, and OECD.Stat, which the `OECD` package
  targets, has been offline since 2024-07-01. Both sources are rebuilt on the
  providers' current APIs.

## R CMD check results

`R CMD check --as-cran --run-donttest` of the 4.0.0 tarball, built as it is
submitted, on R 4.4.1 with every Suggest that installs there, gives 0 errors
in 4.6 minutes (tests 42 s, examples 39 s, vignettes 61 s). The URL and
DESCRIPTION spelling checks are clean, and the rest is the maintainer's
machine:

* WARNING, `qpdf` is not installed on the maintainer's machine.
* NOTEs of the machine: `magick` cannot be installed there, no `tidy` binary
  and no `V8`, "unable to verify current time".
* NOTE, new files in other directories: `~/.cache/fontconfig` only, which the
  system fontconfig library creates the first time R's cairo PNG device draws
  (here, while the vignettes are rebuilt). It appears because the check ran
  with an empty `HOME` so that any stray write would show; the package writes
  nothing outside `tempdir()`.

The depends-only configuration (`_R_CHECK_DEPENDS_ONLY_=true`, every Suggest
absent) runs in CI on every push, alongside macOS, Windows and Linux on R
devel, release and oldrel.

## Reverse dependencies

There are none.

## The marked-UTF-8 strings note

On older R (4.1.x) the check reports `Note: found 266 marked UTF-8 strings`.
They are intentional and correctly marked: the flag emoji in
`country_meta$flag`, behind `convert_country(x, to = "flag")`, and accented
country names ("Curacao", "Cote d'Ivoire", "Reunion", "St. Barthelemy", "Sao
Tome & Principe", "Aland Islands") in `country_meta`, `world_tiles`,
`historical_codes` and `country_groups_tbl`. Every name in the curated
override table is plain ASCII by design, so name matching does not depend on
the locale.

## Notes

* Examples: of the 122 documented topics with an `\examples{}` block, 61 run
  unconditionally, 49 use `\donttest{}` and 13 use `\dontrun{}` (one uses
  both). Each `\dontrun{}` example needs a live web service (the World Bank,
  Our World in Data, Eurostat's GISCO, the CShapes download, or the DuckDB
  extension ggsql loads). No example needs the network to succeed: a failed
  fetch degrades to a warning and an empty result, as CRAN policy asks.
* Tests that need the network are skipped on CRAN, and the slowest tests carry
  `skip_on_cran()` so the CRAN-mode test step stays short; every CI leg sets
  `NOT_CRAN=true` and runs all of them.
* The persistent cache lives in `tools::R_user_dir("countryatlas", "cache")`
  with an expiry and a size cap, and under `tempdir()` whenever
  `_R_CHECK_PACKAGE_NAME_` is set, so a check writes nothing outside it.
