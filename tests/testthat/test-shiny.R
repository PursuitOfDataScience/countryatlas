# world_map_ui() / world_map_server(): the Shiny module (V4).

test_that("the UI namespaces its inputs and the plot output", {
  skip_if_not_installed("shiny", "1.6.0")
  ui <- as.character(world_map_ui("atlas", style = "fisher", n_bins = 4))
  for (id in c("fill", "style", "n_bins", "projection", "map")) {
    expect_match(ui, sprintf('id="atlas-%s"', id), fixed = TRUE)
  }
  expect_match(ui, '<option value="fisher" selected>', fixed = TRUE)
})

test_that("the UI validates its starting values, naming the argument", {
  skip_if_not_installed("shiny", "1.6.0")
  expect_error(world_map_ui(1), "id")
  expect_error(world_map_ui("m", style = "categorical"), "style")
  expect_error(world_map_ui("m", projection = "flat"), "projection")
  expect_error(world_map_ui("m", n_bins = 12), "n_bins")
})

test_that("the server maps the chosen column, classes and projection", {
  skip_if_not_installed("shiny", "1.6.0")
  skip_slow_on_cran()
  shiny::testServer(world_map_server,
    args = list(data = world_snapshot$countries, fill = "gdp_per_capita"), {
      session$setInputs(fill = "gdp_per_capita", style = "fisher", n_bins = 4,
                        projection = "equal_earth")
      p <- session$returned()
      expect_s3_class(p, "ggplot")
      prov <- map_provenance(p)
      expect_identical(prov$fill, "gdp_per_capita")
      expect_identical(prov$style, "fisher")
      expect_identical(prov$n_bins, 4L)
      session$setInputs(fill = "life_expectancy", projection = "none")
      prov <- map_provenance(session$returned())
      expect_identical(prov$fill, "life_expectancy")
      expect_identical(prov$projection, "none")
    })
})

test_that("a reactive frame works, and an unmappable one fails at start", {
  skip_if_not_installed("shiny", "1.6.0")
  skip_slow_on_cran()
  shiny::testServer(world_map_server,
    args = list(data = shiny::reactive(world_snapshot$countries[1:40, ])), {
      session$setInputs(fill = "population", style = "quantile", n_bins = 3,
                        projection = "equal_earth")
      expect_identical(map_provenance(session$returned())$fill, "population")
    })
  expect_error(world_map_server("m", data.frame(x = 1)), "iso3c")
  expect_error(world_map_server("m", 1:3), "data frame")
  expect_error(world_map_server("m", world_snapshot$countries, style = "sd"),
               "inputs")
})

test_that("only numeric non-key columns are offered as fills", {
  d <- data.frame(iso3c = "FRA", year = 2020, long = 1, lat = 2, group = 1,
                  order = 1, gdp = 1, name = "a", .hidden = 1,
                  check.names = FALSE)
  expect_identical(countryatlas:::shiny_fill_columns(d), "gdp")
})
