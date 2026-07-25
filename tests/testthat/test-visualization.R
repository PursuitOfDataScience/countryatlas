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
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
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
  expect_s3_class(bubble_map(snap, population), "ggplot")
  expect_s3_class(tile_map(snap, gdp_per_capita), "ggplot")
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

test_that("theme_world_map is a theme", {
  expect_s3_class(theme_world_map(), "theme")
})

test_that("sf-only plots error cleanly without sf", {
  skip_if(requireNamespace("sf", quietly = TRUE))
  expect_error(bivariate_map(snap, gdp_per_capita, life_expectancy))
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
  expect_s3_class(
    interactive_map(mapdf, gdp_per_capita, tooltip = country, engine = "ggiraph"),
    "girafe"
  )
})

test_that("interactive_map(engine='leaflet') accepts a custom tooltip", {
  skip_if_not_installed("leaflet")
  skip_if_not_installed("sf")
  expect_s3_class(interactive_map(snap, gdp_per_capita, engine = "leaflet"), "leaflet")
  expect_s3_class(
    interactive_map(snap, gdp_per_capita, tooltip = country, engine = "leaflet"),
    "leaflet"
  )
})

test_that("dorling_map errors cleanly without sf/cartogram", {
  skip_if(requireNamespace("sf", quietly = TRUE) &&
            requireNamespace("cartogram", quietly = TRUE))
  expect_error(dorling_map(snap, gdp_per_capita))
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
