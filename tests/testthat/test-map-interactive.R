# --- renderers ----------------------------------------------------------------------

test_that("interactive_map gains a mapgl engine", {
  skip_slow_on_cran()
  skip_if_not_installed("mapgl")
  skip_if_no_sf_geometry()
  d <- sf_df()
  expect_s3_class(interactive_map(d, gdp_per_capita, engine = "mapgl"),
                  "maplibregl")
  expect_s3_class(interactive_map(d, continent, engine = "mapgl"), "maplibregl")
  expect_error(interactive_map(poly_df(), gdp_per_capita, engine = "mapgl"),
               "needs an sf frame")
})

test_that("interactive_map names dots the engine cannot use", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  g <- world_geometry(geometry = "sf")
  g <- g[g$iso3c %in% c("FRA", "DEU", "ESP", "ITA"), ]
  g$gdp <- c(1, 2, 3, 4)

  # `...` was documented as reaching world_map() for ggiraph, but that branch
  # builds its own ggplot, so `style = "quantile"` was silently dropped and
  # the map came back with the default continuous fill. It now classifies as
  # world_map() does, silently; an argument it cannot use is still named.
  skip_if_not_installed("ggiraph")
  expect_no_warning(gq <- interactive_map(g, gdp, engine = "ggiraph",
                                          style = "continuous"))
  expect_no_warning(interactive_map(g, gdp, engine = "ggiraph"))
  expect_warning(interactive_map(g, gdp, engine = "ggiraph", na_style = "hatched"),
                 "na_style")

  skip_if_not_installed("leaflet")
  w <- tryCatch(
    interactive_map(g, gdp, engine = "leaflet", style = "quantile",
                    n_bins = 3),
    warning = function(x) x)
  msg <- cli::ansi_strip(paste(conditionMessage(w), collapse = " "))
  expect_match(msg, "these arguments", fixed = TRUE)
  expect_match(msg, "style", fixed = TRUE)
  expect_match(msg, "n_bins", fixed = TRUE)
  expect_no_warning(interactive_map(g, gdp, engine = "leaflet"))

  # plotly genuinely forwards, so it stays quiet and still rejects nonsense.
  skip_if_not_installed("plotly")
  expect_no_warning(interactive_map(g, gdp, engine = "plotly",
                                    style = "quantile"))
  expect_error(interactive_map(g, gdp, engine = "plotly", nonsense_arg = 1))
})

test_that("the tmap engine names an older tmap instead of failing opaquely", {
  skip_slow_on_cran()
  # DESCRIPTION pins no version on any Suggests package, so need_pkg("tmap") is
  # satisfied by any tmap -- including a 3.x that exports none of the scale
  # constructors this engine builds with. The capability is checked, not a
  # version number, so this stays right whichever release introduced them.
  expect_true(isTRUE(countryatlas:::check_tmap_api(
    have = countryatlas:::tmap_scale_api)))

  # A tmap 3-shaped export list: tm_shape and tm_polygons, no tm_scale_*().
  err <- tryCatch(
    countryatlas:::check_tmap_api(have = c("tm_shape", "tm_polygons")),
    error = function(e) e)
  expect_s3_class(err, "countryatlas_old_tmap")
  msg <- gsub("[[:space:]]+", " ",
              cli::ansi_strip(paste(conditionMessage(err), collapse = " ")))
  expect_match(msg, "too old", fixed = TRUE)
  expect_match(msg, "tm_scale_intervals", fixed = TRUE)
  expect_match(msg, "ggplot2", fixed = TRUE)

  # A partial upgrade is still too old, and the message names only what is
  # actually missing.
  partial <- tryCatch(
    countryatlas:::check_tmap_api(
      have = c("tm_scale_intervals", "tm_shape")),
    error = function(e) e)
  expect_s3_class(partial, "countryatlas_old_tmap")
  pmsg <- cli::ansi_strip(paste(conditionMessage(partial), collapse = " "))
  expect_match(pmsg, "tm_scale_continuous", fixed = TRUE)
  expect_false(grepl("tm_scale_intervals", pmsg, fixed = TRUE))

  # And the installed tmap really does satisfy it.
  skip_if_not_installed("tmap")
  expect_true(isTRUE(countryatlas:::check_tmap_api()))
})

test_that("the ggsql engine states the version it needs", {
  # `DRAW spatial` landed in ggsql 0.4.1; CRAN currently ships 0.3.3, which
  # would accept the call and then reject the clause inside its own SQL front
  # end. The gate must name the version, not just the package.
  skip_if(requireNamespace("ggsql", quietly = TRUE) &&
            utils::packageVersion("ggsql") >= "0.4.1")
  skip_if_no_sf_geometry()
  # Must be an *sf* frame: the sf check now runs ahead of the package gates, so a
  # country-level frame is (correctly) rejected for its shape before ggsql is
  # ever consulted.
  sfd <- attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf")
  err <- tryCatch(interactive_map(sfd, gdp_per_capita, engine = "ggsql"),
                  condition = function(e) conditionMessage(e))
  expect_match(err, "ggsql", fixed = TRUE)
  expect_match(err, "0.4.1", fixed = TRUE)
})

# `tooltip =` was documented but silently ignored by every engine before 2.0.0.
# The original tests only asserted the returned object's class, which passes
# whether the argument is honoured or dropped -- mutation testing found the fix
# unprotected. Capture what each engine is actually handed. Split per engine and
# skipped explicitly: as one test with both engines inside requireNamespace()
# blocks, it ran zero expectations and still reported green wherever the engines
# were absent.

test_that("interactive_map's ggiraph engine honours tooltip", {
  skip_slow_on_cran()
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
  skip_slow_on_cran()
  skip_if_not_installed("leaflet")
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  seen <- NULL
  # The labels are computed values now, not `~` formulas. That was the point of
  # the change: leaflet evaluates a formula against the data as an environment,
  # so `~ pal(get(fill_name))` found a *column* named `pal` before the palette
  # function, and `~ paste0(iso3c, ...)` read iso3c with nothing checking for
  # it. Asserting the rendered strings is also a better test than reading a
  # column name out of a formula's environment -- it checks what the user sees.
  testthat::local_mocked_bindings(
    addPolygons = function(map, ..., label = NULL) {
      seen <<- label
      map
    },
    .package = "leaflet"
  )
  invisible(interactive_map(snap, gdp_per_capita, engine = "leaflet"))
  expect_type(seen, "character")
  expect_gt(length(seen), 100L)
  # "<iso3c>: <value>", with the fill column as the default tooltip.
  fra <- grep("^FRA: ", seen, value = TRUE)
  expect_length(fra, 1L)
  gdp <- snap$gdp_per_capita[match("FRA", snap$iso3c)]
  expect_equal(fra, paste0("FRA: ", gdp))

  invisible(interactive_map(snap, gdp_per_capita, tooltip = country,
                            engine = "leaflet"))
  fra2 <- grep("^FRA: ", seen, value = TRUE)
  expect_length(fra2, 1L)
  expect_equal(fra2, "FRA: France")
})

test_that("the interactive engines draw a fill with nothing to scale", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  sfd <- suppressWarnings(attach_geometry(countryatlas::world_snapshot$countries,
                                          geometry = "sf"))
  sfd$allna <- NA_real_
  sfd$oneval <- NA_real_
  sfd$oneval[sfd$iso3c %in% "FRA"] <- 5
  sfd$const <- 3
  sfd$catna <- NA_character_
  if (requireNamespace("leaflet", quietly = TRUE)) {
    # colorNumeric() died on "Wasn't able to determine range of domain".
    for (col in c("allna", "oneval", "const", "catna")) {
      expect_no_error(interactive_map(sfd, !!rlang::sym(col), engine = "leaflet"))
    }
  }
  if (requireNamespace("mapgl", quietly = TRUE)) {
    # One distinct value gave one break and two colours; none at all was
    # refused by mapgl outright.
    for (col in c("allna", "oneval", "const", "catna")) {
      expect_no_warning(w <- interactive_map(sfd, !!rlang::sym(col),
                                             engine = "mapgl"))
      expect_s3_class(w, "maplibregl")
    }
  }
})

test_that("the plotly engine refuses the orthographic view by name", {
  skip_slow_on_cran()
  skip_if_not_installed("plotly")
  skip_if_no_sf_geometry()
  sfd <- suppressWarnings(attach_geometry(countryatlas::world_snapshot$countries,
                                          geometry = "sf"))
  expect_error(interactive_map(sfd, gdp_per_capita, engine = "plotly",
                               projection = "orthographic"),
               class = "countryatlas_engine_projection")
  expect_s3_class(interactive_map(sfd, gdp_per_capita, engine = "plotly"),
                  "plotly")
})

test_that("interactive_map(engine='ggiraph') accepts a custom tooltip", {
  skip_slow_on_cran()
  skip_if_not_installed("ggiraph")
  mapdf <- attach_geometry(snap, geometry = "polygon")
  expect_s3_class(interactive_map(mapdf, gdp_per_capita, engine = "ggiraph"), "girafe")
  by_country <- interactive_map(mapdf, gdp_per_capita, tooltip = country,
                                engine = "ggiraph")
  expect_s3_class(by_country, "girafe")
  # Asserting the class alone would pass if `tooltip` were dropped on the floor:
  # the object is a girafe either way. Two different tooltip columns have to
  # produce two different widgets.
  by_iso <- interactive_map(mapdf, gdp_per_capita, tooltip = iso3c,
                            engine = "ggiraph")
  expect_false(identical(by_country$x$html, by_iso$x$html))
})

test_that("interactive_map(engine='leaflet') accepts a custom tooltip", {
  skip_slow_on_cran()
  skip_if_not_installed("leaflet")
  skip_if_no_sf_geometry()
  expect_s3_class(interactive_map(snap, gdp_per_capita, engine = "leaflet"), "leaflet")
  by_country <- interactive_map(snap, gdp_per_capita, tooltip = country,
                                engine = "leaflet")
  expect_s3_class(by_country, "leaflet")
  # Same reasoning as the ggiraph case: the class is satisfied whether or not
  # `tooltip` was honoured, so compare two different columns.
  by_iso <- interactive_map(snap, gdp_per_capita, tooltip = iso3c,
                            engine = "leaflet")
  lbl <- function(m) vapply(m$x$calls, function(cl) paste(utils::capture.output(
    str(cl$args)), collapse = ""), character(1))
  expect_false(identical(lbl(by_country), lbl(by_iso)))
})

test_that("interactive_map reports a missing geometry the same way on every engine", {
  skip_slow_on_cran()
  # The ggiraph branch assembles its own ggplot rather than calling world_map(),
  # so it bypassed the geometry check and failed at render time on `.data$long`,
  # while engine = "plotly" reported it properly. leaflet attaches geometry
  # itself and is documented as doing so.
  snap <- countryatlas::world_snapshot$countries
  for (eng in c("plotly", "ggiraph")) {
    skip_if_not_installed(eng)
    expect_error(interactive_map(snap, gdp_per_capita, engine = eng),
                 "no map geometry", info = eng)
    expect_error(interactive_map(snap, gdp_per_capita, engine = eng),
                 class = "countryatlas_error")
  }
  mapdf <- attach_geometry(snap, geometry = "polygon")
  for (eng in c("plotly", "ggiraph")) {
    skip_if_not_installed(eng)
    expect_s3_class(interactive_map(mapdf, gdp_per_capita, engine = eng),
                    "htmlwidget")
  }
  # leaflet attaches sf geometry itself, to a polygon frame as to a country
  # table, so it needs the sf backend too. Skipping on leaflet alone ran this
  # wherever leaflet was installed and sf could not be loaded.
  skip_if_not_installed("leaflet")
  skip_if_no_sf_geometry()
  expect_s3_class(interactive_map(mapdf, gdp_per_capita, engine = "leaflet"),
                  "htmlwidget")
  # leaflet's documented leniency: a country-level table is fine there.
  expect_s3_class(interactive_map(snap, gdp_per_capita, engine = "leaflet"),
                  "htmlwidget")
})
