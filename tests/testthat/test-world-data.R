test_that("world_data(year) keeps the classic backward-compatible output", {
  skip_if_offline_wb()
  skip_if_not_installed("maps")
  w <- world_data(2020)
  skip_if_wdi_empty(w, "gdp_per_capita")
  expect_true(all(c("long", "lat", "group", "iso3c", "iso2c", "income",
                    "continent", "gdp_per_capita") %in% names(w)))
  # The gdp_per_capita_2015 alias is opt-in as of 2.0.0: absent by default,
  # restored only when options(countryatlas.gdp_compat = TRUE).
  expect_false("gdp_per_capita_2015" %in% names(w))
  opt <- options(countryatlas.gdp_compat = TRUE)
  # The compat alias is deprecated and says so; assert that rather than let the
  # warning leak into the suite's summary.
  expect_warning(w_compat <- world_data(2020), "gdp_compat")
  options(opt)
  expect_true("gdp_per_capita_2015" %in% names(w_compat))
  expect_true(is.factor(w$income))
  expect_identical(levels(w$income), countryatlas:::income_levels())
})

test_that("multi-indicator named vectors drive clean column names", {
  skip_if_offline_wb()
  md <- country_data(2020, c(gdp = "NY.GDP.PCAP.KD", pop = "SP.POP.TOTL"))
  skip_if_wdi_empty(md, c("gdp", "pop"))
  expect_true(all(c("gdp", "pop") %in% names(md)))
  expect_false(any(c("NY.GDP.PCAP.KD", "SP.POP.TOTL") %in% names(md)))
  expect_gt(sum(!is.na(md$gdp)), 150)
})

test_that("a year range yields a panel keyed on iso3c + year", {
  skip_if_offline_wb()
  pan <- country_data(2018:2020, c(gdp = "NY.GDP.PCAP.KD"))
  skip_if_wdi_empty(pan, "gdp")
  expect_true("year" %in% names(pan))
  expect_setequal(unique(pan$year), 2018:2020)
  # one row per country-year
  expect_equal(anyDuplicated(pan[, c("iso3c", "year")]), 0)
})

test_that("year validation rejects bad input", {
  expect_error(world_data("2020"), class = "countryatlas_error")
  expect_error(world_data(1800), class = "countryatlas_error")
})

test_that("country_data with no indicator returns the country spine", {
  cd <- country_data(2020, indicator = NULL)
  expect_true(all(c("iso3c", "iso2c", "country", "continent") %in% names(cd)))
  expect_gt(nrow(cd), 150)
})

test_that("polygon and sf backends agree on country coverage", {
  skip_if_not_installed("maps")
  skip_if_no_sf_geometry()
  poly <- world_geometry("countries", geometry = "polygon")
  sfg <- world_geometry("countries", geometry = "sf")
  common <- intersect(stats::na.omit(unique(poly$iso3c)), sfg$iso3c)
  # The two backends should share the vast majority of countries.
  expect_gt(length(common), 150)
})

test_that("Natural Earth iso_a3 == -99 countries are recovered (regression)", {
  skip_if_no_sf_geometry()
  sfg <- world_geometry("countries", geometry = "sf")
  # France, Norway, Kosovo are notorious -99 cases; they must not vanish.
  expect_true(all(c("FRA", "NOR") %in% sfg$iso3c))
})
