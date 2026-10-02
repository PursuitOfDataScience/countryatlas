# --- spike_map ------------------------------------------------------------------

test_that("spike_map builds a ggplot with one triangle per country", {
  skip_slow_on_cran()
  # In degrees: three vertices per spike.
  p <- suppressWarnings(spike_map(world_snapshot$countries, population,
                                  projection = "none"))
  expect_s3_class(p, "ggplot")
  expect_silent(ggplot2::ggplot_build(p))
  spikes <- p$layers[[2]]$data
  expect_equal(nrow(spikes) %% 3L, 0L)
  expect_equal(anyDuplicated(unique(spikes$iso3c)), 0L)
  # Projected: one sf triangle per country, in the map's own CRS.
  skip_if_not_installed("sf")
  q <- suppressWarnings(spike_map(world_snapshot$countries, population))
  sp <- q$layers[[2]]$data
  expect_s3_class(sp, "sf")
  expect_equal(anyDuplicated(sp$iso3c), 0L)
  expect_true(all(lengths(sf::st_geometry(sp)) == 1L))
})

test_that("spike_map validates input", {
  expect_error(spike_map(data.frame(x = 1), x), class = "countryatlas_error")
})

test_that("bubble_map and spike_map count only the countries they can place", {
  skip_slow_on_cran()
  # The basemap does not draw every code in the codelist, so a
  # point-per-country verb silently lost the ones it has no centroid for --
  # five on the 3.0.0 basemap, Gibraltar alone on the Natural Earth one.
  # bubble_map left-joined and drew a point at (NA, NA) -- ggplot2 muttered
  # "Removed 5 rows" -- while spike_map inner-joined and said nothing. Both then
  # computed provenance on the frame as it arrived, so a population map missing
  # Hong Kong reported "215 of 215".
  snap <- world_snapshot$countries
  cent <- world_geometry("centroids", geometry = "polygon")
  n_lost <- sum(!snap$iso3c %in% cent$iso3c & !is.na(snap$population))
  expect_gt(n_lost, 0)                       # the premise holds on this snapshot

  # geom_point puts every bubble in one group, so count rows there and groups
  # for the spike triangles (3 vertices per country).
  verbs <- list(
    bubble_map = list(f = bubble_map, count = function(d) nrow(d)),
    spike_map  = list(f = spike_map, count = function(d) {
      if ("geometry" %in% names(d)) nrow(d) else length(unique(d$group))
    })
  )
  for (nm in names(verbs)) {
    expect_warning(p <- verbs[[nm]]$f(snap, population),
                   class = "countryatlas_no_centroid")
    cov <- attr(p, "countryatlas_provenance")$coverage
    expect_equal(cov$n_missing, n_lost)
    expect_equal(cov$n_shown, cov$n_total - n_lost)
    expect_true("GIB" %in% cov$missing_iso3c)
    # n_shown must equal what is on the page, not what came in.
    b <- ggplot2::ggplot_build(p)
    expect_equal(verbs[[nm]]$count(b$data[[2]]), cov$n_shown)
  }
  # And ggplot2 no longer has NA coordinates to complain about.
  expect_silent(suppressWarnings({
    p <- bubble_map(snap, population)
    invisible(ggplot2::ggplot_build(p))
  }))
})

test_that("point verbs tolerate data that already carries centroid columns", {
  skip_slow_on_cran()
  # world_geometry("centroids") output, or anything joined to it, collided with
  # the internal join: dplyr suffixed both sides to .x/.y and the aes() looking
  # for `.data$centroid_lon` found no such column.
  d <- world_snapshot$countries
  d$centroid_lon <- 0
  d$centroid_lat <- 0
  for (f in list(bubble_map, spike_map)) {
    # In degrees, so the drawn positions can be read off the layer.
    p <- suppressWarnings(f(d, population, projection = "none"))
    expect_s3_class(ggplot2::ggplot_build(p), "ggplot_built")
    # The bundled centroids win -- nothing is drawn at the planted (0, 0).
    xy <- ggplot2::ggplot_build(p)$data[[2]]
    expect_false(all(xy$x == 0))
  }
})

test_that("flow_map arcs cross the antimeridian instead of the whole map", {
  skip_slow_on_cran()
  # A great circle Tokyo -> Los Angeles runs ...178, 179, -179, -178..., and
  # geom_path() under coord_quickmap() joined those two points literally: every
  # trans-Pacific flow was drawn as a horizontal streak back across Africa.
  d <- data.frame(from = c("Japan", "Fiji"), to = c("United States", "Peru"),
                  vol = c(10, 5))
  p <- flow_map(d, from, to, weight = vol)
  # In degrees on either backend: the built-in Equal Earth (no sf) projects
  # the arcs itself and keeps their degrees in .wdj_lon.
  arcs <- p$layers[[2]]$data
  lon <- if (".wdj_lon" %in% names(arcs)) arcs$.wdj_lon else arcs$lon
  jumps <- unlist(lapply(split(lon, arcs$.grp), function(x) abs(diff(x))))
  expect_lt(max(jumps), 180)
  # Each Pacific flow is drawn as two pieces meeting exactly on the edge.
  expect_equal(length(unique(arcs$.grp)), 4L)
  edges <- sort(unique(round(range(lon), 6)))
  expect_equal(edges, c(-180, 180))
  # And a flow that does not cross the dateline stays in one piece.
  p2 <- flow_map(data.frame(from = "France", to = "Germany"), from, to)
  expect_equal(length(unique(ggplot2::ggplot_build(p2)$data[[2]]$group)), 1L)
})

test_that("flow_map legends carry the caller's weight column name", {
  skip_slow_on_cran()
  # The internal arc frame's column is literally called `weight`, so ggplot2
  # titled both legends "weight" whatever the user had mapped.
  d <- data.frame(from = "France", to = "Germany", trade_volume = 7)
  p <- flow_map(d, from, to, weight = trade_volume)
  nms <- vapply(p$scales$scales, function(s) s$name %||% NA_character_, "")
  expect_true("trade_volume" %in% nms)
  expect_false("weight" %in% nms)
  # Same name on both scales, so the two guides merge into one legend.
  expect_equal(sum(nms == "trade_volume", na.rm = TRUE), 2L)
})

test_that("the antimeridian splitter handles the degenerate crossings", {
  sp <- countryatlas:::split_antimeridian
  mk <- function(lon) data.frame(lon = lon, lat = seq_along(lon))
  cases <- list(
    none      = list(mk(c(0, 10, 20)),                       1L),
    one       = list(mk(c(170, 179, -179, -170)),            2L),
    on_plus   = list(mk(c(170, 180, -180, -170)),            2L),
    on_minus  = list(mk(c(-170, -180, 180, 170)),            2L),
    two_rows  = list(mk(c(179, -179)),                       2L),
    at_end    = list(mk(c(170, 179, -179)),                  2L),
    twice     = list(mk(c(170, 179, -179, -100, 100, 179, -179)), 4L)
  )
  for (nm in names(cases)) {
    d <- cases[[nm]][[1]]
    out <- sp(d, rep(1L, nrow(d)))
    # A point sitting exactly on the edge makes the crossing interpolation 0/0.
    expect_true(all(is.finite(out$lon)), info = nm)
    expect_true(all(is.finite(out$lat)), info = nm)
    expect_equal(length(unique(out$.grp)), cases[[nm]][[2]], info = nm)
    within <- unlist(lapply(split(out$lon, out$.grp),
                            function(x) if (length(x) > 1) abs(diff(x)) else 0))
    expect_lt(max(within), 180)
  }
})

test_that("a caller column named x0/y0/x1/y1 does not break flow_map", {
  skip_slow_on_cran()
  # The arc endpoints are joined in under those names, and a caller who
  # geocoded their own endpoints -- the shape of frame this verb is for -- has
  # them already. dplyr suffixed both sides and the completeness check failed
  # with vctrs' "Can't subset columns that don't exist".
  fl <- data.frame(from = c("United States", "France"),
                   to = c("France", "Japan"), w = c(5, 3))
  for (nm in c("x0", "y0", "x1", "y1")) {
    d <- fl
    d[[nm]] <- 1
    expect_s3_class(suppressWarnings(flow_map(d, from, to, w)), "ggplot")
  }
  a <- suppressWarnings(ggplot2::ggplot_build(flow_map(fl, from, to, w)))
  d2 <- fl
  d2$x0 <- 1
  b <- suppressWarnings(ggplot2::ggplot_build(flow_map(d2, from, to, w)))
  expect_equal(a$data, b$data)

  # A column flow_map actually reads cannot be dropped, so it is refused.
  d3 <- fl
  names(d3)[3] <- "x0"
  expect_error(flow_map(d3, from, to, x0), class = "countryatlas_error")
})

test_that("a pre-joined centroid column does not break the cartogram", {
  skip_slow_on_cran()
  # country_meta carries centroid_lon/centroid_lat, so joining it for capitals
  # or area before drawing is ordinary. gridded_cartogram() then joined the
  # centroids again without dropping the caller's, dplyr suffixed both sides to
  # `.x`/`.y`, and the filter failed with vctrs' "Can't subset rows with
  # `is.na(df$centroid_lon) | ...`". bubble_map() and spike_map() already
  # guarded the same join.
  skip_if_no_sf_geometry()
  snap <- world_snapshot$countries
  cm <- countryatlas::country_meta[, c("iso3c", "centroid_lon", "centroid_lat")]
  withc <- dplyr::left_join(snap, cm, by = "iso3c")

  expect_s3_class(suppressWarnings(gridded_cartogram(withc, population)),
                  "ggplot")
  expect_s3_class(suppressWarnings(bubble_map(withc, population)), "ggplot")
  expect_s3_class(suppressWarnings(spike_map(withc, population)), "ggplot")

  # Dropping the caller's columns must not change what is drawn.
  a <- suppressWarnings(ggplot2::ggplot_build(gridded_cartogram(snap,
                                                                population)))
  b <- suppressWarnings(ggplot2::ggplot_build(gridded_cartogram(withc,
                                                                population)))
  expect_equal(a$data, b$data)
})

test_that("an NA country key never borrows a centroid", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  d <- data.frame(iso3c = c("USA", NA), population = c(10, 99))
  b <- ggplot2::ggplot_build(bubble_map(d, population, backend = "sf"))
  pts <- b$data[[length(b$data)]]
  expect_equal(sum(!is.na(pts$size)), 1L)           # USA only
})

test_that("bubble and spike maps refuse sizes they cannot draw", {
  skip_slow_on_cran()
  snap <- countryatlas::world_snapshot$countries[, c("iso3c", "population")]
  snap$population[snap$iso3c == "FRA"] <- -1.4e9
  snap$population[snap$iso3c == "DEU"] <- Inf
  snap$population[snap$iso3c == "ITA"] <- NA
  quiet_centroids <- function(expr) withCallingHandlers(
    expr, countryatlas_no_centroid = function(w) invokeRestart("muffleWarning"))
  expect_warning(p <- quiet_centroids(bubble_map(snap, population)),
                 class = "countryatlas_unusable_size")
  # No "Removed 1 row containing missing values" at build time for ITA.
  expect_no_warning(ggplot2::ggplot_build(p))
  prov <- map_provenance(p)
  expect_true(all(c("FRA", "DEU", "ITA") %in% prov$missing_iso3c[[1]]))
  # What is drawn is what is counted as shown: one point per country.
  expect_equal(nrow(ggplot2::layer_data(p, 2)), prov$n_countries)
  # spike_map() said these had "no bundled centroid".
  msgs <- character(0)
  withCallingHandlers(spike_map(snap, population),
                      warning = function(w) {
                        msgs <<- c(msgs, conditionMessage(w))
                        invokeRestart("muffleWarning")
                      })
  centroid_msg <- grep("no bundled centroid", msgs, value = TRUE)
  expect_length(centroid_msg, 1L)
  expect_no_match(centroid_msg, "FRA|DEU")
  expect_true(any(grepl("negative or infinite", msgs)))
})

test_that("flow_map() drops unusable weights before they reach the scales", {
  skip_slow_on_cran()
  od <- data.frame(from = c("China", "Germany", "United States", "Japan"),
                   to = c("United States", "France", "Mexico", "Brazil"),
                   value = c(500, NA, 300, Inf))
  expect_warning(p <- flow_map(od, from, to, value),
                 "2 flows dropped: the weight is missing or infinite")
  # Printing used to fail with grid's "'lwd' must be non-negative and finite".
  expect_no_warning(print(p))
})

test_that("bubble_map() projects on the polygon backend too", {
  skip_slow_on_cran()
  snap <- countryatlas::world_snapshot$countries
  # Gibraltar has no centroid, which is reported on its own.
  bubbles <- function(...) {
    withCallingHandlers(bubble_map(snap, population, ...),
                        countryatlas_no_centroid = function(w) {
                          invokeRestart("muffleWarning")
                        })
  }
  # 3.0.0 said the polygon backend ignored `projection`; it applies now,
  # through sf (without it, the built-in Equal Earth only).
  expect_no_warning(bubbles())
  skip_if_not_installed("sf")
  expect_no_warning(p <- bubbles(projection = "robinson"))
  expect_identical(map_provenance(p)$projection, "robinson")
})

test_that("bubble_map, tile_map and flow_map build", {
  skip_slow_on_cran()
  expect_s3_class(suppressWarnings(bubble_map(snap, population)), "ggplot")
  expect_s3_class(suppressWarnings(tile_map(snap, gdp_per_capita)), "ggplot")
  od <- data.frame(from = c("China", "Germany"),
                   to = c("United States", "France"), value = c(5, 2))
  expect_s3_class(flow_map(od, from, to, value), "ggplot")
})

test_that("great_circle returns the requested number of points", {
  gc <- countryatlas:::great_circle(0, 0, 90, 0, n = 25)
  expect_equal(nrow(gc), 25)
  expect_named(gc, c("lon", "lat"))
})

test_that("the country-level plotting verbs keep working without geometry", {
  skip_slow_on_cran()
  # Pin the asymmetry deliberately: these four attach geometry themselves, so
  # the guard above must not spread to them.
  snap <- countryatlas::world_snapshot$countries
  expect_s3_class(suppressWarnings(tile_map(snap, gdp_per_capita)), "ggplot")
  expect_s3_class(suppressWarnings(bubble_map(snap, population)), "ggplot")
  expect_s3_class(suppressWarnings(spike_map(snap, population)), "ggplot")
  skip_if_not_installed("mapproj")
  expect_s3_class(globe_map(snap, gdp_per_capita, backend = "polygon"), "ggplot")
})

test_that("flow_map says when it cannot place a flow", {
  skip_slow_on_cran()
  # An unresolvable endpoint has no centroid, so its arc silently vanished --
  # and when nothing resolved, flow_map returned a bare world map with no arc
  # layer at all and no warning. The commonest cause is feeding iso3c codes
  # while `origin` still defaults to "country.name".
  d <- tibble::tibble(from = c("USA", "FRA"), to = c("CHN", "BRA"), w = c(1, 2))

  expect_warning(p <- flow_map(d, from, to, w), "flows dropped")
  expect_warning(flow_map(d, from, to, w), class = "countryatlas_warning")
  # Nothing placed: the map is still returned, but with no arc layer.
  expect_length(ggplot2::ggplot_build(p)$data, 1L)

  # Told how to read the codes, it is silent and draws the arcs.
  expect_silent(ok <- flow_map(d, from, to, w, origin = "iso3c"))
  expect_length(ggplot2::ggplot_build(ok)$data, 2L)

  # Proper names on the default origin are silent too.
  named <- tibble::tibble(from = c("China", "Germany"),
                          to = c("United States", "France"), value = c(500, 200))
  expect_silent(flow_map(named, from, to, value))

  # A partial failure warns and still draws what it can.
  part <- tibble::tibble(from = c("China", "Zzz"),
                         to = c("United States", "France"), value = c(1, 2))
  expect_warning(pp <- flow_map(part, from, to, value), "1 flow dropped")
  expect_gt(nrow(ggplot2::ggplot_build(pp)$data[[2]]), 0L)
})
