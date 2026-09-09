## Why this submission

3.0.0 is a major release: 46 new exports, two new datasets, and 26 documented
breaking changes. It takes the package from "join World Bank data to a map" to
"join anyone's data, to the map as it was in 1950, and say honestly what the
picture does and does not support" -- a registry of pluggable data sources, a
historical-geometry backend, spatial statistics, and a set of verbs whose
purpose is reporting what a map does *not* show.

Three of the breaking changes affect existing code and are the reason for the
major bump rather than 2.1.0:

* `world_map(projection = "mercator")` now draws a different -- and usable --
  map. The previous output was unusable, so this is a fix, but the picture does
  change.
* `morans_i()` returns two further columns, `n_excluded` and `excluded`. Code
  assuming a five-column result will see seven. The statistic is unchanged.
* `geom_country_labels()` takes `data` as its second argument, matching the
  `geom_*(mapping, data, ...)` convention. A call that passed `repel`
  positionally must now name it; named calls are unaffected.

Four more change behaviour without changing a signature: `world_tiles` places
171 of its 239 countries in a different cell (the placement scan reused cells
it had already claimed), `dispute_policy()` now returns the policy it replaced
rather than the one just set (R's setter convention), the `"coastline"` and
`"ocean"` geometries name their geometry column `geometry` rather than `x`, and
`gini()`/`theil()` warn where they used to return a bare `NA`.

The remaining eighteen are listed under **Breaking changes** in `NEWS.md`.

Two deprecations warn from this release: `wdj_overrides()` (use
`country_overrides()`; soft-deprecated since 2.0.0) and
`options(countryatlas.gdp_compat = TRUE)`.

`cachem` is new in `Imports`. It is an unconditional dependency of `memoise`,
which was already imported, so it adds nothing to install; it is declared
because the persistent cache now uses `cachem::cache_disk()` for the expiry and
size cap CRAN policy asks for (30 days, 50 MB, both user-adjustable). The
previous `memoise::cache_filesystem()` had neither, so the cache directory grew
without bound. `stats`, `utils`, `tools`, `grDevices` and `parallel` are also
now declared; they were already called with `::`.

`inst/CITATION` no longer uses `%||%`. That operator only entered base R in
4.4.0, and a CITATION file is evaluated by `readCitationFile()` outside the
package namespace, so `NAMESPACE`'s `importFrom(rlang, "%||%")` does not reach
it -- on the R (>= 4.1.0) this package declares, `citation("countryatlas")`
would have failed.

## R CMD check results

0 errors | 0 warnings | 1 note

The one note is `found 261 marked UTF-8 strings`, which appears on older R and
is intentional -- see "The marked-UTF-8 strings note" below.

Everything else `R CMD check --as-cran` reports on the maintainer's machine is
an artefact of that machine, not of the package: optional `Suggests` that
cannot be installed there (`duckdb`, `ggsql`, `gifski`, `magick`), no `qpdf`
or `tidy` binary, and "unable to verify current time". None of those arise on
CRAN's own check machines or on the GitHub Actions runners listed below.

## The `donttest` additional issue reported for 1.0.0 (resolved in 2.0.0)

*Retained for the record.* The 2.0.0 auto-check returned OK on
`r-devel-linux-x86_64-debian-special-donttest`, confirming this is fixed.

The auto-check flagged 1.0.0's `donttest` result: "checking for new files in
some other directories" found `~/.cache/R/countryatlas` and two entries in it.
1.0.0 cached World Bank responses in `tools::R_user_dir("countryatlas",
"cache")` unconditionally, and its `\donttest{}` examples fetch, so running
them wrote into the checking account's home.

2.0.0 fixes it. `wdj_cache_dir()` returns a path under `tempdir()` whenever
`_R_CHECK_PACKAGE_NAME_` is set, which `R CMD check` sets for the whole run and
its example, test and vignette subprocesses; real use still gets
`tools::R_user_dir()`. A test pins both branches.

Verified by reproducing the reported check rather than by inspection: `R CMD
check --as-cran --run-donttest` with `_R_CHECK_THINGS_IN_OTHER_DIRS_=true`, an
empty `HOME` and `XDG_CACHE_HOME`/`XDG_DATA_HOME`/`XDG_CONFIG_HOME` pointed
inside it, with the World Bank reachable so the examples really did fetch (the
`world_data` example took 6.3s). No `countryatlas` path appears anywhere in the
snapshot.

That run did surface a write from a suggested package rather than from
countryatlas: `interactive_map(engine = "ggiraph")` renders a `girafe()` widget,
and `gdtools` then installs 90 Liberation font files into
`tools::R_user_dir("gdtools", "data")`. 2.0.0 is the first version whose tests
render such a widget. `tests/testthat/setup-user-dirs.R` now redirects the R
user directories to the session temp directory for the duration of the test run,
so the tests still exercise the `ggiraph` engine without writing outside
`tempdir()`; re-running the same check confirms those 90 files are gone.

The only path that remains in that sandbox is `~/.cache/fontconfig` (5 entries),
and it is not ours to move: the system fontconfig library builds it the first
time R's cairo PNG device renders anything, which during a check happens in the
process that re-builds the vignettes. Any package whose vignettes draw a plot
creates it, and it shows up here only because the sandbox starts from an empty
`HOME` -- on a machine that has ever rendered a PNG the paths already exist and
are not new. It is reported for completeness, not as an outstanding issue.

* This is a major update (2.0.1 -> 3.0.0); see "Why this submission" above.
  For context, 2.0.0 was a planned major release: it added
  an optional bridge to `ggsql`'s `DRAW spatial` API and fixes several
  correctness bugs found by auditing 1.0.0 (quantile break computation,
  centroid de-duplication, label placement, the `plate_carree` CRS,
  override-only code conversion). The bug fixes change plot output for affected
  calls, hence the major version bump.

* On the `ggsql` bridge specifically, stated precisely as of 2026-08-20: the
  `DRAW spatial` layer and the `PROJECT TO` projections were added to the ggsql
  *engine* in 0.4.0/0.4.1 (posit-dev/ggsql, tagged 2026-06-22), but the ggsql
  **R package** (posit-dev/ggsql-r) is still at 0.3.3 -- its tags stop at
  v0.3.3, its development version is 0.3.3.9000, and it vendors engine 0.3.3.
  So the bridge is deliberately forward-looking: it targets a released engine
  feature that the R bindings have not shipped yet.
* Nothing in the package depends on it. `ggsql` is in `Suggests`; the gate is
  `rlang::check_installed("ggsql", version = "0.4.1")`, so
  `interactive_map(engine = "ggsql")` refuses with an actionable message rather
  than failing inside ggsql's SQL front end; `world_query()` is a
  dependency-free string builder that is fully tested; and every example that
  would execute a query is wrapped in `\dontrun{}`. The package checks,
  installs and runs completely without `ggsql` present at any version.

## Test environments

* local: R 4.4.1 on Linux (full `--as-cran`), plus the further configurations
  run there:
  * R 4.6.0, with every optional package absent and
    `_R_CHECK_DEPENDS_ONLY_=true` -- OK, 1 NOTE (no `tidy` binary). That
    installation's site library carries none of the Suggests, so this is the
    strictest of the configurations listed here.
  * R 4.1.0, the declared minimum in `Depends` -- OK, 1744 tests passing, with
    the vignettes built and `sf` available. The NOTEs are the Suggests that
    installation lacks (`rnaturalearth` among them) and the marked-UTF-8
    strings described below. Checked statically as well: nothing in the package
    uses a base function newer than 4.1, and `%||%`, which only entered base R
    in 4.4, is imported from `rlang`.
  * four locales, run because this package's behaviour is locale-sensitive and
    2.0.0 shipped without this axis being covered: `en_US.UTF-8`,
    `en_US.iso88591` (`session charset: ISO8859-1`, matching CRAN's Fedora
    flavours), `en_US.iso885915` and `C`. The `test-standardize.R` failure was
    only reachable outside a UTF-8 locale, so no number of UTF-8 runs could
    have found it.
  * `_R_CHECK_DEPENDS_ONLY_=true` (the `noSuggests` configuration, every
    optional package absent) -- OK
  * every URL in `DESCRIPTION`, the README, the vignettes and the help pages
    resolves (29 distinct URLs, all HTTP 200)
  * the stricter check flags, all OK: `_R_CHECK_LENGTH_1_LOGIC2_=abort`,
    `_R_CHECK_LENGTH_1_CONDITION_=abort`,
    `_R_CHECK_XREFS_NOTE_MISSING_PACKAGE_ANCHORS_=true`,
    `_R_CHECK_S3_METHODS_SHOW_POSSIBLE_ISSUES_=true`,
    `_R_CHECK_CODOC_VARIABLES_VIA_USAGE_=true`,
    `_R_CHECK_PACKAGES_USED_IGNORE_UNUSED_IMPORTS_=false`,
    `_R_CHECK_DOT_INTERNAL_=true`, `_R_CHECK_RD_VALIDATE_RD2HTML_=true`,
    `_R_CLASS_MATRIX_ARRAY_=true`
* GitHub Actions: ubuntu (devel, release, oldrel-1), macOS (release),
  windows (release)

## The marked-UTF-8 strings note

On older R (4.1.x) the check reports `Note: found 261 marked UTF-8 strings`.
These are intentional and all correctly *marked* as UTF-8 rather than left in
an unknown encoding: 249 of them are the flag emoji in `country_meta$flag`,
which back the package's `convert_country(x, to = "flag")` feature, and the
remaining 12 are accented country names ("Curacao", "Cote d'Ivoire",
"Reunion", "St. Barthelemy", "Sao Tome & Principe", "Aland Islands") in
`country_meta` / `world_tiles` / `historical_codes`. Stripping them would
remove the data users come to the package for. Every name in the curated
override table is plain ASCII by design, so name matching itself does not
depend on the locale; `?country_overrides` documents this.

## Notes

* Examples: of the 99 documented topics with an `\examples{}` block, 48 run
  unconditionally, 40 use `\donttest{}` and 13 use `\dontrun{}` (two topics use
  both). 30 of the 40 `\donttest{}` topics are guarded with
  `requireNamespace()` so they skip rather than fail when an optional package
  is absent; the other ten need no optional package -- `country_weights`,
  `gearys_c`, `getis_ord`, `local_morans`, `morans_i` and `spatial_lag` run off
  the bundled `country_meta` centroids, `gridded_cartogram` and `tile_map` off
  `world_tiles`, and `country_data` / `wdi_search` degrade without a
  connection.
* No example needs the network to succeed, verified by running the full check
  behind a blackhole proxy. `?world_data` and `?country_data` do call the World
  Bank, but a failed fetch degrades to a warning and a metadata-only frame
  rather than an error. `?wdi_search` searches `WDI`'s bundled indicator list
  and needs no connection at all. Everything else runs from the bundled
  `world_snapshot` / `world_tiles` data.
* Example timings on the maintainer's machine: about 63s for all 99 together
  under `--run-donttest`, well inside CRAN's per-example limit; the check step
  reports `checking examples ... [63s/67s] OK`.
* `\dontrun{}` is left on 13 topics, in each case because the code genuinely
  cannot be executed in a check -- the five source adapters and
  `add_indicator()` / `compare_sources()` / `fetch_indicator()` need a live
  provider, `historical_geometry()` / `nuts_geometry()` / `subnational_map()`
  need a `cshapes` or GISCO download, and:
  * `animate_world()`, and the `world_data()` variants of `globe_map()` -- need
    a live World Bank fetch.
  * `interactive_map()` -- returns an HTML widget.
  * `as_ggsql_source()` -- the function itself needs only `DBI` + `duckdb` (or
    `nanoarrow` for `format = "arrow"`), but its example goes on to execute the
    query, so it needs a DuckDB connection and `ggsql` as well.
  * `spin_globe()` -- renders 60 frames and writes a GIF via `gifski`/`magick`.
  * `clear_wdi_cache(disk = TRUE)` -- deletes files on disk; the safe
    in-session form of the call is a live example.

* Tests that require the network are skipped on CRAN and when the World Bank API
  is unreachable; the bundled `world_snapshot` dataset keeps the remaining tests
  offline and deterministic.
* Heavy spatial dependencies (`sf`, `rnaturalearth`, `cartogram`, `biscale`,
  `gganimate`, `leaflet`, `ggiraph`, `plotly`, `rmapshaper`,
  `ggsql`, `duckdb`) are in `Suggests` and gated with
  `rlang::check_installed()`; tests and vignette chunks that use them skip
  cleanly when they are absent.
