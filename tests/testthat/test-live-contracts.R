# One small real request per provider, run by the weekly live-contracts
# workflow (COUNTRYATLAS_LIVE=true) and nowhere else. The rest of the suite
# replays recorded responses; this is what notices that a provider has changed
# under them. Strict mode makes a failed request an error, so a dead endpoint
# fails here instead of degrading to an empty frame.
skip_if_not_live <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_not(identical(Sys.getenv("COUNTRYATLAS_LIVE"), "true"),
                        "set COUNTRYATLAS_LIVE=true for the live contracts")
}

test_that("live: the World Bank's current release", {
  skip_if_not_live()
  withr::local_options(countryatlas.strict = TRUE)
  x <- countryatlas:::fetch_wdi(c(gdp = "NY.GDP.PCAP.KD"), 2019, 2020,
                                cache = FALSE, parallel = FALSE)
  expect_gt(sum(!is.na(x$gdp)), 300L)
  info <- source_info(x)
  expect_match(info$vintage, "^[0-9]{4}-[0-9]{2}$")
  expect_identical(info$unit, "constant 2015 US$")
})

test_that("live: the World Bank's archived releases", {
  skip_if_not_live()
  withr::local_options(countryatlas.strict = TRUE)
  v <- wdi_vintages()
  expect_gte(nrow(v), 142L)
  x <- countryatlas:::fetch_wdi(c(gdp = "NY.GDP.PCAP.KD"), 2015, 2015,
                                cache = FALSE, vintage = "2024-07")
  expect_gt(sum(!is.na(x$gdp)), 150L)
})

test_that("live: Our World in Data's Chart API", {
  skip_if_not_live()
  withr::local_options(countryatlas.strict = TRUE)
  x <- fetch_owid(c(le = "life-expectancy"), years = 2020)
  expect_gt(nrow(x), 150L)
  expect_identical(source_info(x)$unit, "years")
})

test_that("live: the SDMX services", {
  skip_if_not_live()
  withr::local_options(countryatlas.strict = TRUE)
  o <- fetch_oecd(c(g = "OECD.SDD.NAD,DSD_NAAG@DF_NAAG_I,1.0"),
                  countries = c("FRA", "DEU", "JPN"), years = 2020:2023,
                  key = "A..B1GQ_R_GR..")
  expect_identical(nrow(o), 12L)
  i <- fetch_indicator("imf", c(g = "IMF.RES,WEO,9.0.0"),
                       countries = c("FRA", "DEU"), years = 2021:2022,
                       key = ".NGDP_RPCH.A")
  expect_identical(nrow(i), 4L)
  l <- fetch_indicator("ilo", c(u = "ILO,DF_UNE_DEAP_SEX_AGE_RT,1.0"),
                       countries = c("FRA", "DEU"), years = 2020:2022,
                       key = ".A..SEX_T.AGE_YTHADULT_YGE15")
  expect_identical(nrow(l), 6L)
  e <- fetch_sdmx("eurostat", c(pop = "ESTAT,DEMO_PJAN,1.0"),
                  key = "A.NR.TOTAL.T.FR+DE", years = 2020:2021)
  expect_identical(nrow(e), 4L)
})

test_that("live: UN Comtrade, when a key is configured", {
  skip_if_not_live()
  skip_if_not_installed("comtradr")
  skip_if(!nzchar(Sys.getenv("COMTRADE_PRIMARY")), "no Comtrade key")
  withr::local_options(countryatlas.strict = TRUE)
  x <- fetch_comtrade(c(total = "TOTAL"), countries = "FRA", years = 2022)
  expect_gt(nrow(x), 0L)
})
