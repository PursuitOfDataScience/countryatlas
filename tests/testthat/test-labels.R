# --- Bug: geom_country_labels(data =) collided with the hardcoded data --------

test_that("geom_country_labels takes a data argument", {
  skip_slow_on_cran()
  mapdf <- poly_df()
  keep <- c("USA", "CHN", "IND", "BRA")
  # "formal argument \"data\" matched by multiple actual arguments" -- `data`
  # was hard-wired in the layer call while `...` forwarded to the same call.
  renders(world_map(mapdf, gdp_per_capita) +
            geom_country_labels(data = subset(mapdf, iso3c %in% keep)))
  renders(world_map(mapdf, gdp_per_capita) +
            geom_country_labels(data = function(d) subset(d, iso3c %in% keep)))
  renders(world_map(mapdf, gdp_per_capita) +
            geom_country_labels(data = ~ subset(.x, iso3c %in% keep)))
  renders(world_map(mapdf, gdp_per_capita) + geom_country_labels())
  # ... and `...` still reaches the text geom.
  renders(world_map(mapdf, gdp_per_capita) +
            geom_country_labels(data = subset(mapdf, iso3c %in% keep),
                                size = 4, colour = "white"))
})

test_that("geom_country_labels labels only the countries it was given", {
  skip_slow_on_cran()
  mapdf <- poly_df()
  keep <- c("USA", "CHN", "IND", "BRA")
  p <- world_map(mapdf, gdp_per_capita) +
    geom_country_labels(data = subset(mapdf, iso3c %in% keep), repel = FALSE)
  drawn <- ggplot2::ggplot_build(p)$data[[2]]
  expect_equal(nrow(drawn), length(keep))
})

test_that("geom_country_labels accepts a mapping and still honours flag", {
  skip_slow_on_cran()
  # to_centroids() reduced the frame to iso3c/long/lat/flag, so a mapping
  # naming any other column died on "object 'continent' not found" -- the
  # ordinary reason to pass a mapping. And modifyList(base, mapping) dropped
  # the default `label`, taking flag = TRUE with it.
  mapdf <- suppressWarnings(
    attach_geometry(world_snapshot$countries, geometry = "polygon"))
  labels_of <- function(...) {
    b <- ggplot2::ggplot_build(world_map(mapdf, gdp_per_capita) +
                                 geom_country_labels(..., repel = FALSE))
    b$data[[length(b$data)]]
  }
  lyr <- labels_of(ggplot2::aes(colour = continent))
  expect_gt(sum(!is.na(lyr$label)), 100)      # labels survive a custom mapping
  expect_gt(length(unique(lyr$colour)), 1)    # and the mapping took effect
  # flag = TRUE works with and without a mapping. A flag emoji is a pair of
  # regional-indicator code points (U+1F1E6..U+1F1FF).
  #
  # Compared as code points, not with a regex: `\p{Regional_Identifier}` is not
  # a property this PCRE build has, and the obvious fallback -- the range
  # "[\U0001F1E6-\U0001F1FF]" -- is not portable either. R's default engine
  # (TRE) cannot form a character range over non-BMP code points, so on Windows
  # that pattern is an error, not a non-match: "invalid regular expression,
  # reason 'Invalid character range'". utf8ToInt() involves no regex engine and
  # gives the same answer on every platform.
  is_flag <- function(x) {
    cps <- unlist(lapply(enc2utf8(as.character(x)), utf8ToInt),
                  use.names = FALSE)
    any(!is.na(cps) & cps >= 0x1F1E6L & cps <= 0x1F1FFL)
  }
  plain <- stats::na.omit(labels_of()$label)
  for (lab in list(labels_of(flag = TRUE),
                   labels_of(ggplot2::aes(colour = continent), flag = TRUE))) {
    txt <- stats::na.omit(lab$label)
    expect_true(is_flag(txt))
    expect_false(any(txt %in% plain))          # flags, not the ISO codes
  }
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
  # Said once, not on every call (repel = TRUE is the default). Where ggrepel
  # really is absent an earlier test has already had the once.
  rlang::reset_message_verbosity("geom_country_labels-no-ggrepel")
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

test_that("geom_country_labels does not inherit the group aesthetic", {
  skip_slow_on_cran()
  mapdf <- attach_geometry(snap, geometry = "polygon")
  p <- world_map(mapdf, gdp_per_capita) + geom_country_labels(repel = FALSE)
  expect_silent(ggplot2::ggplot_build(p))
})

test_that("geom_country_labels rejects an sf frame with an actionable message", {
  skip_slow_on_cran()
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
