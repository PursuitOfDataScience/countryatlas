test_that("source_info() reads and source_info<- writes the record", {
  skip_slow_on_cran()
  d <- data.frame(iso3c = c("FRA", "DEU"), rate = c(7.3, 3.1), n = 1:2)
  expect_identical(nrow(source_info(d)), 0L)
  expect_identical(names(source_info(d)), countryatlas:::SOURCE_INFO_COLS)
  source_info(d) <- data.frame(column = "rate", source = "My survey", unit = "%")
  info <- source_info(d)
  expect_identical(info$column, "rate")
  expect_identical(info$unit, "%")
  expect_true(is.na(info$vintage))
  # A second column adds to the record; describing one again replaces it.
  source_info(d) <- data.frame(column = "n", source = "Census")
  expect_identical(source_info(d)$column, c("rate", "n"))
  source_info(d) <- data.frame(column = "rate", source = "Revised survey")
  expect_identical(source_info(d)$source[source_info(d)$column == "rate"],
                   "Revised survey")
  source_info(d) <- NULL
  expect_identical(nrow(source_info(d)), 0L)
  expect_error(source_info(d) <- data.frame(column = "nope"), "nope")
  expect_error(source_info(d) <- data.frame(src = "x"), "column")
  expect_error(source_info(d) <- data.frame(column = "rate", colour = "red"),
               "colour")
  v <- 1:3
  expect_error(source_info(v) <- data.frame(column = "x"), "data frame")
})

test_that("which dplyr verbs keep the record is pinned", {
  # The record is an attribute. dplyr keeps a data frame's attributes through
  # dplyr_reconstruct() and drops them in summarise(); if dplyr changes that,
  # this test says so before a user finds a map that lost its source.
  d <- tibble::tibble(iso3c = c("FRA", "DEU", "JPN"), region = c("E", "E", "A"),
                      v = 1:3)
  source_info(d) <- data.frame(column = "v", source = "s")
  keeps <- function(x) nrow(source_info(x)) == 1L
  expect_true(keeps(dplyr::filter(d, v > 1)))
  expect_true(keeps(dplyr::mutate(d, w = v * 2)))
  expect_true(keeps(dplyr::arrange(d, v)))
  expect_true(keeps(dplyr::select(d, iso3c, v)))
  expect_true(keeps(dplyr::left_join(d, tibble::tibble(iso3c = "FRA", z = 1),
                                     by = "iso3c")))
  expect_false(keeps(dplyr::summarise(dplyr::group_by(d, region), v = sum(v))))
})

test_that("country_data() and attach_geometry() carry the record", {
  local_fixture_http(list("/indicator/NY.GDP.PCAP.KD" = "wb-NY.GDP.PCAP.KD.json"))
  cd <- country_data(2020, c(gdp = "NY.GDP.PCAP.KD"), cache = FALSE,
                     classify = character())
  info <- source_info(cd)
  expect_identical(info$column, "gdp")
  expect_identical(info$indicator, "NY.GDP.PCAP.KD")
  expect_identical(info$unit, "constant 2015 US$")
  g <- attach_geometry(cd, geometry = "polygon")
  expect_identical(source_info(g)$column, "gdp")
})

test_that("a map names its data's source in provenance and the caption", {
  skip_slow_on_cran()
  snap <- countryatlas::world_snapshot$countries
  source_info(snap) <- data.frame(
    column = "gdp_per_capita", source = "wdi", indicator = "NY.GDP.PCAP.KD",
    unit = "constant 2015 US$", vintage = "2026-07", fetched_at = "2026-10-01")
  g <- attach_geometry(snap, geometry = "polygon")
  p <- world_map(g, gdp_per_capita, footnote = "auto")
  prov <- map_provenance(p)
  expect_identical(prov$sources[[1]]$indicator, "NY.GDP.PCAP.KD")
  out <- cli::ansi_strip(paste(utils::capture.output(print(prov), type = "message"),
                               collapse = " "))
  expect_match(out, "World Bank WDI NY.GDP.PCAP.KD (constant 2015 US$), release 2026-07, fetched 2026-10-01",
               fixed = TRUE)
  expect_match(gg_caption_of(p), "Source: World Bank WDI, release 2026-07.",
               fixed = TRUE)
  # No record, no source line: the caption is the coverage line alone.
  bare <- countryatlas::world_snapshot$countries
  source_info(bare) <- NULL
  p0 <- world_map(attach_geometry(bare, geometry = "polygon"),
                  gdp_per_capita, footnote = "auto")
  expect_false(grepl("Source:", gg_caption_of(p0), fixed = TRUE))
  expect_identical(nrow(map_provenance(p0)$sources[[1]]), 0L)
  # The bundled snapshot carries its own record, so its map names its source.
  ps <- world_map(attach_geometry(countryatlas::world_snapshot$countries,
                                  geometry = "polygon"),
                  gdp_per_capita, footnote = "auto")
  expect_match(gg_caption_of(ps), "Source: World Bank WDI", fixed = TRUE)
})
