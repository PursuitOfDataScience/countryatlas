test_that("globe_map polygon backend constructs without sf", {
  skip_slow_on_cran()
  skip_if_not_installed("mapproj")
  p <- globe_map(world_snapshot$countries, continent, backend = "polygon",
                 style = "categorical")
  expect_s3_class(p, "ggplot")
  expect_s3_class(p$coordinates, "CoordMap")
})

test_that("spin_globe needs a gif encoder", {
  # Without gifski/magick it should fail fast, before rendering any frame.
  skip_if(requireNamespace("gifski", quietly = TRUE) ||
            requireNamespace("magick", quietly = TRUE))
  # Pinned to the encoder gate: unpinned, a mistyped column or any other
  # early failure would satisfy this, and the block only runs when both
  # encoders are absent.
  expect_error(
    spin_globe(world_snapshot$countries, continent, backend = "polygon",
               n_frames = 2L),
    class = "rlib_error_package_not_found"
  )
  expect_error(
    spin_globe(world_snapshot$countries, continent, backend = "polygon",
               n_frames = 2L),
    "gifski"
  )
})

test_that("globe_map(interactive) returns a WebGL globe", {
  skip_slow_on_cran()
  skip_if_not_installed("mapgl")
  skip_if_no_sf_geometry()
  expect_s3_class(globe_map(sf_df(), gdp_per_capita, interactive = TRUE),
                  "maplibregl")
  expect_error(globe_map(snap, gdp_per_capita, interactive = TRUE),
               "needs an sf frame")
})

test_that("globe_map(interactive = TRUE) validates before handing off", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  skip_if_not_installed("mapgl")
  g <- world_geometry(geometry = "sf")
  g$gdp <- as.numeric(seq_len(nrow(g)))
  # arg_match() and check_label_args() sat *below* the hand-off, so nothing
  # was checked on this path.
  expect_error(globe_map(g, gdp, interactive = TRUE, style = "nonsense"),
               "must be one of")
  expect_error(globe_map(g, gdp, interactive = TRUE,
                         title = c("a", "b", "c")),
               "single value")
  # ...and the ggplot2 styling that cannot travel to MapLibre is named.
  expect_warning(globe_map(g, gdp, interactive = TRUE, style = "quantile",
                           palette = "magma", title = "t"),
                 class = "countryatlas_engine_ignored")
  # The static path is unaffected.
  expect_no_warning(globe_map(g, gdp, style = "quantile", palette = "magma"))
})

test_that("an orthographic view can be drawn from any side", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  skip_on_cran()
  sfd <- suppressWarnings(attach_geometry(countryatlas::world_snapshot$countries,
                                          geometry = "sf"))
  draw <- function(p) {
    f <- tempfile(fileext = ".png")
    on.exit(unlink(f))
    grDevices::png(f, width = 120, height = 120)
    on.exit(grDevices::dev.off(), add = TRUE, after = FALSE)
    print(p)
    TRUE
  }
  # These viewpoints built and then failed when drawn: a country on the
  # horizon (Chad, at lon 120 / lat 20) projected to a one-point ring and grid
  # refused it with "Invalid graphics path".
  for (v in list(c(120, 20), c(140, 20), c(10, -60), c(50, 45), c(330, 70))) {
    expect_true(draw(globe_map(sfd, gdp_per_capita, lon = v[1], lat = v[2])))
  }
  expect_true(draw(world_map(sfd, gdp_per_capita, projection = "orthographic",
                             recenter = 140)))
  expect_true(draw(tissot_map("orthographic")))
  if (requireNamespace("tmap", quietly = TRUE) &&
      all(c("tm_scale_intervals", "tm_scale_continuous") %in%
            getNamespaceExports("tmap"))) {
    tm <- world_map(sfd, gdp_per_capita, engine = "tmap",
                    projection = "orthographic", recenter = 120)
    f <- tempfile(fileext = ".png")
    expect_no_error(suppressMessages(tmap::tmap_save(tm, f, width = 200,
                                                     height = 200)))
    unlink(f)
  }
  # The cut keeps every row, so the colour scale and the coverage are the same
  # from every side; what is out of view is empty, and nothing projects to a
  # non-finite or degenerate ring.
  cut <- countryatlas:::clip_to_hemisphere(sfd, 120, 20)
  expect_equal(nrow(cut), nrow(sfd))
  expect_equal(sf::st_drop_geometry(cut), sf::st_drop_geometry(sfd))
  pr <- sf::st_transform(cut, countryatlas:::wdj_crs("orthographic", 120, 20))
  xy <- sf::st_coordinates(pr[!sf::st_is_empty(pr), ])
  expect_true(all(is.finite(xy[, 1:2])))
  ring <- interaction(as.data.frame(xy[, setdiff(colnames(xy), c("X", "Y"))]),
                      drop = TRUE)
  expect_true(all(table(ring) >= 4L))
  expect_equal(map_provenance(globe_map(sfd, gdp_per_capita, lon = 120))$n_total,
               map_provenance(globe_map(sfd, gdp_per_capita, lon = 0))$n_total)
})

test_that("spin_globe renders one frame per central longitude", {
  skip_slow_on_cran()
  # gifski/magick assemble the GIF and are often unavailable, but the frame
  # loop is the part worth testing: it calls globe_map() once per longitude in
  # a full 0-360 sweep, which is why wdj_crs() must accept a `recenter` beyond
  # +/-180. Intercept ggsave() so the loop runs for real without writing PNGs.
  skip_if_not_installed("mapproj")
  snap <- countryatlas::world_snapshot$countries
  rendered <- list()
  testthat::local_mocked_bindings(
    ggsave = function(filename, plot, ...) {
      rendered[[length(rendered) + 1L]] <<- basename(filename)
      expect_s3_class(plot, "ggplot")
      invisible(filename)
    },
    .package = "ggplot2"
  )
  # Claim an assembler exists so the loop is reached; the assembly call itself
  # then fails, which is fine -- the frames are what we are checking.
  testthat::local_mocked_bindings(
    has_pkg = function(pkg) {
      if (identical(pkg, "gifski")) TRUE else isTRUE(requireNamespace(pkg, quietly = TRUE))
    }
  )
  invisible(tryCatch(
    spin_globe(snap, continent, backend = "polygon", style = "categorical",
               n_frames = 6, width = 120, height = 120),
    error = function(e) NULL
  ))
  expect_length(rendered, 6L)
  expect_equal(rendered[[1]], "frame_0001.png")
  expect_equal(rendered[[6]], "frame_0006.png")
})

test_that("spin_globe validates its scalars before rendering anything", {
  skip_slow_on_cran()
  # Deliberately NOT guarded on gifski/magick: a bad argument must be reported
  # regardless of which optional packages are installed, so these checks have
  # to run before the animation-package gate.
  snap <- countryatlas::world_snapshot$countries
  expect_error(spin_globe(snap, continent, backend = "polygon", n_frames = 1),
               "`n_frames`")
  expect_error(spin_globe(snap, continent, backend = "polygon", n_frames = NA),
               "single finite number")
  expect_error(spin_globe(snap, continent, backend = "polygon", fps = 0), "`fps`")
  expect_error(spin_globe(snap, continent, backend = "polygon", width = 0), "`width`")
  expect_error(spin_globe(snap, continent, backend = "polygon", lat = 200), "`lat`")
  # The fill column is validated by globe_map() inside the frame loop, which is
  # covered by globe_map()'s own tests -- reaching it here would need an
  # animation package installed.
})

test_that("globe_map(backend = 'sf') builds on every style", {
  skip_slow_on_cran()
  # This whole branch had no coverage: the only sf-related test in the file ran
  # *when sf was absent*, which is how nine bugs hid in an earlier pass.
  skip_if_no_sf_geometry()
  sfd <- attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf")
  for (st in c("continuous", "binned", "quantile", "jenks")) {
    if (st == "jenks") skip_if_not_installed("classInt")
    # n_bins only for the styles that bin: passing it under "continuous" now
    # draws a notice that the argument does not apply, which is correct and has
    # nothing to do with what this test is checking.
    p <- if (identical(st, "continuous")) {
      globe_map(sfd, gdp_per_capita, backend = "sf", style = st)
    } else {
      globe_map(sfd, gdp_per_capita, backend = "sf", style = st, n_bins = 4)
    }
    expect_s3_class(p, "ggplot")
    expect_no_error(ggplot2::ggplot_build(p))
  }
  p <- globe_map(sfd, continent, backend = "sf", style = "categorical",
                 title = "TT")
  expect_identical(p$labels$title, "TT")
  # lon/lat really do move the orthographic centre.
  crs_at <- function(lon) {
    b <- ggplot2::ggplot_build(globe_map(sfd, gdp_per_capita, backend = "sf",
                                         lon = lon))
    sf::st_crs(b$plot$coordinates$crs)$proj4string
  }
  expect_false(identical(crs_at(0), crs_at(90)))
  expect_match(crs_at(0), "ortho", fixed = TRUE)
})
