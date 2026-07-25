## R CMD check results

0 errors | 0 warnings | 1 note

* This is an update (1.0.0 -> 2.0.0). 2.0.0 is a planned major release: it
  integrates the `ggsql` 0.4.1 spatial API (all optional, in Suggests) and
  fixes several correctness bugs found by auditing 1.0.0 (quantile break
  computation, centroid de-duplication, label placement, the `plate_carree`
  CRS, override-only code conversion). The bug fixes change plot output for
  affected calls, hence the major version bump.

## Test environments

* local: R 4.4.1 on Linux
* GitHub Actions: ubuntu (devel, release, oldrel-1), macOS (release),
  windows (release)

## Notes

* All examples that touch the World Bank API or heavy optional spatial
  dependencies are wrapped in `\donttest{}` / `\dontrun{}`.
* Tests that require the network are skipped on CRAN and when the World Bank API
  is unreachable; the bundled `world_snapshot` dataset keeps the remaining tests
  offline and deterministic.
* Heavy spatial dependencies (`sf`, `rnaturalearth`, `cartogram`, `biscale`,
  `gganimate`, `leaflet`, `ggiraph`, `plotly`, `rmapshaper`,
  `ggsql`, `duckdb`) are in `Suggests` and gated with
  `rlang::check_installed()`; tests and vignette chunks that use them skip
  cleanly when they are absent.
