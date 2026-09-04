snap <- countryatlas::world_snapshot$countries

test_that("world_map builds a ggplot for several styles", {
  skip_if_not_installed("maps")
  mapdf <- attach_geometry(snap, geometry = "polygon")
  for (style in c("continuous", "binned", "quantile", "categorical")) {
    fill_col <- if (style == "categorical") "continent" else "gdp_per_capita"
    p <- world_map(mapdf, !!rlang::sym(fill_col), style = style)
    expect_s3_class(p, "ggplot")
    expect_silent(ggplot2::ggplot_build(p))
  }
})

test_that("world_map renders in every documented projection", {
  # Regression: winkel_tripel built a CRS fine and st_transform()ed fine, but
  # coord_sf()'s graticule collapsed to a degenerate point under it and GEOS
  # threw "point array must contain 0 or >1 elements" -- so one of the eight
  # projections 2.0.0 advertises errored on every render. Only a full
  # ggplot_build() over every projection catches this class of bug.
  skip_if_no_sf_geometry()
  sfdata <- attach_geometry(snap, geometry = "sf")
  for (proj in countryatlas:::wdj_projections()) {
    expect_no_error(
      ggplot2::ggplot_build(world_map(sfdata, gdp_per_capita, projection = proj))
    )
  }
})

test_that("na_label renames the discrete legend's NA key", {
  skip_if_not_installed("maps")
  mapdf <- attach_geometry(snap, geometry = "polygon")
  labels_of <- function(p) {
    ggplot2::ggplot_build(p)$plot$scales$scales[[1]]$get_labels()
  }
  # Default.
  expect_true("No data" %in% labels_of(world_map(mapdf, continent,
                                                 style = "categorical")))
  # Custom, for both the categorical and the binned-into-a-factor styles.
  expect_true("Not reported" %in%
    labels_of(world_map(mapdf, continent, style = "categorical",
                        na_label = "Not reported")))
  expect_true("Not reported" %in%
    labels_of(world_map(mapdf, gdp_per_capita, style = "quantile",
                        na_label = "Not reported")))
  # Real levels are untouched.
  expect_true("Europe" %in% labels_of(world_map(mapdf, continent,
                                                style = "categorical")))
})

test_that("bubble_map, tile_map and flow_map build", {
  skip_if_not_installed("maps")
  expect_s3_class(suppressWarnings(bubble_map(snap, population)), "ggplot")
  expect_s3_class(suppressWarnings(tile_map(snap, gdp_per_capita)), "ggplot")
  od <- data.frame(from = c("China", "Germany"),
                   to = c("United States", "France"), value = c(5, 2))
  expect_s3_class(flow_map(od, from, to, value), "ggplot")
})

test_that("geom_country_labels does not inherit the group aesthetic", {
  skip_if_not_installed("maps")
  mapdf <- attach_geometry(snap, geometry = "polygon")
  p <- world_map(mapdf, gdp_per_capita) + geom_country_labels(repel = FALSE)
  expect_silent(ggplot2::ggplot_build(p))
})

test_that("theme_world_map is applied where the docs say it is", {
  # ?theme_world_map used to claim "all the package's plotting functions".
  # bivariate_map() is the documented exception -- it uses biscale::bi_theme()
  # so the map matches biscale's own legend. facet_map()/dorling_map() get the
  # theme indirectly, via world_map()/cartogram_map().
  direct <- c("world_map", "globe_map", "bubble_map", "spike_map",
              "cartogram_map", "tile_map", "flow_map")
  for (f in direct) {
    src <- paste(deparse(body(get(f, envir = asNamespace("countryatlas")))),
                 collapse = " ")
    expect_true(grepl("theme_world_map", src, fixed = TRUE), info = f)
  }
  for (f in c("facet_map", "dorling_map")) {
    src <- paste(deparse(body(get(f, envir = asNamespace("countryatlas")))),
                 collapse = " ")
    expect_false(grepl("theme_world_map", src, fixed = TRUE), info = f)
    expect_true(grepl("world_map\\(|cartogram_map\\(", src), info = f)
  }
  bi <- paste(deparse(body(bivariate_map)), collapse = " ")
  expect_false(grepl("theme_world_map", bi, fixed = TRUE))
  expect_true(grepl("bi_theme", bi, fixed = TRUE))
})

test_that("theme_world_map is a theme", {
  expect_s3_class(theme_world_map(), "theme")
})

test_that("sf-only plots error cleanly without sf", {
  skip_if(requireNamespace("sf", quietly = TRUE))
  # "cleanly" is the whole point of this test, so assert the package gate
  # rather than any error at all. bivariate_map() checks biscale before sf, so
  # the message names whichever is missing first -- pin the class, which holds
  # either way.
  expect_error(bivariate_map(snap, gdp_per_capita, life_expectancy),
               class = "rlib_error_package_not_found")
})

test_that("bivariate_map builds a ggplot (needs sf + biscale)", {
  # Regression: the fill columns were injected into biscale::bi_class() with
  # `!!sym()`, but bi_class() reads them with as.character(substitute(...)),
  # so every call failed with "the condition has length > 1".
  skip_if_not_installed("sf")
  skip_if_not_installed("biscale")
  skip_if_not_installed("rnaturalearth")
  sfdata <- attach_geometry(snap, geometry = "sf")
  p <- suppressWarnings(bivariate_map(sfdata, gdp_per_capita, life_expectancy))
  expect_s3_class(p, "ggplot")
  expect_no_error(suppressWarnings(ggplot2::ggplot_build(p)))
  expect_s3_class(
    suppressWarnings(bivariate_map(sfdata, gdp_per_capita, life_expectancy,
                                   dim = 2)),
    "ggplot"
  )
  expect_error(bivariate_map(sfdata, not_a_column, life_expectancy),
               class = "countryatlas_error")
})

test_that("interactive_map(engine='ggiraph') accepts a custom tooltip", {
  skip_if_not_installed("ggiraph")
  skip_if_not_installed("maps")
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

test_that("dorling_map errors cleanly without sf/cartogram", {
  skip_if(requireNamespace("sf", quietly = TRUE) &&
            requireNamespace("cartogram", quietly = TRUE))
  # cartogram_map()'s need_pkg() runs ahead of its is_sf() check, so the gate
  # is what fires here -- pinned, so a shape or argument error cannot pass for
  # it.
  expect_error(dorling_map(snap, gdp_per_capita), class = "rlib_error_package_not_found")
})

test_that("a Dorling cartogram is area-proportional and does not overlap", {
  # Sixteen tests cover this family's validation, package gating, cell counts
  # and denominators -- none of them the two properties that make the output a
  # Dorling cartogram at all. Passing the wrong column, or skipping the
  # equal-area projection, would leave every one of them passing.
  skip_if_no_sf_geometry()
  skip_if_not_installed("cartogram")
  sfd <- suppressWarnings(
    attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf"))
  d <- suppressWarnings(dorling_map(sfd, population))$data

  # Areas are only honest in a projected CRS.
  expect_false(sf::st_is_longlat(d))

  # Circle area is proportional to the value -- so the ratio is one constant,
  # not merely correlated.
  a <- as.numeric(suppressWarnings(sf::st_area(d)))
  v <- d$population
  ok <- is.finite(a) & is.finite(v) & v > 0 & a > 0
  expect_gt(sum(ok), 100L)
  ratio <- a[ok] / v[ok]
  expect_equal(max(ratio) / min(ratio), 1, tolerance = 1e-6)

  # ...and the whole point of Dorling: the circles do not overlap.
  old <- sf::sf_use_s2()
  on.exit(suppressMessages(sf::sf_use_s2(old)), add = TRUE)
  suppressMessages(sf::sf_use_s2(FALSE))
  touching <- suppressWarnings(sf::st_intersects(d))
  expect_equal((sum(lengths(touching)) - nrow(d)) / 2, 0)
})

test_that("a gridded cartogram keeps countries near where they really are", {
  # The grid is only a map if a country's cell tracks its real position; a
  # mis-assignment would draw a plausible-looking grid of the wrong countries.
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  d <- suppressWarnings(gridded_cartogram(snap, population, cells = 900))$data
  cm <- countryatlas::country_meta
  lon <- cm$centroid_lon[match(d$iso3c, cm$iso3c)]
  lat <- cm$centroid_lat[match(d$iso3c, cm$iso3c)]
  ok <- is.finite(lon) & is.finite(lat) & is.finite(d$x) & is.finite(d$y)
  expect_gt(sum(ok), 500L)
  expect_gt(cor(d$x[ok], lon[ok]), 0.9)
  expect_gt(cor(d$y[ok], lat[ok]), 0.9)
  # One country per cell (a country may hold several cells -- that is the
  # value-proportional part).
  expect_false(any(duplicated(paste(d$x, d$y))))
})

test_that("dorling_map builds a ggplot (needs sf + cartogram)", {
  skip_if_not_installed("sf")
  skip_if_not_installed("cartogram")
  skip_if_not_installed("rnaturalearth")
  sfdata <- world_geometry("countries", geometry = "sf")
  sfdata <- dplyr::inner_join(sfdata, snap[, c("iso3c", "population")], by = "iso3c")
  p <- dorling_map(sfdata, population)
  expect_s3_class(p, "ggplot")
})

test_that("great_circle returns the requested number of points", {
  gc <- countryatlas:::great_circle(0, 0, 90, 0, n = 25)
  expect_equal(nrow(gc), 25)
  expect_named(gc, c("lon", "lat"))
})

test_that("world_map quantile breaks are country-weighted, not vertex-weighted", {
  # One country (A) has 100 vertices, the others have 1; values are 1..4. The
  # quantile breaks must come from the 4 country values, so each country lands
  # in its own bin -- not be dominated by the 100 copies of value 1.
  df <- rbind(
    data.frame(iso3c = "A", group = 1, long = 0, lat = 0, val = 1)[rep(1, 100), ],
    data.frame(iso3c = "B", group = 2, long = 1, lat = 1, val = 2),
    data.frame(iso3c = "C", group = 3, long = 2, lat = 2, val = 3),
    data.frame(iso3c = "D", group = 4, long = 3, lat = 3, val = 4)
  )
  p <- world_map(df, val, style = "quantile", n_bins = 4)
  expect_equal(length(unique(stats::na.omit(as.character(p$data$.wdj_bin)))), 4L)
})

# Forgetting attach_geometry() is the easiest mistake in the package, and it is
# easy precisely because the other plotting verbs do not need it: tile_map(),
# bubble_map(), spike_map() and globe_map() all take a country-level frame. So
# world_map(snap, gdp) looks like it should work -- it returned a ggplot object
# with no complaint, then failed only when printed, with ggplot2's "Problem
# while computing aesthetics ... Caused by error in `.data$long`".

test_that("world_map rejects a frame with no geometry, at the call", {
  snap <- countryatlas::world_snapshot$countries
  expect_error(world_map(snap, gdp_per_capita), "no map geometry")
  expect_error(world_map(snap, gdp_per_capita), class = "countryatlas_error")
  expect_error(world_map(snap, gdp_per_capita), "attach_geometry")
  # facet_map() delegates to world_map(), so it is covered too.
  expect_error(facet_map(snap, gdp_per_capita, region), "no map geometry")
  # A frame with only some of the polygon columns is not map-ready either.
  half <- snap
  half$long <- 1
  expect_error(world_map(half, gdp_per_capita), "no map geometry")
})

test_that("world_map still accepts every documented route to geometry", {
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  poly <- attach_geometry(snap, geometry = "polygon")
  expect_s3_class(world_map(poly, gdp_per_capita), "ggplot")
  expect_s3_class(world_map(poly, gdp_per_capita, style = "quantile"), "ggplot")
  expect_s3_class(facet_map(attach_geometry(transform(snap, yr = 2020L),
                                            geometry = "polygon"),
                            gdp_per_capita, yr), "ggplot")
  # join_world() produces a map-ready frame from messy names.
  jw <- suppressWarnings(join_world(
    data.frame(country = c("France", "Brazil"), v = c(1, 2)), country,
    warn = FALSE))
  expect_s3_class(world_map(jw, v), "ggplot")
  if (requireNamespace("sf", quietly = TRUE) &&
      requireNamespace("rnaturalearth", quietly = TRUE)) {
    sfd <- suppressWarnings(attach_geometry(snap, geometry = "sf"))
    expect_s3_class(world_map(sfd, gdp_per_capita), "ggplot")
  }
})

test_that("the country-level plotting verbs keep working without geometry", {
  # Pin the asymmetry deliberately: these four attach geometry themselves, so
  # the guard above must not spread to them.
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  expect_s3_class(suppressWarnings(tile_map(snap, gdp_per_capita)), "ggplot")
  expect_s3_class(suppressWarnings(bubble_map(snap, population)), "ggplot")
  expect_s3_class(suppressWarnings(spike_map(snap, population)), "ggplot")
  skip_if_not_installed("mapproj")
  expect_s3_class(globe_map(snap, gdp_per_capita, backend = "polygon"), "ggplot")
})

test_that("a returned plot survives ordinary ggplot2 operations", {
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  poly <- attach_geometry(snap, geometry = "polygon")
  plots <- suppressWarnings(
    list(world_map(poly, gdp_per_capita), tile_map(snap, gdp_per_capita),
         bubble_map(snap, population), spike_map(snap, population)))
  for (p in plots) {
    expect_s3_class(p, "ggplot")
    expect_no_error(ggplot2::ggplot_build(p + ggplot2::theme_minimal()))
    expect_no_error(ggplot2::ggplot_build(p + ggplot2::labs(title = "t")))
    expect_no_error(ggplot2::ggplot_build(
      p + ggplot2::theme(legend.position = "bottom")))
    f <- tempfile(fileext = ".png")
    # suppressWarnings: the snapshot has five countries with no population, so
    # geom_point() reports dropping them. That is ggplot2 behaving correctly,
    # and it is not what this test is about.
    suppressWarnings(suppressMessages(
      ggplot2::ggsave(f, p, width = 4, height = 3, dpi = 72)))
    expect_true(file.exists(f))
    unlink(f)
  }
})

# The numeric fill styles said so only obliquely and late. "continuous" and
# "binned" reached ggplot2 and failed at *print* time ("Discrete value supplied
# to a continuous scale", "Binned scales only support continuous data"), neither
# naming the column. "quantile" and "jenks" did not fail at all: compute_breaks()
# returns early on a non-numeric column, so the fill fell through to the discrete
# scale and drew a plausible map whose legend claimed quantile bins it had never
# computed. The reverse direction -- categorical on a numeric column -- was
# already guarded, so this closes the pair.

test_that("the numeric fill styles require a numeric column", {
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  mapdf <- attach_geometry(snap, geometry = "polygon")
  chr <- mapdf; chr$g <- "a"
  fac <- mapdf; fac$g <- factor(rep(c("lo", "hi"), length.out = nrow(mapdf)))
  for (st in c("continuous", "binned", "quantile", "jenks")) {
    for (d in list(chr, fac)) {
      expect_error(world_map(d, g, style = st), "needs a numeric", info = st)
      expect_error(world_map(d, g, style = st), class = "countryatlas_error")
      # The message names the style and the column.
      expect_error(world_map(d, g, style = st), st, fixed = TRUE)
      expect_error(world_map(d, g, style = st), "\"g\"", fixed = TRUE)
    }
  }
  # And it fires at the call, not when the plot is drawn.
  expect_error(world_map(chr, g, style = "quantile"), "needs a numeric")
})

test_that("the legitimate style/column pairings are untouched", {
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  mapdf <- attach_geometry(snap, geometry = "polygon")
  for (st in c("continuous", "binned", "quantile", "jenks")) {
    # suppressWarnings: `jenks` degrades to quantile breaks with a warning when
    # classInt is absent, as it is in a Suggests-free check. That is documented
    # behaviour, pinned by its own test below, and not what this one is about.
    expect_no_error(suppressWarnings(ggplot2::ggplot_build(
      world_map(mapdf, gdp_per_capita, style = st))))
  }
  fac <- mapdf; fac$g <- factor(rep(c("lo", "hi"), length.out = nrow(mapdf)))
  expect_no_error(ggplot2::ggplot_build(world_map(fac, g, style = "categorical")))
  chr <- mapdf; chr$g <- "a"
  expect_no_error(ggplot2::ggplot_build(world_map(chr, g, style = "categorical")))
  # The pre-existing reverse guard still fires.
  expect_error(world_map(mapdf, gdp_per_capita, style = "categorical"),
               "needs a discrete")
})

test_that("interactive_map reports a missing geometry the same way on every engine", {
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
  skip_if_not_installed("maps")
  mapdf <- attach_geometry(snap, geometry = "polygon")
  for (eng in c("plotly", "ggiraph", "leaflet")) {
    skip_if_not_installed(eng)
    expect_s3_class(interactive_map(mapdf, gdp_per_capita, engine = eng),
                    "htmlwidget")
  }
  # leaflet's documented leniency: a country-level table is fine there.
  skip_if_not_installed("leaflet")
  expect_s3_class(interactive_map(snap, gdp_per_capita, engine = "leaflet"),
                  "htmlwidget")
})

test_that("animate_world validates before handing off to gganimate", {
  skip_if_not_installed("maps")
  # A three-country panel is enough, and keeps the geometry join small: joining
  # the whole snapshot for three years is ~250k rows and trips dplyr's
  # many-to-many heuristic, which is noise for what this test checks.
  snap <- countryatlas::world_snapshot$countries
  small <- snap[snap$iso3c %in% c("FRA", "BRA", "USA"), ]
  panel <- do.call(rbind, lapply(2018:2020, function(y) transform(small, yr = y)))
  mapdf <- attach_geometry(panel, geometry = "polygon")
  expect_error(animate_world(panel, gdp_per_capita, yr), "no map geometry")
  expect_error(animate_world(mapdf, gdp_per_capita, nope), "not found")
  chr <- mapdf; chr$g <- "a"
  expect_error(animate_world(chr, g, yr), "needs a numeric")
  # The documented fallback when gganimate is absent is a faceted plot.
  local_mocked_bindings(has_pkg = function(pkg) {
    if (identical(pkg, "gganimate")) FALSE
    else isTRUE(requireNamespace(pkg, quietly = TRUE))
  })
  expect_message(animate_world(mapdf, gdp_per_capita, yr), "faceting")
  out <- suppressMessages(animate_world(mapdf, gdp_per_capita, yr))
  expect_s3_class(out, "ggplot")
  expect_no_error(ggplot2::ggplot_build(out))
})

test_that("jenks degrades to quantile breaks when classInt is absent", {
  # A documented fallback that had no test of its own: it surfaced only as an
  # unexplained warning in the Suggests-free check tally.
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  mapdf <- attach_geometry(snap, geometry = "polygon")
  local_mocked_bindings(has_pkg = function(pkg) {
    if (identical(pkg, "classInt")) FALSE
    else isTRUE(requireNamespace(pkg, quietly = TRUE))
  })
  expect_warning(world_map(mapdf, gdp_per_capita, style = "jenks"),
                 "classInt")
  p <- suppressWarnings(world_map(mapdf, gdp_per_capita, style = "jenks"))
  expect_s3_class(p, "ggplot")
  expect_no_error(suppressWarnings(ggplot2::ggplot_build(p)))
  # Only jenks needs classInt; quantile computes its own breaks either way.
  expect_no_warning(world_map(mapdf, gdp_per_capita, style = "quantile"))
})

test_that("flow_map says when it cannot place a flow", {
  # An unresolvable endpoint has no centroid, so its arc silently vanished --
  # and when nothing resolved, flow_map returned a bare world map with no arc
  # layer at all and no warning. The commonest cause is feeding iso3c codes
  # while `origin` still defaults to "country.name".
  skip_if_not_installed("maps")
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

test_that("geom_country_labels rejects an sf frame with an actionable message", {
  # The layer's own aes(x = long, y = lat) was evaluated against the sf frame,
  # which has neither column, so the failure was rlang's data-pronoun abort:
  # "Column `long` not found in `.data`". The 0-row guard inside label_data()
  # never got a chance to run.
  skip_if_no_sf_geometry()
  sfd <- attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf")
  p <- world_map(sfd, gdp_per_capita) + geom_country_labels()
  expect_error(ggplot2::ggplot_build(p), "needs the polygon backend",
               class = "countryatlas_error")
  expect_error(ggplot2::ggplot_build(p), "geom_sf_text")
  # And the recommended alternative really does work.
  alt <- world_map(sfd, gdp_per_capita) +
    ggplot2::geom_sf_text(ggplot2::aes(label = iso3c), size = 2)
  expect_no_error(ggplot2::ggplot_build(alt))
})

test_that("label placement survives the antimeridian without `group`", {
  # polygon_centroids() is exact because `group` identifies each country's
  # pieces and the label goes on the largest. Without it, a plain mean(range())
  # put every country that crosses 180 degrees on the far side of the planet:
  # measured against the largest-piece centroid, Fiji was 177.8 degrees out,
  # New Zealand 169.6, and the USA 96.6 (its Aleutian tail dragging the
  # mid-range into the Gulf of Guinea).
  skip_if_not_installed("maps")
  poly <- attach_geometry(countryatlas::world_snapshot$countries,
                          geometry = "polygon")
  truth <- countryatlas:::polygon_centroids(poly)
  lon_of <- function(cc) {
    x <- poly$long[!is.na(poly$iso3c) & poly$iso3c == cc]
    c(plain = mean(range(x, na.rm = TRUE)),
      fixed = countryatlas:::antimeridian_centre(x),
      truth = truth$centroid_lon[truth$iso3c == cc])
  }
  for (cc in c("FJI", "NZL", "USA")) {
    v <- lon_of(cc)
    expect_lt(abs(v[["fixed"]] - v[["truth"]]), abs(v[["plain"]] - v[["truth"]]))
  }
  expect_lt(abs(lon_of("FJI")[["fixed"]] - lon_of("FJI")[["truth"]]), 1)
  # A country that never crosses the line is untouched.
  expect_equal(lon_of("RUS")[["fixed"]], lon_of("RUS")[["plain"]])
  # Antarctica encircles the pole rather than straddling the line, so longitude
  # is arbitrary and the wrap moves it: pinned so the trade-off stays visible.
  expect_equal(round(lon_of("ATA")[["fixed"]]), 180)

  # End to end: the group-less frame still labels every country.
  nogrp <- poly[, setdiff(names(poly), "group")]
  built <- ggplot2::ggplot_build(ggplot2::ggplot(nogrp) + geom_country_labels())
  expect_gt(nrow(built$data[[1]]), 200L)
  fj <- built$data[[1]]
  expect_gt(fj$x[fj$label == "FJI"], 170)
})
