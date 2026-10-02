test_that("fetch_sdmx() reads the OECD's SDMX-CSV onto the spine", {
  # OECD.Stat, which the OECD package's client still targets, went offline on
  # 2024-07-01; the replacement service is SDMX, read here with no client.
  seen <- local_fixture_http(list("/dataflow/OECD.SDD.NAD/" = "oecd-naag-structure.json",
                                  "/data/OECD.SDD.NAD" = "oecd-naag.csv"))
  x <- fetch_sdmx("oecd", c(gdp_growth = "OECD.SDD.NAD,DSD_NAAG@DF_NAAG_I,1.0"),
                  key = "A..B1GQ_R_GR..", countries = c("FRA", "DEU", "JPN"),
                  years = 2020:2023)
  expect_identical(names(x), c("iso3c", "year", "gdp_growth"))
  expect_setequal(unique(x$iso3c), c("FRA", "DEU", "JPN"))
  expect_identical(sort(unique(x$year)), 2020:2023)
  expect_equal(x$gdp_growth[x$iso3c == "JPN" & x$year == 2020],
               -4.28327942682386)
  # The countries went into the key's REF_AREA slot, so the server filtered.
  data_url <- grep("/data/", seen$urls, value = TRUE)
  expect_match(data_url, "/A.FRA+DEU+JPN.B1GQ_R_GR..?", fixed = TRUE)
  expect_match(data_url, "startPeriod=2020&endPeriod=2023", fixed = TRUE)
  info <- source_info(x)
  expect_identical(info$source, "oecd")
  expect_identical(info$unit, "Percentage change")
  expect_match(info$label, "NAAG Chapter 1", fixed = TRUE)
})

test_that("fetch_oecd() is fetch_sdmx() for the OECD", {
  local_fixture_http(list("/dataflow/OECD.SDD.NAD/" = "oecd-naag-structure.json",
                          "/data/OECD.SDD.NAD" = "oecd-naag.csv"))
  a <- fetch_oecd(c(g = "OECD.SDD.NAD,DSD_NAAG@DF_NAAG_I,1.0"),
                  countries = c("FRA", "DEU", "JPN"), years = 2020:2023,
                  key = "A..B1GQ_R_GR..")
  expect_identical(names(a), c("iso3c", "year", "g"))
  expect_identical(nrow(a), 12L)
  expect_identical(source_info(a)$column, "g")
})

test_that("the ILO and the IMF are sources too", {
  local_fixture_http(list("/dataflow/ILO/" = "ilo-une-structure.json",
                          "/data/ILO," = "ilo-une.csv"))
  u <- fetch_indicator("ilo", c(unemp = "ILO,DF_UNE_DEAP_SEX_AGE_RT,1.0"),
                       countries = c("FRA", "DEU"), years = 2020:2022,
                       key = ".A..SEX_T.AGE_YTHADULT_YGE15")
  expect_identical(nrow(u), 6L)
  expect_equal(u$unemp[u$iso3c == "DEU" & u$year == 2020], 3.881)
  expect_identical(source_info(u)$licence, "CC BY 4.0")
  local_fixture_http(list("/structure/dataflow/IMF.RES/" = "imf-weo-structure.json",
                          "/data/IMF.RES" = "imf-weo.csv"))
  g <- fetch_indicator("imf", c(g = "IMF.RES,WEO,9.0.0"),
                       countries = c("FRA", "DEU"), years = 2021:2022,
                       key = ".NGDP_RPCH.A")
  expect_identical(nrow(g), 4L)
  expect_identical(source_info(g)$provider_updated, "2026-04-15")
})

test_that("a dimension that still varies is named, never silently first-rowed", {
  csv <- paste("DATAFLOW,REF_AREA,MEASURE,TIME_PERIOD,OBS_VALUE",
               "X:Y(1.0),FRA,A,2020,1", "X:Y(1.0),FRA,B,2020,2", sep = "\n")
  local_fixture_http(list("/data/" = function(u) fixture_response(text = csv)))
  expect_error(fetch_sdmx("bis", "BIS,X,1.0"), "MEASURE",
               class = "countryatlas_sdmx_not_unique")
  qtr <- paste("DATAFLOW,REF_AREA,TIME_PERIOD,OBS_VALUE",
               "X:Y(1.0),FR,2020-Q1,1", "X:Y(1.0),FR,2020-Q2,2", sep = "\n")
  local_fixture_http(list("/data/" = function(u) fixture_response(text = qtr)))
  expect_error(fetch_sdmx("bis", "BIS,X,1.0"), "not years",
               class = "countryatlas_sdmx_not_unique")
})

test_that("a provider without a published structure is filtered locally", {
  csv <- paste("DATAFLOW,REF_AREA,TIME_PERIOD,OBS_VALUE",
               "X:Y(1.0),FR,2020,1", "X:Y(1.0),DE,2020,2", "X:Y(1.0),XM,2020,3",
               sep = "\n")
  seen <- local_fixture_http(list("/data/" = function(u) fixture_response(text = csv)))
  x <- fetch_sdmx("bis", c(rate = "BIS,WS_CBPOL,1.0"), countries = "FRA")
  expect_identical(x$iso3c, "FRA")
  expect_match(seen$urls, "/data/BIS,WS_CBPOL,1.0/all", fixed = TRUE)
})

test_that("an empty or failed answer degrades, and strict makes it an error", {
  local_fixture_http(list("/data/" = function(u) fixture_response(
    text = "DATAFLOW,REF_AREA,TIME_PERIOD,OBS_VALUE")))
  expect_warning(z <- fetch_sdmx("bis", c(v = "BIS,X,1.0")),
                 class = "countryatlas_no_data")
  expect_identical(names(z), c("iso3c", "year", "v"))
  expect_identical(nrow(z), 0L)
  testthat::local_mocked_bindings(
    wdj_http_get = function(url, ...) {
      rlang::abort("HTTP status 503", class = c("countryatlas_fetch_failed",
                                                "countryatlas_error"),
                   status = 503L)
    }, .package = "countryatlas")
  expect_warning(f <- fetch_sdmx("bis", "BIS,X,1.0"),
                 class = "countryatlas_fetch_failed")
  expect_identical(nrow(f), 0L)
  withr::local_options(countryatlas.strict = TRUE)
  expect_error(fetch_sdmx("bis", "BIS,X,1.0"), class = "countryatlas_fetch_failed")
})

test_that("fetch_sdmx() validates provider, flow and key", {
  skip_slow_on_cran()
  expect_error(fetch_sdmx("nowhere", "A,B,1.0"), "Unknown SDMX provider")
  expect_error(fetch_sdmx("oecd", "A,B,1.0,extra"), "dataflow")
  expect_error(fetch_sdmx("oecd", "A,B/../x,1.0"), "dataflow")
  expect_error(fetch_sdmx("oecd", 1), class = "countryatlas_error")
  local_fixture_http(list("/dataflow/OECD.SDD.NAD/" = "oecd-naag-structure.json"))
  expect_error(fetch_sdmx("oecd", "OECD.SDD.NAD,DSD_NAAG@DF_NAAG_I,1.0",
                          key = "A.B"), "5 dimensions")
  expect_error(fetch_sdmx("oecd", "OECD.SDD.NAD,DSD_NAAG@DF_NAAG_I,1.0",
                          key = "A.FRA...", countries = "DEU"),
               "both name countries")
  expect_warning(try(fetch_sdmx("oecd", "OECD.SDD.NAD,DSD_NAAG@DF_NAAG_I,1.0",
                                key = "A....", nonsense = 1), silent = TRUE),
                 class = "countryatlas_dots_unused")
})
