test_that("world_data(year) keeps the classic backward-compatible output", {
  skip_if_offline_wb()
  w <- wdi_live(world_data(2020))
  skip_if_wdi_empty(w, "gdp_per_capita")
  expect_true(all(c("long", "lat", "group", "iso3c", "iso2c", "income",
                    "continent", "gdp_per_capita") %in% names(w)))
  # The gdp_per_capita_2015 alias of 1.0.0 is gone, option and all.
  expect_false("gdp_per_capita_2015" %in% names(w))
  expect_true(is.factor(w$income))
  expect_identical(levels(w$income), countryatlas:::income_levels())
})

test_that("multi-indicator named vectors drive clean column names", {
  skip_if_offline_wb()
  md <- wdi_live(country_data(2020, c(gdp = "NY.GDP.PCAP.KD", pop = "SP.POP.TOTL")))
  skip_if_wdi_empty(md, c("gdp", "pop"))
  expect_true(all(c("gdp", "pop") %in% names(md)))
  expect_false(any(c("NY.GDP.PCAP.KD", "SP.POP.TOTL") %in% names(md)))
  expect_gt(sum(!is.na(md$gdp)), 150)
})

test_that("a year range yields a panel keyed on iso3c + year", {
  skip_if_offline_wb()
  pan <- wdi_live(country_data(2018:2020, c(gdp = "NY.GDP.PCAP.KD")))
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

test_that("world_data validates classify and language before fetching", {
  skip_slow_on_cran()
  # `classify` was filtered with intersect(), which silently dropped anything
  # unrecognised -- so classify = "incomes" added no classification columns and
  # said nothing -- and `language` went straight to WDI, where a length-2 value
  # surfaced as "the condition has length > 1". Both are checked before the
  # network call, which is also why this test needs no connection.
  expect_error(world_data(2020, classify = "incomes"), "must be one of")
  expect_error(world_data(2020, classify = c("income", "nope")), "must be one of")
  expect_error(world_data(2020, classify = 1), "must be a character")
  expect_error(world_data(2020, classify = NA), "must be a character")
  expect_error(world_data(2020, language = 1), "must be a single string")
  expect_error(world_data(2020, language = c("en", "fr")), "single string")

  # country_data takes the same two arguments and shares the checks.
  expect_error(country_data(2020, classify = "incomes"), "must be one of")
  expect_error(country_data(2020, language = c("en", "fr")), "single string")

  # Asking for no classification at all stays valid -- that is what
  # character(0) means -- and so does any subset.
  #
  # Mocked, because expect_error(expr, NA) *evaluates* the call: these two
  # reached the live World Bank API and cost the suite two 60-second timeouts
  # and four warnings whenever it was slow, in a test whose whole point is that
  # validation happens BEFORE any fetch. helper-net.R exists for the tests that
  # do need the network; this one does not.
  testthat::local_mocked_bindings(
    fetch_one_indicator = function(code, name, start, end, language = "en") {
      tibble::tibble(iso2c = c("FR", "DE"), iso3c = c("FRA", "DEU"),
                     country = c("France", "Germany"),
                     year = as.integer(start), !!name := c(1, 2))
    }
  )
  expect_error(world_data(2020, classify = character(0)), NA)
  expect_error(world_data(2020, classify = c("income", "region")), NA)
})

test_that("a failed download is not written to the on-disk cache", {
  # memoise caches whatever the function returns, and the World Bank cache is on
  # disk. WDI() answers a failed download by warning and returning a zero-row
  # frame, so one call made while the network was down persisted an empty
  # result and every later session read it back instead of retrying.
  skip_if_not_installed("WDI")
  dir <- withr::local_tempdir()
  withr::local_options(countryatlas.cache_dir = dir)
  local_mocked_bindings(
    wb_request = function(indicator, start, end, extra = FALSE, language = "en", ...) {
      warning("Unable to download data")
      d <- data.frame(iso2c = character(0), country = character(0),
                      year = integer(0))
      d[[names(indicator)[1]]] <- numeric(0)
      d
    }, .package = "countryatlas")
  suppressWarnings(suppressMessages(
    try(country_data(2020, c(gdp = "NY.GDP.PCAP.KD")), silent = TRUE)))
  expect_length(list.files(dir, recursive = TRUE), 0L)
  # And the user is told why, rather than silently getting nothing.
  # The stub emits WDI's own "Unable to download data" alongside ours; muffle
  # just that one so the assertion is about the condition we raise.
  expect_warning(
    withCallingHandlers(
      suppressMessages(countryatlas:::fetch_wdi(c(gdp = "NY.GDP.PCAP.KD"),
                                                2020, 2020)),
      warning = function(w) {
        if (grepl("Unable to download", conditionMessage(w), fixed = TRUE)) {
          invokeRestart("muffleWarning")
        }
      }),
    class = "countryatlas_no_data")
})

test_that('world_data(geometry = "none") warns for every sf-only argument', {
  fake <- tibble::tibble(iso3c = c("FRA", "DEU"), country = c("a", "b"),
                         gdp_per_capita = c(1, 2))
  local_mocked_bindings(country_data = function(...) fake,
                        .package = "countryatlas")
  # No geometry is fetched at all, so none of the three can be honoured.
  expect_warning(world_data(2020, geometry = "none", projection = "mollweide"),
                 class = "countryatlas_projection_ignored")
  expect_warning(world_data(2020, geometry = "none", recenter = 150),
                 class = "countryatlas_recenter_ignored")
  expect_warning(world_data(2020, geometry = "none", scale = "large"),
                 class = "countryatlas_scale_ignored")
  expect_no_warning(world_data(2020, geometry = "none"))
})

test_that('world_data(geometry = "none") still honours region', {
  # region was only applied inside attach_geometry(), which this branch skips,
  # so asking for one continent quietly returned the whole world.
  fake <- tibble::tibble(
    iso3c = c("FRA", "DEU", "USA", "BRA", "CHN"),
    country = c("France", "Germany", "United States", "Brazil", "China"),
    gdp_per_capita = c(1, 2, 3, 4, 5))
  local_mocked_bindings(country_data = function(...) fake,
                        .package = "countryatlas")

  expect_equal(nrow(world_data(2020, geometry = "none")), 5L)
  expect_equal(world_data(2020, geometry = "none", region = "Europe")$iso3c,
               c("FRA", "DEU"))
  expect_equal(
    world_data(2020, geometry = "none", region = c("FRA", "BRA"))$iso3c,
    c("FRA", "BRA"))
  # A bounding box needs shapes to clip; refuse rather than return the world.
  expect_error(world_data(2020, geometry = "none", region = c(-10, 35, 30, 60)),
               class = "countryatlas_bbox_without_geometry")
  # `scale` is an sf-backend option, so it cannot be honoured here either.
  expect_warning(world_data(2020, geometry = "none", scale = "large"),
                 class = "countryatlas_scale_ignored")
  expect_no_warning(world_data(2020, geometry = "none"))
})

test_that("the network-backed examples degrade instead of failing offline", {
  # CRAN policy: examples must not fail when a web resource is unavailable, and
  # world_data()/country_data() are \donttest{} examples that run under
  # --run-donttest. With every WDI call erroring they must warn and still return
  # a usable table, built from the country spine.
  testthat::local_mocked_bindings(
    fetch_one_indicator = function(...) stop("Could not resolve host")
  )
  # Into a cache directory of its own, and empty. Otherwise a successful fetch
  # left on disk by an earlier test -- or by a developer's own session -- is
  # served from the cache, the mock is never called, and the test silently
  # asserts nothing. It passed in isolation and failed in combination, which is
  # the tell.
  withr::local_options(list(
    countryatlas.cache_dir = file.path(tempfile("degrade-cache"), "c")))
  clear_country_cache("wdi")
  withr::defer(clear_country_cache("wdi"))
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

test_that("a non-finite year is refused as such, without a coercion warning", {
  expect_error(country_data(Inf), "finite")
  expect_error(country_data(c(2000, Inf)), "finite")
  expect_no_warning(try(country_data(Inf), silent = TRUE))
})

test_that("latest = TRUE records the year each value comes from", {
  # Each value column took its own last non-NA value and `year` was dropped:
  # France came back with GDP from 2023 beside population from 2021, and
  # nothing recorded which year any value came from.
  fake <- tibble::tibble(
    iso3c = rep(c("FRA", "DEU"), each = 3), iso2c = rep(c("FR", "DE"), each = 3),
    country = rep(c("France", "Germany"), each = 3), year = rep(2021:2023, 2),
    gdp = c(1, 2, 3, 10, 20, NA), pop = c(5, NA, NA, 7, 8, 9))
  get <- function(latest) {
    testthat::with_mocked_bindings(
      country_data(2023, c(gdp = "X", pop = "Y"), latest = latest,
                   classify = character()),
      fetch_wdi = function(...) fake)
  }
  each <- get(TRUE)
  expect_identical(names(each), c("iso3c", "iso2c", "country", "gdp",
                                  "gdp_year", "pop", "pop_year"))
  fra <- each[each$iso3c == "FRA", ]
  expect_equal(c(fra$gdp, fra$gdp_year, fra$pop, fra$pop_year),
               c(3, 2023, 5, 2021))
  deu <- each[each$iso3c == "DEU", ]
  expect_equal(c(deu$gdp_year, deu$pop_year), c(2022, 2023))
  # "common": the latest year in which every indicator is present.
  com <- get("common")
  expect_equal(com$gdp[com$iso3c == "FRA"], 1)
  expect_equal(com$pop_year[com$iso3c == "FRA"], 2021L)
  expect_equal(com$gdp_year[com$iso3c == "DEU"], 2022L)
  expect_equal(com$pop[com$iso3c == "DEU"], 8)
  expect_error(get("newest"), "common")
  expect_error(get(NA), class = "countryatlas_error")
})

test_that("a country with no common year gets NA throughout", {
  fake <- tibble::tibble(iso3c = "FRA", iso2c = "FR", country = "France",
                         year = 2021:2022, gdp = c(1, NA), pop = c(NA, 2))
  out <- testthat::with_mocked_bindings(
    country_data(2022, c(gdp = "X", pop = "Y"), latest = "common",
                 classify = character()),
    fetch_wdi = function(...) fake)
  expect_true(is.na(out$gdp) && is.na(out$pop) && is.na(out$gdp_year))
})
