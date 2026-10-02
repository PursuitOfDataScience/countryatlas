test_that("the World Bank client returns what WDI::WDI() returned", {
  # The 3.0.0 path went through WDI::WDI(). On the same request, recorded the
  # same day, the package's own client must hand back the same keys, the
  # same columns and the same values, for three indicators over a panel.
  for (code in c("NY.GDP.PCAP.KD", "SP.POP.TOTL", "SP.DYN.LE00.IN")) {
    local_fixture_http(stats::setNames(list(paste0("wb-", code, ".json")),
                                       paste0("/indicator/", code)))
    new <- countryatlas:::wb_request(c(value = code), 2019, 2020)
    old <- readRDS(fixture_path(paste0("wdi-", code, ".rds")))
    expect_setequal(names(new), names(old))
    key <- function(d) paste(d$iso3c, d$year)
    expect_setequal(key(new), key(old))
    m <- match(key(old), key(new))
    expect_equal(new$value[m], old$value, info = code)
    expect_identical(new$iso2c[m], old$iso2c)
    expect_identical(new$country[m], old$country)
    expect_identical(attr(new, "wb_lastupdated"), attr(old, "lastupdated"))
  }
})

test_that("fetch_wdi() through the client keeps 3.0.0's shape and adds a record", {
  local_fixture_http(list("/indicator/NY.GDP.PCAP.KD" = "wb-NY.GDP.PCAP.KD.json",
                          "/indicator/SP.POP.TOTL" = "wb-SP.POP.TOTL.json"))
  x <- countryatlas:::fetch_wdi(c(gdp = "NY.GDP.PCAP.KD", pop = "SP.POP.TOTL"),
                                2019, 2020, cache = FALSE, parallel = FALSE)
  expect_true(all(c("iso2c", "iso3c", "country", "year", "gdp", "pop") %in%
                    names(x)))
  expect_equal(nrow(x), 16L)
  info <- source_info(x)
  expect_identical(info$column, c("gdp", "pop"))
  expect_identical(info$indicator, c("NY.GDP.PCAP.KD", "SP.POP.TOTL"))
  expect_identical(info$unit, c("constant 2015 US$", NA))
  expect_identical(info$vintage, c("2026-07", "2026-07"))
  expect_identical(info$licence, c("CC BY 4.0", "CC BY 4.0"))
  # No internal attribute leaks into the result.
  expect_null(attr(x, "wb_label"))
})

test_that("the client follows every page", {
  js <- jsonlite::fromJSON(paste(readLines(fixture_path("wb-SP.POP.TOTL.json"),
                                           warn = FALSE), collapse = ""),
                           simplifyVector = FALSE)
  rows <- js[[2]]
  page <- function(i) {
    meta <- js[[1]]; meta$page <- i; meta$pages <- 2L
    part <- if (i == 1L) rows[1:8] else rows[9:16]
    fixture_response(text = jsonlite::toJSON(list(meta, part), auto_unbox = TRUE,
                                             null = "null", digits = NA))
  }
  seen <- local_fixture_http(list("page=1" = function(u) page(1L),
                                  "page=2" = function(u) page(2L)))
  x <- countryatlas:::wb_request(c(pop = "SP.POP.TOTL"), 2019, 2020)
  expect_equal(nrow(x), 16L)
  expect_length(seen$urls, 2L)
  expect_true(all(grepl("per_page=5000", seen$urls, fixed = TRUE)))
})

test_that("an unknown indicator is named, and is not called an outage", {
  local_fixture_http(list("indicator" = function(u) fixture_response(text =
    '[{"message":[{"id":"120","key":"Invalid value","value":"The provided parameter value is not valid"}]}]')))
  expect_error(countryatlas:::wb_request(c(v = "NOT.A.CODE"), 2020, 2020),
               "does not recognise", class = "countryatlas_empty_fetch")
  expect_warning(countryatlas:::fetch_wdi(c(v = "NOT.A.CODE"), 2020, 2020,
                                          cache = FALSE),
                 class = "countryatlas_no_data")
})

test_that("an archived release is read, and its legacy codes are mapped", {
  local_fixture_http(list("/sources/57/" = "wb-archive-202407.json"))
  x <- countryatlas:::wb_request(c(gdp = "NY.GDP.PCAP.KD"), 2015, 2016,
                                 vintage = "2024-07")
  expect_identical(attr(x, "wb_vintage"), "202407")
  expect_true(all(c("FRA", "DEU", "JPN") %in% x$iso3c))
  # ADO, the World Bank's old code for Andorra, becomes AND, and where both
  # appear the row that was already ISO is the one kept.
  expect_false("ADO" %in% x$iso3c)
  expect_identical(sum(x$iso3c == "AND" & x$year == 2015, na.rm = TRUE), 1L)
  expect_identical(x$iso2c[x$iso3c == "FRA"][1], "FR")
})

test_that("a release that does not hold a series says so and names others", {
  xml <- '<?xml version="1.0" encoding="utf-8"?><wb:error xmlns:wb="http://www.worldbank.org"><wb:message id="160" key="Data not found.">The provided parameter value is not valid or data not found.</wb:message></wb:error>'
  local_fixture_http(list("/version/201907/" = function(u) fixture_response(text = xml),
                          "/sources/57/version" = "wb-vintages.json",
                          "/version/" = "wb-archive-202407.json"))
  e <- expect_error(countryatlas:::wb_request(c(p = "SP.POP.TOTL"), 2015, 2015,
                                              vintage = "201907"),
                    class = "countryatlas_vintage_missing")
  expect_match(conditionMessage(e), "2019-07", fixed = TRUE)
  w <- expect_warning(countryatlas:::fetch_wdi(c(p = "SP.POP.TOTL"), 2015, 2015,
                                               cache = FALSE, vintage = "2019-07"),
                      class = "countryatlas_vintage_missing")
  expect_match(conditionMessage(w), "nearest releases that hold it",
               fixed = TRUE)
})

test_that("a vintage is read the ways people write one", {
  skip_slow_on_cran()
  id <- countryatlas:::wb_vintage_id
  expect_identical(id("2024-07"), "202407")
  expect_identical(id("202407"), "202407")
  expect_identical(id(202407), "202407")
  expect_identical(id("2024 Jul"), "202407")
  expect_null(id(NULL))
  for (bad in list("2024-13", "July 2024", "24-07", NA, c("2024-07", "2023-07"),
                   TRUE)) {
    expect_error(id(bad), "vintage", class = "countryatlas_error")
  }
  expect_error(fetch_indicator("owid", "x", vintage = "2024-07"),
               "only to")
})

test_that("wdi_vintages() lists the archive's releases in order", {
  .st <- countryatlas:::.wdj_state
  old <- .st$wdi_vintages
  .st$wdi_vintages <- NULL
  withr::defer(.st$wdi_vintages <- old)
  local_fixture_http(list("/sources/57/version" = "wb-vintages.json"))
  v <- wdi_vintages()
  expect_identical(names(v), c("vintage", "id", "label"))
  expect_gte(nrow(v), 140L)
  expect_false(is.unsorted(v$id))
  expect_identical(v$vintage[v$id == "202407"], "2024-07")
  # Kept for the day: a second call makes no request.
  seen <- local_fixture_http(list())
  expect_identical(wdi_vintages(), v)
  expect_length(seen$urls, 0L)
})

test_that("compare_vintages() reports revisions between releases", {
  arch <- jsonlite::fromJSON(paste(readLines(fixture_path("wb-archive-202407.json"),
                                             warn = FALSE), collapse = ""),
                             simplifyVector = FALSE)
  # A second release, built from the first by revising France up 2% and
  # Germany down 20%, so the expected revisions are known exactly.
  rev <- arch
  rev$source$data <- lapply(arch$source$data, function(r) {
    iso <- r$variable[[which(vapply(r$variable, function(v) v$concept, "") ==
                               "Country")]]$id
    if (identical(iso, "FRA")) r$value <- r$value * 1.02
    if (identical(iso, "DEU")) r$value <- r$value * 0.8
    r
  })
  local_fixture_http(list(
    "/version/202407/" = "wb-archive-202407.json",
    "/version/202507/" = function(u) fixture_response(text = jsonlite::toJSON(
      rev, auto_unbox = TRUE, null = "null", digits = NA))))
  out <- compare_vintages("NY.GDP.PCAP.KD", c("2024-07", "2025-07"), year = 2015)
  expect_identical(names(out), c("iso3c", "country", "vintage", "value",
                                 "revision", "rel_revision"))
  fra <- out[out$iso3c == "FRA" & out$vintage == "2025-07", ]
  expect_equal(fra$rel_revision, 0.02, tolerance = 1e-12)
  deu <- out[out$iso3c == "DEU" & out$vintage == "2025-07", ]
  expect_equal(deu$rel_revision, -0.2, tolerance = 1e-12)
  s <- attr(out, "countryatlas_revisions")
  expect_identical(s$from, "2024-07")
  expect_identical(s$to, "2025-07")
  n <- s$n
  expect_equal(s$share_revised_1pct, 2 / n)
  expect_equal(s$share_revised_10pct, 1 / n)
  expect_error(compare_vintages("NY.GDP.PCAP.KD", "2024-07"), "two distinct")
  expect_error(compare_vintages(c("A", "B"), c("2024-07", "current")),
               "single code")
})
