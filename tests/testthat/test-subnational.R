# --- subnational ----------------------------------------------------------------------

test_that("standardize_subnational passes ISO 3166-2 codes through", {
  skip_slow_on_cran()
  d <- data.frame(region = c("DE-BY", "DE-HE", "Nowhere at all"), v = 1:3)
  out <- suppressWarnings(standardize_subnational(d, region, country = "Germany"))
  expect_true(all(c("iso3c", "iso_3166_2") %in% names(out)))
  expect_equal(out$iso3c, rep("DEU", 3))
  expect_equal(out$iso_3166_2[1:2], c("DE-BY", "DE-HE"))
  # Never a guess: an unresolvable region is NA.
  expect_true(is.na(out$iso_3166_2[3]))
})

test_that("standardize_subnational takes country as a column or a literal", {
  d <- data.frame(region = c("DE-BY", "FR-ARA"),
                  cty = c("Germany", "France"), v = 1:2)
  out <- suppressWarnings(standardize_subnational(d, region, country = cty))
  expect_equal(out$iso3c, c("DEU", "FRA"))
})

test_that("nuts_geometry validates the vintage before reaching the network", {
  skip_if_not_installed("giscoR")
  expect_error(nuts_geometry(year = 1999), "NUTS vintage")
  expect_error(nuts_geometry(level = 9), "level")
})

test_that("subnational_map reports missing arguments and columns, not internals", {
  expect_error(subnational_map(NULL), "`fill` is required")
  expect_error(subnational_map(data.frame(geo = "DE1", v = 1), nope),
               "not found in `data`")
})

test_that("subnational_map notices regions that match no geometry", {
  # The join keeps the geometry and discards unmatched data, so a caller whose
  # codes come from a different NUTS vintage lost those rows silently -- only a
  # *total* wipe-out was reported, though that error names the vintage problem
  # exactly. The counting is split out so it needs no GISCO round-trip.
  u <- countryatlas:::unmatched_keys
  expect_length(u(c("DE1", "DE2"), c("DE1", "DE2", "DE3")), 0L)
  expect_setequal(u(c("DE1", "XX9", "YY8"), c("DE1", "DE2")), c("XX9", "YY8"))
  expect_length(u(c("DE1", NA), "DE1"), 0L)          # NA is not a key
  expect_length(u(c("XX9", "XX9"), "DE1"), 1L)       # reported once
  expect_length(u(character(0), "DE1"), 0L)
})

test_that("standardize_subnational says when it has no usable crosswalk", {
  # It looks for geo_name/name/region_name in regions::nuts_lau_2019 or
  # all_valid_nuts_codes. regions 0.1.8 exposes neither, so the lookup is
  # skipped -- silently, leaving the caller with "did not resolve" and a hint
  # about European coverage that was never consulted.
  # Structural for the notice, behavioural for the result: the note is
  # `.frequency = "once"`, so whether it fires *here* depends on whether an
  # earlier test tripped it first. The package tests its one-shot notices the
  # same way.
  # The block lives in the internal helper, not the exported wrapper.
  src <- paste(deparse(countryatlas:::subnational_lookup), collapse = " ")
  expect_match(src, "no name-to-code crosswalk", fixed = TRUE)
  expect_match(src, "subnational-no-crosswalk", fixed = TRUE)

  # The condition that makes the note fire: neither candidate dataset in the
  # installed `regions` exposes a name column the lookup recognises, so the
  # crosswalk is skipped rather than consulted.
  skip_if_not_installed("regions")
  cand <- c("geo_name", "name", "region_name")
  cw <- tryCatch(regions::nuts_lau_2019, error = function(e) NULL)
  skip_if(is.null(cw), "regions::nuts_lau_2019 unavailable")
  expect_false(any(cand %in% names(cw)))

  # And the documented promise holds either way: a code passes through, a name
  # gets NA rather than a guess from a different code system.
  d <- data.frame(reg = c("Bayern", "DE-BY"), ctry = "Germany")
  out <- suppressMessages(suppressWarnings(
    standardize_subnational(d, reg, ctry)))
  expect_equal(out$iso_3166_2, c(NA, "DE-BY"))
})

test_that("an unreachable or misshapen GISCO response is named", {
  skip_slow_on_cran()
  # giscoR answers a failed download with NULL rather than an error, the same
  # shape fetch_owid() guards for owidR. Unguarded it reached sf as "no
  # applicable method for 'st_as_sf' applied to an object of class NULL"; a
  # response without NUTS_ID gave base R's "replacement has 0 rows".
  skip_if_not_installed("giscoR")
  skip_if_not_installed("sf")
  mk <- function(ids) {
    if (!length(ids)) {
      return(sf::st_sf(NUTS_ID = character(0), NAME_LATN = character(0),
                       LEVL_CODE = integer(0),
                       geometry = sf::st_sfc(crs = 4326)))
    }
    pts <- sf::st_sfc(lapply(seq_along(ids),
                             function(i) sf::st_point(c(i, i))), crs = 4326)
    sf::st_sf(NUTS_ID = ids, NAME_LATN = paste0("R", seq_along(ids)),
              LEVL_CODE = 2L, geometry = pts)
  }
  ret <- NULL
  local_mocked_bindings(gisco_get_nuts = function(...) ret, .package = "giscoR")

  ret <- mk(c("FR10", "DE21", "IT11"))
  got <- suppressWarnings(nuts_geometry(level = 2))
  expect_s3_class(got, "sf")
  expect_true(all(c("nuts_id", "iso3c") %in% names(got)))

  ret <- NULL
  expect_error(nuts_geometry(level = 2), class = "countryatlas_no_nuts")
  ret <- mk(character(0))
  expect_error(nuts_geometry(level = 2), class = "countryatlas_no_nuts")

  ret <- mk(c("FR10", "DE21"))
  names(ret)[names(ret) == "NUTS_ID"] <- "ID"
  expect_error(nuts_geometry(level = 2), class = "countryatlas_bad_response")
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    nuts_geometry(level = 2), error = identity))), "no NUTS_ID column",
    fixed = TRUE)
})

test_that("subnational_map()'s projection notice reads as text", {
  skip_if_not_installed("sf")
  sq <- function(x0, y0) sf::st_polygon(list(rbind(
    c(x0, y0), c(x0 + 1, y0), c(x0 + 1, y0 + 1), c(x0, y0 + 1), c(x0, y0))))
  fake <- function(level = 2, year = 2021, countries = NULL,
                   resolution = "60", projection = NULL) {
    sf::st_sf(nuts_id = c("DE21", "DE22"), iso3c = "DEU", name = c("A", "B"),
              level = 2L, geometry = sf::st_sfc(sq(10, 48), sq(11, 48),
                                                crs = 4326))
  }
  local_mocked_bindings(nuts_geometry = fake, .package = "countryatlas")
  d <- data.frame(nuts_id = c("DE21", "DE22"), value = c(1, 2))
  w <- tryCatch(subnational_map(d, value, projection = "mollweide"),
                countryatlas_projection_ignored = function(w) conditionMessage(w))
  expect_no_match(w, "{.fn", fixed = TRUE)
  expect_no_match(w, 'geometry = "sf"', fixed = TRUE)
  expect_silent(subnational_map(d, value, projection = "equal_earth"))
})

test_that("standardize_subnational() normalises an ISO 3166-2 code's case and padding", {
  d <- data.frame(region = c("DE-BY", "de-by", "DE-BY ", "\u00a0DE-HE", "US-CA"),
                  value = 1:5)
  out <- suppressWarnings(suppressMessages(
    standardize_subnational(d, region, country = "Germany")))
  expect_equal(out$iso_3166_2, c("DE-BY", "DE-BY", "DE-BY", "DE-HE", NA))
})
