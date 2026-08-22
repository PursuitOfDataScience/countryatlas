# Regression tests for the pre-CRAN polish pass. Each block pins a defect that
# green tests and a clean R CMD check did not catch, because the failing path
# was only reachable with a bad column name or an unusual argument.

snap <- countryatlas::world_snapshot$countries

test_that("plotting verbs name a missing column instead of leaking a ggplot2 error", {
  skip_if_not_installed("maps")
  mapdf <- attach_geometry(snap, geometry = "polygon")
  expect_error(world_map(mapdf, not_a_column), class = "countryatlas_error")
  expect_error(world_map(mapdf, not_a_column), "not found in")
  expect_error(facet_map(mapdf, not_a_column, continent), class = "countryatlas_error")
  expect_error(tile_map(snap, not_a_column), class = "countryatlas_error")
  expect_error(bubble_map(snap, not_a_column), class = "countryatlas_error")
  expect_error(bubble_map(snap, population, color = not_a_column),
               class = "countryatlas_error")
  expect_error(spike_map(snap, not_a_column), class = "countryatlas_error")
  if (requireNamespace("mapproj", quietly = TRUE)) {
    expect_error(globe_map(snap, not_a_column, backend = "polygon"),
                 class = "countryatlas_error")
  }
  od <- data.frame(from = "China", to = "United States", value = 1)
  expect_error(flow_map(od, from, to, not_a_column), class = "countryatlas_error")
  expect_error(flow_map(od, nope, to), class = "countryatlas_error")
})

test_that("morans_i names a missing value column", {
  # Used to report "not enough bordering countries" -- a zero-row frame is what
  # a NULL column subset produces, so the real cause was hidden. need_pkg()
  # fires before the column check, so sf has to be present for this to be the
  # error we see.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  expect_error(morans_i(snap, not_a_column, n_perm = 0), "not found in")
})

test_that("audit_coverage rejects an indicator column that isn't there", {
  # Used to silently report n_missing = 0 / na_rate = NaN for it.
  expect_error(audit_coverage(snap, indicator = "not_a_column"),
               class = "countryatlas_error")
  expect_silent(audit_coverage(snap, indicator = "gdp_per_capita"))
})

test_that("a multi-element na_label warns but does not error the legend", {
  # There is one NA key, so discrete_na_labels() takes the first element -- that
  # tolerance is deliberate (a length-1 NA means "leave the default formatter
  # alone", and a length > 1 value must not reach a length-1 condition). It used
  # to happen in silence; now it says so, while title/legend, which have no such
  # contract, error like world_query()'s do.
  skip_if_not_installed("maps")
  mapdf <- attach_geometry(snap, geometry = "polygon")
  expect_warning(
    p <- world_map(mapdf, gdp_per_capita, style = "quantile",
                   na_label = c("No data", "ignored")),
    "labels one key")
  expect_s3_class(p, "ggplot")
  expect_no_error(ggplot2::ggplot_build(p))
  expect_error(world_map(mapdf, gdp_per_capita, title = c("a", "b")),
               "must be a single value")
  expect_error(world_map(mapdf, gdp_per_capita, legend = c("a", "b")),
               "must be a single value")
  # NULL / NA keep the default formatter.
  expect_no_error(ggplot2::ggplot_build(
    world_map(mapdf, gdp_per_capita, style = "quantile", na_label = NA)))
})

test_that("per_capita survives an all-NA year column", {
  # min()/max() of an empty vector gave start = Inf and a bogus WDI request.
  df <- data.frame(iso3c = c("USA", "CHN"), year = NA_integer_,
                   co2 = c(5e6, 1e7), pop = c(331e6, 1402e6))
  out <- per_capita(df, co2, pop)
  expect_true("co2_per_capita" %in% names(out))
  # Without an explicit pop the fetch is mocked, so no network is touched; the
  # point is that `start`/`end` are finite years, not Inf.
  seen <- NULL
  testthat::local_mocked_bindings(
    fetch_wdi = function(indicator, start, end, ...) {
      seen <<- c(start = start, end = end)
      tibble::tibble(iso3c = c("USA", "CHN"), year = NA_integer_,
                     .wdj_pop = c(331e6, 1402e6))
    }
  )
  out2 <- per_capita(df[, c("iso3c", "year", "co2")], co2)
  expect_true(all(is.finite(seen)))
  expect_true("co2_per_capita" %in% names(out2))
})

test_that("per_capita aborts cleanly on a partial population fetch", {
  # A fetch missing a join column used to die on a raw vctrs subscript error.
  df <- data.frame(iso3c = c("USA", "CHN"), year = 2020L, co2 = c(5e6, 1e7))
  testthat::local_mocked_bindings(
    fetch_wdi = function(...) {
      tibble::tibble(iso3c = c("USA", "CHN"), .wdj_pop = c(331e6, 1402e6))
    }
  )
  expect_error(per_capita(df, co2), class = "countryatlas_error")
  expect_error(per_capita(df, co2), "Could not fetch population")
})

test_that("theil returns NA rather than NaN when all weights are zero", {
  # is.na() is TRUE for NaN as well, so it cannot tell the fixed NA from the
  # NaN the bug produced -- assert the exact value.
  expect_identical(theil(c(1, 2, 3), weights = c(0, 0, 0)), NA_real_)
  expect_identical(gini(c(1, 2, 3), weights = c(0, 0, 0)), NA_real_)
})

test_that(".Rbuildignore excludes the session-local .claude directory", {
  # It is git-excluded, but R CMD build only reads .Rbuildignore, so without
  # this line the lock file shipped in the tarball ("hidden files" NOTE).
  skip_if_not(file.exists("../../.Rbuildignore"))
  expect_true(any(grepl("claude", readLines("../../.Rbuildignore"))))
})

test_that('style = "categorical" names the offending numeric column', {
  skip_if_not_installed("maps")
  mapdf <- attach_geometry(snap, geometry = "polygon")
  # ggplot2 used to raise "Continuous value supplied to a discrete scale" at
  # build time, naming neither the column nor the style.
  expect_error(world_map(mapdf, gdp_per_capita, style = "categorical"),
               class = "countryatlas_error")
  expect_error(world_map(mapdf, gdp_per_capita, style = "categorical"),
               "categorical")
  if (requireNamespace("mapproj", quietly = TRUE)) {
    expect_error(globe_map(snap, gdp_per_capita, backend = "polygon",
                           style = "categorical"),
                 class = "countryatlas_error")
  }
  # A discrete column is still fine.
  expect_no_error(ggplot2::ggplot_build(
    world_map(mapdf, continent, style = "categorical")))
})

test_that("bivariate_map does not leak biscale's missing-values warning", {
  skip_if_not_installed("sf")
  skip_if_not_installed("biscale")
  skip_if_not_installed("rnaturalearth")
  sfd <- attach_geometry(snap, geometry = "sf")
  expect_true(anyNA(sfd$gdp_per_capita) || anyNA(sfd$life_expectancy))
  expect_no_warning(bivariate_map(sfd, gdp_per_capita, life_expectancy))
})

test_that("region accepts ISO codes in any case", {
  # Lowercase used to half-resolve: countrycode's case-insensitive name regex
  # matched "usa" but not "can", so region = c("usa", "can") silently dropped
  # Canada instead of subsetting to both.
  rr <- countryatlas:::resolve_region
  expect_equal(rr(c("usa", "can")), c("USA", "CAN"))
  expect_equal(rr(c("Usa", "cAn")), c("USA", "CAN"))
  expect_equal(rr(c("USA", "CAN")), c("USA", "CAN"))
  expect_equal(rr(c(" usa ", "can")), c("USA", "CAN"))
  # An all-uppercase unknown code is still taken at face value (an empty
  # subset), not reinterpreted as a country name.
  expect_equal(rr("XYZ"), "XYZ")
  # Names, continents, groups and bounding boxes are untouched.
  expect_equal(rr(c("United States", "Canada")), c("USA", "CAN"))
  expect_gt(length(rr("Africa")), 40L)
  expect_equal(length(rr("EU")), 27L)
  expect_s3_class(rr(c(-20, 30, 40, 70)), "wdj_bbox")
  expect_null(rr(NULL))
})

test_that("region subsetting gives the same geometry for either case", {
  skip_if_not_installed("maps")
  lower <- world_geometry("countries", geometry = "polygon",
                          region = c("usa", "can"))
  upper <- world_geometry("countries", geometry = "polygon",
                          region = c("USA", "CAN"))
  expect_equal(nrow(lower), nrow(upper))
  expect_gt(nrow(lower), 0L)
  expect_setequal(unique(lower$iso3c), c("USA", "CAN"))
})

test_that("country_codes rejects an unknown column instead of dropping it", {
  # A typo used to return a table quietly missing the requested column.
  expect_error(country_codes("curency"), class = "countryatlas_error")
  expect_error(country_codes(c("iso2c", "curency")), "Unknown column")
  # Friendly shortcuts and raw codelist column names both still work.
  expect_true(all(c("country", "iso3c", "iso2c", "currency") %in%
                    names(country_codes(c("iso2c", "currency")))))
  # A raw codelist column is accepted as input but comes back under its
  # friendly name, which is what country_codes() documents.
  expect_true("currency" %in% names(country_codes("iso4217c")))
  expect_gt(ncol(country_codes()), 5L)
})

test_that("wdj_known_iso3c is the single source of truth for country codes", {
  known <- countryatlas:::wdj_known_iso3c()
  expect_true("XKX" %in% known)          # Kosovo has no codelist row
  expect_true(all(c("USA", "FRA", "JPN") %in% known))
  expect_false(anyNA(known))
  expect_equal(anyDuplicated(known), 0L)
  # The name matcher and region resolution must agree with it.
  expect_false(anyNA(countryatlas:::wdj_to_iso3c(known, origin = "iso3c")))
  expect_true(is.na(countryatlas:::wdj_to_iso3c("ZZZ", origin = "iso3c")))
})

test_that("wdj_cache_dir keeps R CMD check out of the user's file space", {
  # R CMD check runs the \donttest{} examples, which fetch, so an unguarded
  # default left World Bank responses in the checking account's persistent
  # cache. Real use still gets tools::R_user_dir().
  old_opt <- options(countryatlas.cache_dir = NULL)
  old_env <- Sys.getenv("_R_CHECK_PACKAGE_NAME_", unset = NA)
  on.exit({
    options(old_opt)
    if (is.na(old_env)) {
      Sys.unsetenv("_R_CHECK_PACKAGE_NAME_")
    } else {
      Sys.setenv("_R_CHECK_PACKAGE_NAME_" = old_env)
    }
  }, add = TRUE)
  user_dir <- tools::R_user_dir("countryatlas", "cache")

  Sys.setenv("_R_CHECK_PACKAGE_NAME_" = "countryatlas")
  under_check <- countryatlas:::wdj_cache_dir()
  expect_false(identical(under_check, user_dir))
  expect_true(startsWith(under_check, tempdir()))

  Sys.unsetenv("_R_CHECK_PACKAGE_NAME_")
  expect_equal(countryatlas:::wdj_cache_dir(), user_dir)

  # An explicit option wins over both.
  mine <- file.path(tempdir(), "explicit-cache")
  options(countryatlas.cache_dir = mine)
  expect_equal(countryatlas:::wdj_cache_dir(), mine)
  Sys.setenv("_R_CHECK_PACKAGE_NAME_" = "countryatlas")
  expect_equal(countryatlas:::wdj_cache_dir(), mine)
})

test_that("the ggsql engine states the version it needs", {
  # `DRAW spatial` landed in ggsql 0.4.1; CRAN currently ships 0.3.3, which
  # would accept the call and then reject the clause inside its own SQL front
  # end. The gate must name the version, not just the package.
  skip_if(requireNamespace("ggsql", quietly = TRUE) &&
            utils::packageVersion("ggsql") >= "0.4.1")
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  # Must be an *sf* frame: the sf check now runs ahead of the package gates, so a
  # country-level frame is (correctly) rejected for its shape before ggsql is
  # ever consulted.
  sfd <- attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf")
  err <- tryCatch(interactive_map(sfd, gdp_per_capita, engine = "ggsql"),
                  condition = function(e) conditionMessage(e))
  expect_match(err, "ggsql", fixed = TRUE)
  expect_match(err, "0.4.1", fixed = TRUE)
})

test_that("world_query stays a dependency-free string builder", {
  # It must not gate on ggsql at all -- only executing the query does.
  q <- world_query(gdp_per_capita, projection = "equal_earth",
                   palette = "magma", transform = "log10", title = "It's a test")
  expect_s3_class(q, "ggsql_query")
  expect_match(as.character(q), "DRAW spatial", fixed = TRUE)
  expect_match(as.character(q), "PROJECT TO equal_earth", fixed = TRUE)
  expect_match(as.character(q), "SCALE fill TO magma VIA log10", fixed = TRUE)
  # A quote in the title is SQL-escaped, not injected.
  expect_match(as.character(q), "'It''s a test'", fixed = TRUE)
  # Omitting the optional clauses omits the lines.
  bare <- world_query(x, projection = NULL, palette = NULL)
  expect_false(grepl("PROJECT TO", bare, fixed = TRUE))
  expect_false(grepl("SCALE", bare, fixed = TRUE))
})

test_that("quietly_sf swallows console output but returns the value", {
  # Most sf/s2 diagnostics are ordinary message() conditions; a few GDAL/GEOS
  # ones are written straight to stderr from C. quietly_sf() has to stop both,
  # so it muffles the conditions *and* redirects the stream.
  skip_if(sink.number(type = "message") != 2L,
          "a message sink is already active")
  f <- tempfile()
  con <- file(f, "w")
  sink(con, type = "message")
  got <- tryCatch(countryatlas:::quietly_sf({ message("noise"); 42 }),
                  finally = { sink(type = "message"); close(con) })
  expect_equal(got, 42)
  expect_length(readLines(f, warn = FALSE), 0L)

  # The condition must not escape to the caller's handlers either.
  seen <- 0L
  withCallingHandlers(
    expect_equal(countryatlas:::quietly_sf({ message("noise"); 7 }), 7),
    message = function(m) {
      seen <<- seen + 1L
      invokeRestart("muffleMessage")
    }
  )
  expect_identical(seen, 0L)
})

test_that("the sf happy path prints nothing to the console", {
  # st_break_antimeridian() runs on every sf call and emits three notices
  # ("Spherical geometry (s2) switched off/on", plus st_intersection's planar
  # note). Unsilenced, a plain attach_geometry(geometry = "sf") printed them.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if(sink.number(type = "message") != 2L,
          "a message sink is already active")
  snap <- countryatlas::world_snapshot$countries

  stderr_lines <- function(expr) {
    f <- tempfile()
    con <- file(f, "w")
    sink(con, type = "message")
    on.exit({
      if (sink.number(type = "message") != 2L) sink(type = "message")
      close(con)
    }, add = TRUE)
    try(force(expr), silent = TRUE)
    if (sink.number(type = "message") != 2L) sink(type = "message")
    length(readLines(f, warn = FALSE))
  }

  expect_equal(stderr_lines(attach_geometry(snap, geometry = "sf")), 0L)
  expect_equal(stderr_lines(world_geometry("countries", geometry = "sf")), 0L)
  expect_equal(stderr_lines(country_borders(region = "Europe")), 0L)
  expect_equal(stderr_lines(locate_country(lon = 2.35, lat = 48.85)), 0L)
})

test_that("the sf happy path leaks no message conditions to the caller", {
  # A clean console is not enough: redirecting the message *stream* leaves the
  # underlying message() conditions travelling to whatever handler the caller
  # has installed, so purrr::quietly(), capture_messages() or a plain
  # withCallingHandlers() around any sf-backed verb still saw sf's internal
  # chatter. Count conditions, not console lines -- they are separate channels.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  snap <- countryatlas::world_snapshot$countries

  n_conditions <- function(expr) {
    n <- 0L
    withCallingHandlers(
      try(force(expr), silent = TRUE),
      message = function(m) {
        n <<- n + 1L
        invokeRestart("muffleMessage")
      }
    )
    n
  }

  expect_identical(n_conditions(attach_geometry(snap, geometry = "sf")), 0L)
  expect_identical(n_conditions(country_borders(region = "Europe")), 0L)
  expect_identical(n_conditions(locate_country(lon = 2.35, lat = 48.85)), 0L)
  expect_identical(n_conditions(neighbors("France")), 0L)
})

test_that("the network-backed examples degrade instead of failing offline", {
  # CRAN policy: examples must not fail when a web resource is unavailable, and
  # world_data()/country_data() are \donttest{} examples that run under
  # --run-donttest. With every WDI call erroring they must warn and still return
  # a usable table, built from the country spine.
  testthat::local_mocked_bindings(
    fetch_one_indicator = function(...) stop("Could not resolve host")
  )
  expect_warning(cd <- country_data(2020, c(co2 = "EN.GHG.CO2.MT.CE.AR5")),
                 class = "countryatlas_warning")
  expect_s3_class(cd, "tbl_df")
  expect_gt(nrow(cd), 100L)
  expect_true(all(c("iso3c", "country") %in% names(cd)))

  expect_warning(wd <- world_data(2020, geometry = "none"),
                 class = "countryatlas_warning")
  expect_s3_class(wd, "tbl_df")
  expect_gt(nrow(wd), 100L)
})

test_that("no runnable example calls per_capita without an explicit pop", {
  # That path deliberately errors when the World Bank is unreachable, so it must
  # not appear in an example that R CMD check executes.
  skip_if_not(dir.exists("../../man"), "man/ not present (installed package)")
  offenders <- character()
  for (f in Sys.glob("../../man/*.Rd")) {
    out <- tempfile(fileext = ".R")
    tools::Rd2ex(f, out = out, commentDontrun = TRUE, commentDonttest = FALSE)
    if (!file.exists(out)) next
    src <- paste(readLines(out, warn = FALSE), collapse = "\n")
    calls <- regmatches(src, gregexpr("per_capita\\([^)]*\\)", src))[[1]]
    for (cl in calls) {
      if (length(strsplit(cl, ",")[[1]]) < 3L) offenders <- c(offenders, basename(f))
    }
  }
  expect_length(offenders, 0L)
})

# `tooltip =` was documented but silently ignored by every engine before 2.0.0.
# The original tests only asserted the returned object's class, which passes
# whether the argument is honoured or dropped -- mutation testing found the fix
# unprotected. Capture what each engine is actually handed. Split per engine and
# skipped explicitly: as one test with both engines inside requireNamespace()
# blocks, it ran zero expectations and still reported green wherever the engines
# were absent.

test_that("interactive_map's ggiraph engine honours tooltip", {
  skip_if_not_installed("maps")
  skip_if_not_installed("ggiraph")
  snap <- countryatlas::world_snapshot$countries
  mapdf <- attach_geometry(snap, geometry = "polygon")
  # girafe() wraps the ggplot; hand it back so the layer mapping is readable.
  testthat::local_mocked_bindings(girafe = function(ggobj, ...) ggobj,
                                  .package = "ggiraph")
  tip <- function(p) rlang::as_label(p$layers[[1]]$mapping$tooltip)
  expect_equal(tip(interactive_map(mapdf, gdp_per_capita, engine = "ggiraph")),
               "gdp_per_capita")            # defaults to fill
  expect_equal(tip(interactive_map(mapdf, gdp_per_capita, tooltip = country,
                                   engine = "ggiraph")),
               "country")                   # honours the argument
})

test_that("interactive_map's leaflet engine honours tooltip", {
  skip_if_not_installed("maps")
  skip_if_not_installed("leaflet")
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  seen <- NULL
  # The label is an unevaluated formula, so read the column name out of the
  # environment it carries rather than deparsing it.
  testthat::local_mocked_bindings(
    addPolygons = function(map, ..., label = NULL) {
      seen <<- get("tooltip_name", envir = environment(label))
      map
    },
    .package = "leaflet"
  )
  invisible(interactive_map(snap, gdp_per_capita, engine = "leaflet"))
  expect_equal(seen, "gdp_per_capita")
  invisible(interactive_map(snap, gdp_per_capita, tooltip = country,
                            engine = "leaflet"))
  expect_equal(seen, "country")
})

test_that("country_borders' column order is what the graph recipe assumes", {
  # ?country_borders tells users to hand igraph only the two code columns,
  # because graph_from_data_frame() treats the FIRST TWO columns as the edge
  # endpoints -- and here columns 1 and 2 both describe endpoint A, so passing
  # the whole tibble builds edges from each country's code to its own name.
  # igraph is not a dependency, so assert the structural fact the advice rests
  # on rather than running it.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  b <- country_borders(region = "Europe")
  expect_equal(names(b), c("iso3c_a", "country_a", "iso3c_b", "country_b"))
  # Columns 1 and 2 are the same endpoint, not two endpoints.
  expect_equal(b$country_a,
               convert_country(b$iso3c_a, to = "country", from = "iso3c",
                               warn = FALSE))
  expect_equal(b$country_b,
               convert_country(b$iso3c_b, to = "country", from = "iso3c",
                               warn = FALSE))
  # The subset the docs recommend is a well-formed edge list.
  edges <- b[, c("iso3c_a", "iso3c_b")]
  expect_equal(ncol(edges), 2L)
  expect_true(all(nchar(unlist(edges)) == 3L))
  expect_false(any(edges$iso3c_a == edges$iso3c_b))
})

test_that('scale = "large" names the non-CRAN package it needs', {
  # The 10m Natural Earth data lives in rnaturalearthhires, which is not on
  # CRAN and not in Suggests. Ungated, rnaturalearth reacts by trying to
  # install it into the user's library and then failing obscurely.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if(requireNamespace("rnaturalearthhires", quietly = TRUE),
          "rnaturalearthhires is installed, so the gate does not fire")
  expect_error(world_geometry("countries", geometry = "sf", scale = "large"),
               class = "countryatlas_error")
  expect_error(world_geometry("countries", geometry = "sf", scale = "large"),
               "rnaturalearthhires")
  # The two CRAN-available scales are unaffected.
  expect_s3_class(world_geometry("countries", geometry = "sf", scale = "small"), "sf")
  expect_s3_class(world_geometry("countries", geometry = "sf", scale = "medium"), "sf")
})

test_that("geom_country_labels says so when it cannot repel", {
  # The one degraded optional backend the package did not announce: asking for
  # repel = TRUE without ggrepel silently produced plain labels, while classInt,
  # gganimate and rmapshaper all report their fallbacks.
  testthat::local_mocked_bindings(
    has_pkg = function(pkg) {
      if (identical(pkg, "ggrepel")) FALSE
      else isTRUE(requireNamespace(pkg, quietly = TRUE))
    }
  )
  # Said once, not on every call (repel = TRUE is the default).
  expect_message(l1 <- geom_country_labels(repel = TRUE), "ggrepel")
  expect_s3_class(l1$geom, "GeomText")
  expect_no_message(geom_country_labels(repel = TRUE))
  # Nothing to report if plain labels were what was asked for.
  expect_no_message(geom_country_labels(repel = FALSE))
})

test_that("geom_country_labels repels when ggrepel is available", {
  skip_if_not_installed("ggrepel")
  expect_no_message(l <- geom_country_labels(repel = TRUE))
  expect_s3_class(l$geom, "GeomTextRepel")
  expect_s3_class(geom_country_labels(repel = FALSE)$geom, "GeomText")
})

test_that("classInt and the base fallback agree on quantile breaks", {
  # A result that changes with which optional package is installed is a bug;
  # for the quantile style these two paths must produce identical breaks.
  x <- countryatlas::world_snapshot$countries$gdp_per_capita
  x <- x[is.finite(x)]
  with_ci <- countryatlas:::compute_breaks(x, "quantile", 5)
  testthat::local_mocked_bindings(
    has_pkg = function(pkg) {
      if (identical(pkg, "classInt")) FALSE
      else isTRUE(requireNamespace(pkg, quietly = TRUE))
    }
  )
  expect_equal(countryatlas:::compute_breaks(x, "quantile", 5), with_ci)
})

# dplyr joins default to na_matches = "na", i.e. an NA key matches another NA
# key. Natural Earth carries Somaliland as a polygon with no ISO code, so any
# unmatched country in the caller's data joined onto it: the value was painted
# on a real country, and with two or more unmatched rows the join fanned out
# many-to-many. country_join()/country_join_all() already passed
# na_matches = "never"; every other country-keyed join now does too.

test_that("an NA country key never joins to geometry", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("rnaturalearthdata")
  geom <- world_geometry("countries", geometry = "sf")
  # The premise of the bug: the sf source really does carry a keyless feature.
  skip_if(!anyNA(geom$iso3c), "sf source has no keyless feature to mis-join to")

  df <- data.frame(iso3c = c("USA", NA, NA), value = c(1, 99, 77))
  out <- attach_geometry(df, geometry = "sf")
  expect_false(any(out$value %in% c(99, 77)))       # not painted on a country
  expect_equal(nrow(out), nrow(geom))               # and no many-to-many fan-out
  # The keyless feature is still drawn, just with no data attached.
  expect_true(all(is.na(out$value[is.na(out$iso3c)])))
  expect_equal(out$value[!is.na(out$iso3c) & out$iso3c == "USA"][1], 1)
})

test_that("an NA country key never borrows a centroid", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  d <- data.frame(iso3c = c("USA", NA), population = c(10, 99))
  b <- ggplot2::ggplot_build(bubble_map(d, population, backend = "sf"))
  pts <- b$data[[length(b$data)]]
  expect_equal(sum(!is.na(pts$size)), 1L)           # USA only
})

test_that("every country-keyed join refuses to match NA to NA", {
  # A source-level invariant: relying on "the polygon backend happens to have no
  # NA keys today" is an upstream data property, not something we control. Read
  # the installed namespace rather than the source tree so this also runs under
  # R CMD check, where R/ is not next to the tests.
  ns <- asNamespace("countryatlas")
  fns <- Filter(is.function, mget(ls(ns, all.names = TRUE), envir = ns,
                                 ifnotfound = list(NULL)))
  src <- vapply(fns, function(f) paste(deparse(f), collapse = " "), character(1))
  rx <- "(left|inner|full|right|semi|anti)_join\\((?:[^()]|\\([^()]*\\))*\\)"
  calls <- unlist(regmatches(src, gregexpr(rx, src, perl = TRUE)))
  keyed <- grep("iso3c|by = by|_iso", calls, value = TRUE)
  expect_gt(length(keyed), 10L)                     # the scan really found them
  # unname(): `keyed` inherits names from the namespace scan, and a named
  # character(0) is not expect_equal() to a bare one.
  expect_equal(unname(grep("na_matches", keyed, value = TRUE, invert = TRUE)),
               character(0))
})

# Numbers that cross into a machine-readable string must not depend on the
# user's formatting options. options(OutDec = ",") is ordinary in comma-decimal
# locales and turned every PROJ string into "+lat_0=12,5", which PROJ rejects --
# surfacing as sf's opaque "crs not found: is it missing?", i.e. no projected
# map at all. options(scipen = -9) rendered EPSG 4326 as "4.326e+03" (an NA
# CRS, later "st_crs(x) == st_crs(y) is not TRUE") and Natural Earth's scale 110
# as "1.1e+02" ("'countries1.1e+02' is not an exported object").

test_that("fmt_num ignores OutDec and scipen", {
  f <- countryatlas:::fmt_num
  vals <- c(0, 20, -90, 48.9, 100, 12.5, -0.5, 359.9)
  want <- f(vals)
  old <- options(OutDec = ",", scipen = -9)
  on.exit(options(old), add = TRUE)
  expect_identical(f(vals), want)
  expect_false(any(grepl(",", want, fixed = TRUE)))
  expect_false(any(grepl("e", want, fixed = TRUE)))
})

test_that("PROJ strings always use a dot decimal", {
  old <- options(OutDec = ",", scipen = -9)
  on.exit(options(old), add = TRUE)
  s <- countryatlas:::wdj_crs("orthographic", recenter = 48.9, lat0 = 12.5)
  expect_match(s, "+lat_0=12.5", fixed = TRUE)
  expect_match(s, "+lon_0=48.9", fixed = TRUE)
  expect_false(grepl(",", s, fixed = TRUE))
  expect_false(grepl("e+", s, fixed = TRUE))
})

test_that("EPSG codes and Natural Earth scales are integer literals", {
  # A double is what breaks: sf and rnaturalearth both paste the number into a
  # name, and only doubles are subject to scipen.
  expect_type(countryatlas:::ne_scale("small"), "integer")
  expect_identical(countryatlas:::ne_scale("small"), 110L)
  expect_identical(countryatlas:::ne_scale("medium"), 50L)
  expect_identical(countryatlas:::ne_scale("large"), 10L)
  src <- vapply(list(countryatlas:::get_world_sf, countryatlas::locate_country,
                     countryatlas::interactive_map),
                function(f) paste(deparse(f), collapse = " "), character(1))
  expect_false(any(grepl("4326[^L]", src)))
})

test_that("the sf paths survive hostile formatting options", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("rnaturalearthdata")
  snap <- countryatlas::world_snapshot$countries
  for (opt in list(list(OutDec = ","), list(scipen = -9),
                   list(OutDec = ",", scipen = -9))) {
    old <- options(opt)
    expect_gt(nrow(suppressWarnings(attach_geometry(snap, geometry = "sf"))), 0L)
    expect_gt(nrow(suppressWarnings(
      world_geometry("countries", geometry = "sf",
                     projection = "orthographic", recenter = 48.9))), 0L)
    expect_gt(nrow(suppressWarnings(world_geometry("graticule",
                                                   geometry = "sf"))), 0L)
    expect_equal(nrow(suppressWarnings(locate_country(2.3, 48.9))), 1L)
    options(old)
  }
})

test_that("with_c_numbers restores the caller's options", {
  old <- suppressWarnings(options(OutDec = ",", scipen = -9))
  on.exit(options(old), add = TRUE)
  stored_scipen <- getOption("scipen")
  seen <- countryatlas:::with_c_numbers(
    c(dec = getOption("OutDec"), sci = as.character(getOption("scipen"))))
  expect_equal(unname(seen[["dec"]]), ".")      # normalised inside
  expect_equal(unname(seen[["sci"]]), "0")
  expect_equal(getOption("OutDec"), ",")        # and put back after
  # Compare against what R actually stored, not the literal passed in: R >= 4.6
  # clamps scipen to -9 and warns, so a hard-coded expectation fails there while
  # the restore itself is faithful.
  expect_equal(getOption("scipen"), stored_scipen)
  # Restored even when the wrapped call fails.
  expect_error(countryatlas:::with_c_numbers(stop("boom")), "boom")
  expect_equal(getOption("OutDec"), ",")
})

test_that("every option the package reads is documented on the package page", {
  # Two of the three were advertised only in NEWS.md -- a changelog, not
  # reference documentation -- so a reader of ?countryatlas had no way to find
  # them. wdj_workers()'s own comment even said "the option is advertised in
  # NEWS", which is how a bad value became reachable in the first place.
  skip_if_no_source_tree()
  src <- unlist(lapply(list.files("../../R", pattern = "[.]R$", full.names = TRUE),
                       readLines, warn = FALSE))
  # Read only from getOption() calls: a bare mention in a comment or a filename
  # like countryatlas.Rmd would otherwise register as an option.
  calls <- unlist(regmatches(
    src, gregexpr('getOption\\("countryatlas\\.[a-z_]+"', src)))
  opts <- unique(sub('^getOption\\("', "", sub('"$', "", calls)))
  expect_gt(length(opts), 0L)
  rd <- paste(readLines("../../man/countryatlas-package.Rd", warn = FALSE),
              collapse = "\n")
  for (o in opts) {
    expect_true(grepl(o, rd, fixed = TRUE),
                info = paste(o, "is read by the package but not documented in",
                             "?countryatlas"))
  }
})

test_that("options(countryatlas.workers) is validated", {
  # A bad value used to reach mclapply(mc.cores = NA) and surface as "missing
  # value where TRUE/FALSE needed" from deep inside the fetch.
  # Base R option save/restore rather than the withr helper: withr is not a
  # declared dependency, and a namespaced call to it from a test trips R CMD
  # check's "'::' import not declared" warning even though testthat pulls it in.
  with_workers <- function(value, code) {
    old <- options(countryatlas.workers = value)
    on.exit(options(old), add = TRUE)
    force(code)
  }
  for (bad in list("many", NA, c(1, 2), Inf)) {
    with_workers(bad, expect_error(countryatlas:::wdj_workers(8),
                                   "single finite number",
                                   info = paste(deparse(bad), collapse = "")))
  }
  # Valid values, including a numeric string, which has always been accepted.
  for (v in list(1, 4, "2")) {
    with_workers(v, expect_identical(countryatlas:::wdj_workers(8), as.integer(v)))
  }
  # Below one is clamped rather than rejected -- the documented contract.
  with_workers(0, expect_identical(countryatlas:::wdj_workers(8), 1L))
  with_workers(-2, expect_identical(countryatlas:::wdj_workers(8), 1L))
  # n_tasks still caps the result.
  with_workers(8, expect_identical(countryatlas:::wdj_workers(3), 3L))
  # And the option is restored afterwards.
  expect_null(getOption("countryatlas.workers"))
})

test_that("no verb leaves the caller's global state modified", {
  # CRAN policy: a package must not change the user's options, working directory
  # or other global settings. The sf backend genuinely has to toggle
  # sf::sf_use_s2() (Natural Earth rings are invalid as spherical geometry) and
  # with_c_numbers() has to normalise OutDec/scipen for two upstream bugs, so
  # each is paired with an on.exit() restore -- which a later edit could drop
  # without any other test noticing. Error paths matter as much as happy ones.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  snap <- countryatlas::world_snapshot$countries
  sfd <- attach_geometry(snap, geometry = "sf")

  state <- function() {
    list(opts = options()[c("OutDec", "scipen", "digits", "warn")],
         s2 = sf::sf_use_s2(), wd = getwd())
  }
  unchanged_by <- function(expr) {
    before <- state()
    invisible(tryCatch(suppressWarnings(suppressMessages(force(expr))),
                       error = function(e) NULL))
    identical(before, state())
  }

  # Happy paths, including every sf_use_s2() toggle site and with_c_numbers().
  expect_true(unchanged_by(world_geometry("countries", geometry = "sf",
                                          region = c(-10, 30, 40, 48))))
  expect_true(unchanged_by(country_borders()))
  expect_true(unchanged_by(locate_country(lon = 2.3, lat = 48.8)))
  expect_true(unchanged_by(simplify_geometry(sfd, keep = 0.3)))
  expect_true(unchanged_by(world_geometry("graticule", geometry = "sf")))
  expect_true(unchanged_by(ggplot2::ggplot_build(world_map(sfd, gdp_per_capita))))

  # Error paths: on.exit() must run even when the call aborts.
  expect_true(unchanged_by(world_geometry("ocean", geometry = "sf",
                                          projection = "orthographic")))
  expect_true(unchanged_by(simplify_geometry(sfd, keep = 0)))
  expect_true(unchanged_by(locate_country(lon = 1, lat = 1, tolerance_km = -1)))
  expect_true(unchanged_by(world_map(sfd, gdp_per_capita, palette = c("a", "b"))))
})

test_that("morans_i touches the RNG only when it permutes", {
  # Consuming random numbers is correct for a permutation test -- what would be
  # wrong is calling set.seed() (the package never does) or spending randomness
  # when none was asked for. n_perm = 0 is the deterministic path.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  sfd <- attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf")

  set.seed(1)
  before <- .Random.seed
  invisible(morans_i(sfd, gdp_per_capita, n_perm = 0))
  expect_identical(before, .Random.seed)

  set.seed(1)
  before <- .Random.seed
  invisible(morans_i(sfd, gdp_per_capita, n_perm = 20))
  expect_false(identical(before, .Random.seed))

  # And a seeded run reproduces, which is what the permutation p-value promises.
  set.seed(42); a <- morans_i(sfd, gdp_per_capita, n_perm = 99)
  set.seed(42); b <- morans_i(sfd, gdp_per_capita, n_perm = 99)
  expect_identical(a$p_value, b$p_value)
})

test_that("a correct call to any verb is completely silent", {
  # Six warning sites went in during the pre-CRAN work (warn_overwrite, the
  # share_of_world grouping note, flow_map's dropped flows, na_label, the
  # latest/panel conflict, the ggrepel fallback). None of them may fire on a
  # correct call: users run with options(warn = 2) in CI, where a stray warning
  # becomes an error.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  sfd <- attach_geometry(snap, geometry = "sf")
  poly <- attach_geometry(snap, geometry = "polygon")
  pan <- tibble::tibble(iso3c = rep(c("USA", "FRA", "CHN", "IND"), each = 3),
                        year = rep(2000:2002, 4),
                        v = c(1, 2, 3, 10, 20, 30, 100, 150, 200, 5, 6, 7),
                        population = 1e6)

  expect_silent(force(world_map(sfd, gdp_per_capita)))
  expect_silent(force(world_map(poly, gdp_per_capita, style = "quantile")))
  expect_silent(force(bubble_map(sfd, population, backend = "sf")))
  expect_silent(force(spike_map(poly, population)))
  expect_silent(force(tile_map(snap, gdp_per_capita)))
  expect_silent(force(per_capita(snap, gdp_per_capita, pop = population)))
  expect_silent(force(share_of_world(snap, population)))
  expect_silent(force(rank_countries(snap, gdp_per_capita)))
  expect_silent(force(aggregate_regions(snap, population, by = "continent")))
  expect_silent(force(growth_rate(pan, v)))
  expect_silent(force(index_to(pan, v, base_year = 2000)))
  expect_silent(force(lag_by_country(pan, v)))
  expect_silent(force(diff_by_country(pan, v)))
  expect_silent(force(complete_years(pan)))
  expect_silent(force(correlate_indicators(snap)))
  expect_silent(force(gini(snap$population)))
  expect_silent(force(theil(snap$population)))
  expect_silent(force(flow_map(tibble::tibble(f = "France", t = "Japan"), f, t)))
  expect_silent(force(morans_i(sfd, gdp_per_capita, n_perm = 0)))
  expect_silent(force(attach_geometry(snap, geometry = "sf")))
  expect_silent(force(neighbors("France")))
  expect_silent(force(locate_country(lon = 2.3, lat = 48.8)))
  expect_silent(force(dissolve_country("USSR")))
  expect_silent(force(standardize_country(tibble::tibble(c = "France"), "c")))
})

test_that("the verbs survive hostile number-formatting options", {
  # A comma decimal mark is ordinary in much of the world, and fmt_num() exists
  # so a PROJ string never depends on it. (A *negative* scipen is not covered:
  # it breaks sf and ggplot2 on their own -- st_crs(paste0("EPSG:", 4326))
  # becomes "EPSG:4.326e+03" -- with this package not even loaded.)
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  snap <- countryatlas::world_snapshot$countries
  sfd <- attach_geometry(snap, geometry = "sf")
  with_opts <- function(o, code) {
    old <- options(o)
    on.exit(options(old), add = TRUE)
    force(code)
  }
  # expect_no_error() takes no `info`, so report the option and the message.
  survives <- function(o, code) {
    tryCatch({
      with_opts(o, force(code))
      TRUE
    }, error = function(e) conditionMessage(e))
  }
  # stringsAsFactors is deliberately absent: R deprecated it, so merely setting
  # it warns, and it no longer affects data.frame() on the versions we support.
  for (o in list(list(OutDec = ","), list(scipen = 0L), list(digits = 3L),
                 list(warn = 2L), list(useFancyQuotes = FALSE))) {
    lbl <- paste(names(o), unlist(o), sep = "=")
    expect_true(isTRUE(survives(o, ggplot2::ggplot_build(
      world_map(sfd, gdp_per_capita)))), info = lbl)
    expect_true(isTRUE(survives(o, world_geometry("countries",
                                                 geometry = "sf"))), info = lbl)
    expect_true(isTRUE(survives(o, locate_country(lon = 2.3, lat = 48.8))),
                info = lbl)
    expect_true(isTRUE(survives(o, convert_country("France", to = "iso3c"))),
                info = lbl)
    expect_true(isTRUE(survives(o, world_query(gdp_per_capita))), info = lbl)
  }
})

test_that("globalVariables() declares nothing it does not need", {
  # The list had grown to 29 names; emptying it and reading what R CMD check
  # reported showed only 7 were load-bearing. The rest were covered by the
  # `.data$x` idiom, which needs no declaration. A stale entry silences the "no
  # visible binding" NOTE for a *new* bare use of the same name -- the warning
  # that would otherwise catch a typo -- so keep the list minimal.
  skip_if_no_source_tree()
  files <- list.files("../../R", pattern = "[.]R$", full.names = TRUE)

  # Read the declared names by parsing R, not by regexing text.
  declared <- character(0)
  for (f in files) {
    for (e in parse(f, keep.source = FALSE)) {
      if (is.call(e) &&
          identical(deparse(e[[1]]), "utils::globalVariables")) {
        declared <- c(declared, eval(e[[2]]))
      }
    }
  }
  expect_gt(length(declared), 0L)

  # Every declared name must appear as a bare symbol somewhere -- not as a
  # string, not `$`-subscripted. Walk the parse trees and collect real symbols.
  syms <- character(0)
  collect <- function(x) {
    if (is.name(x)) {
      syms <<- c(syms, as.character(x))
    } else if (is.call(x)) {
      # Skip the RHS of `$` and `@`, which is a name but not a variable use,
      # and skip the globalVariables() call itself.
      if (identical(deparse(x[[1]]), "utils::globalVariables")) return(invisible())
      if (length(x) == 3L && deparse(x[[1]]) %in% c("$", "@")) {
        collect(x[[2]])
        return(invisible())
      }
      for (i in seq_along(x)) {
        if (!is.null(x[[i]])) try(collect(x[[i]]), silent = TRUE)
      }
    }
  }
  for (f in files) for (e in parse(f, keep.source = FALSE)) collect(e)
  syms <- unique(syms)

  expect_identical(setdiff(declared, syms), character(0))
})

test_that("bundled datasets are never referenced bare inside the package", {
  # A bare `world_tiles` resolves only while the package is *attached*: the
  # lazy-data objects live in the package environment, which is not on a
  # namespace-only lookup path. So `countryatlas::tile_map(...)` in a script with
  # no library() call died with "object 'world_tiles' not found" -- and so did
  # dissolve_country, distance_between, country_groups, in_group and
  # world_geometry(region = <group name>). Every test in this suite attaches the
  # package, so nothing caught it. Declaring the names in globalVariables()
  # silenced the check NOTE without fixing the runtime lookup, which is why the
  # NOTE existed. They must be `countryatlas::`-qualified.
  skip_if_no_source_tree()
  datasets <- c("world_snapshot", "country_meta", "world_tiles",
                "country_groups_tbl", "historical_codes", "common_indicators")
  files <- setdiff(list.files("../../R", pattern = "[.]R$", full.names = TRUE),
                   "../../R/data.R")            # data.R is the roxygen for them

  for (f in files) {
    code <- readLines(f, warn = FALSE)
    code <- code[!grepl("^\\s*#", code)]          # drop comment-only lines
    code <- sub("#.*$", "", code)                 # and trailing comments
    for (d in datasets) {
      # A bare use: the name not preceded by `::` or `$` and not inside a string.
      hits <- grep(paste0("(^|[^\\w.:$\"\'])", d, "([^\\w.\"\']|$)"),
                   code, perl = TRUE, value = TRUE)
      hits <- hits[!grepl(paste0("countryatlas::", d), hits, fixed = TRUE)]
      hits <- hits[!grepl("globalVariables", hits, fixed = TRUE)]
      expect_identical(hits, character(0),
                       info = paste(basename(f), "refers to", d, "unqualified"))
    }
  }
})
