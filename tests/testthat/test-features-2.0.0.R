# Tests for functionality added in 2.0.0.

test_that("growth_rate computes yoy and cagr per country", {
  df <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c(100, 110, 121))
  g <- growth_rate(df, gdp)
  expect_equal(g$gdp_growth, c(NA, 0.1, 0.1))
  cg <- growth_rate(df, gdp, type = "cagr")
  expect_equal(round(cg$gdp_growth[3], 4), 0.1)
})

test_that("index_to rebases each country to the base year", {
  df <- data.frame(iso3c = "USA", year = 2000:2002, gdp = c(50, 55, 60))
  out <- index_to(df, gdp, base_year = 2000)
  expect_equal(out$gdp_index, c(100, 110, 120))
})

test_that("share_of_world sums to one within a year", {
  df <- data.frame(iso3c = c("USA", "CHN"), co2 = c(5, 15))
  out <- share_of_world(df, co2)
  expect_equal(out$co2_share, c(0.25, 0.75))
})

test_that("country_join_all reduce-joins many messy tables", {
  a <- data.frame(country = c("Czechia", "South Korea"), gdp = c(1, 2))
  b <- data.frame(country = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
  d <- data.frame(country = c("Czechia", "Korea"), area = c(79, 100))
  out <- country_join_all(list(a, b, d), by = "country")
  expect_true(all(c("gdp", "pop", "area", "iso3c") %in% names(out)))
  expect_equal(nrow(out), 2)
  expect_equal(out$area[out$iso3c == "CZE"], 79)
})

test_that("repair_country_names fixes confident misses", {
  # Threshold loosened so the test holds with either stringdist or the
  # base-R adist fallback.
  out <- repair_country_names(c("United States", "Brzil", "Germny"),
                              threshold = 0.3, verbose = FALSE)
  expect_equal(as.character(out), c("United States", "Brazil", "Germany"))
  expect_s3_class(attr(out, "repairs"), "tbl_df")
  expect_equal(nrow(attr(out, "repairs")), 2L)
})

test_that("convert_country routes overrides through iso3c for all destinations", {
  expect_equal(convert_country("Canary Islands", to = "iso3c"), "ESP")
  expect_equal(convert_country("Canary Islands", to = "continent"), "Europe")
  expect_equal(convert_country(c("Japan", "Brazil"), to = "flag"),
               c("\U0001F1EF\U0001F1F5", "\U0001F1E7\U0001F1F7"))
  # Kosovo's XKX has NO row at all in countrycode::codelist, so routing every
  # destination through the iso3c round-trip is NA for everything, even ones
  # (flag/region/country) that 1.0.0 already got right via direct name
  # matching -- recover those from the original name rather than regress
  # them. iso2c/continent never resolved even via direct name matching;
  # those come from the same curated fallback standardize_country() uses.
  expect_equal(convert_country("Kosovo", to = "continent"), "Europe")
  expect_equal(convert_country("Kosovo", to = "region"), "Europe & Central Asia")
  expect_equal(convert_country("Kosovo", to = "iso2c"), "XK")
  expect_equal(convert_country("Kosovo", to = "flag"), "\U0001F1FD\U0001F1F0")
  expect_equal(convert_country("Kosovo", to = "country"), "Kosovo")
  # Genuinely missing data (countrycode has no currency for Kosovo) stays NA,
  # not silently invented -- both before and after this fix.
  expect_true(is.na(convert_country("Kosovo", to = "currency")))
  # from = "iso3c" has no name to recover from, so everything it resolves for
  # XKX comes from the curated fallback table -- which covers name and flag
  # too, so country_borders() / locate_country(add = "country") don't hand
  # back NA for Kosovo.
  expect_equal(convert_country("XKX", to = "continent", from = "iso3c"), "Europe")
  expect_equal(convert_country("XKX", to = "region", from = "iso3c"),
               "Europe & Central Asia")
  expect_equal(convert_country("XKX", to = "iso2c", from = "iso3c"), "XK")
  expect_equal(convert_country("XKX", to = "country", from = "iso3c"), "Kosovo")
  expect_equal(convert_country("XKX", to = "flag", from = "iso3c"),
               "\U0001F1FD\U0001F1F0")
  # Genuinely missing data still stays NA rather than being invented.
  expect_true(is.na(convert_country("XKX", to = "currency", from = "iso3c",
                                    warn = FALSE)))
})

test_that("convert_country(warn = TRUE) actually warns about misses", {
  # It used to be a no-op: every internal countrycode() call is wrapped in
  # suppressWarnings(), so `warn` never reached the user.
  expect_warning(convert_country("Wakanda", to = "continent"),
                 "could not be matched")
  expect_warning(convert_country("Wakanda"), "could not be matched")
  expect_warning(convert_country("ZZ", to = "country", from = "iso2c"),
                 "could not be matched")
  expect_silent(convert_country("Wakanda", to = "continent", warn = FALSE))
  expect_silent(convert_country(c("France", "Japan"), to = "continent"))
  # NA in, NA out is not a matching failure.
  expect_silent(convert_country(c(NA, "France"), to = "continent"))
  # Neither is a recognised country with no value for that destination:
  # countrycode simply has no currency for Kosovo.
  expect_silent(convert_country("Kosovo", to = "currency"))
})

test_that("new country groups are present and correctly sized", {
  expect_equal(nrow(country_groups("GCC")), 6)
  expect_equal(nrow(country_groups("Nordic")), 5)
  expect_equal(nrow(country_groups("Visegrad")), 4)
  expect_true("BRA" %in% country_groups("Mercosur")$iso3c)
  # Existing groups unchanged.
  expect_equal(nrow(country_groups("EU")), 27)
})

test_that("country_overrides is an alias of wdj_overrides", {
  # wdj_overrides()'s deprecation note is .frequency = "once", so whether it
  # fires here depends on which test file ran first. Assert the alias, and let
  # test-reference.R assert that the replacement itself stays silent.
  expect_identical(country_overrides(), suppressWarnings(wdj_overrides()))
  expect_equal(unname(country_overrides(c(Somaliland = "SOM"))[["Somaliland"]]),
               "SOM")
})

test_that("plate_carree is equirectangular and new projections build", {
  expect_match(countryatlas:::wdj_crs("plate_carree"), "proj=eqc")
  expect_false(grepl("proj=longlat", countryatlas:::wdj_crs("plate_carree")))
  expect_match(countryatlas:::wdj_crs("winkel_tripel"), "proj=wintri")
  expect_match(countryatlas:::wdj_crs("orthographic", lat0 = 30), "lat_0=30")
})

test_that("globe_map polygon backend constructs without sf", {
  skip_if_not_installed("maps")
  skip_if_not_installed("mapproj")
  p <- globe_map(world_snapshot$countries, continent, backend = "polygon",
                 style = "categorical")
  expect_s3_class(p, "ggplot")
  expect_s3_class(p$coordinates, "CoordMap")
})

test_that("spin_globe needs a gif encoder", {
  # Without gifski/magick it should fail fast, before rendering any frame.
  skip_if(requireNamespace("gifski", quietly = TRUE) ||
            requireNamespace("magick", quietly = TRUE))
  # Pinned to the encoder gate: unpinned, a mistyped column or any other
  # early failure would satisfy this, and the block only runs when both
  # encoders are absent.
  expect_error(
    spin_globe(world_snapshot$countries, continent, backend = "polygon",
               n_frames = 2L),
    class = "rlib_error_package_not_found"
  )
  expect_error(
    spin_globe(world_snapshot$countries, continent, backend = "polygon",
               n_frames = 2L),
    "gifski"
  )
})

test_that("polygon centroids are one antimeridian-safe row per iso3c", {
  skip_if_not_installed("maps")
  cent <- world_geometry("centroids", geometry = "polygon")
  expect_equal(anyDuplicated(cent$iso3c), 0L)
  # USA centroid sits on the contiguous landmass, not pulled to ~0 by Alaska.
  usa_lon <- cent$centroid_lon[cent$iso3c == "USA"]
  expect_lt(usa_lon, -60)
})

test_that("distance_between computes symmetric great-circle distances", {
  d1 <- distance_between("France", "Germany")
  d2 <- distance_between("Germany", "France")
  expect_equal(d1, d2)
  expect_gt(d1, 0)
  expect_lt(d1, 2000)
  expect_warning(w <- distance_between("Wakanda", "France"),
                 "did not resolve to a country")
  expect_true(is.na(w))
  # France is closer to Germany than to Australia.
  expect_lt(distance_between("France", "Germany"),
            distance_between("France", "Australia"))
  # Recycles a length-1 argument against a longer one, the usual R way.
  expect_length(distance_between("USA", c("Canada", "Mexico", "France")), 3)
})

test_that("country_borders and neighbors need sf", {
  skip_if(requireNamespace("sf", quietly = TRUE))
  # Pinned to the package gate itself, not merely "it errored". With no
  # pattern this accepted any condition at all -- a typo in the fixture, or
  # an argument error raised before the gate was reached -- and this block
  # only runs when the package is *absent*, which is the one configuration
  # nobody watches. The already-pinned ggsql block below documents the same
  # hazard. need_pkg() -> rlang::check_installed() raises
  # "rlib_error_package_not_found".
  expect_error(country_borders(), class = "rlib_error_package_not_found")
  expect_error(country_borders(), "sf")
  # neighbors() resolves the code first and only then reaches country_borders(),
  # so this also pins that the gate is what stops it -- not name resolution.
  expect_error(neighbors("FRA", origin = "iso3c"), class = "rlib_error_package_not_found")
  expect_error(neighbors("FRA", origin = "iso3c"), "sf")
})

test_that("country_borders finds real neighbours (needs sf)", {
  skip_if_no_sf_geometry()
  b <- country_borders()
  expect_true(all(c("iso3c_a", "country_a", "iso3c_b", "country_b") %in% names(b)))
  expect_false(any(b$iso3c_a == b$iso3c_b))
  key <- paste(pmin(b$iso3c_a, b$iso3c_b), pmax(b$iso3c_a, b$iso3c_b))
  expect_equal(anyDuplicated(key), 0L)
  fra_deu <- (b$iso3c_a == "FRA" & b$iso3c_b == "DEU") |
    (b$iso3c_a == "DEU" & b$iso3c_b == "FRA")
  expect_true(any(fra_deu))
})

test_that("neighbors looks up a country's borders (needs sf)", {
  skip_if_no_sf_geometry()
  fra <- neighbors("France")
  expect_true(all(fra$iso3c == "FRA"))
  expect_true("DEU" %in% fra$neighbor)
  # Japan is an island nation with no land border.
  expect_equal(nrow(neighbors("Japan")), 0L)
})

# country_borders() keeps one direction of each pair and asserts in a comment
# that "a country never borders itself". neighbors() then rebuilds both
# directions. Those are invariants a geometry or Natural Earth change could
# quietly break, so pin them rather than trusting the comment.

test_that("the border adjacency is irreflexive and de-duplicated", {
  skip_if_no_sf_geometry()
  b <- country_borders()
  expect_gt(nrow(b), 100L)
  expect_equal(sum(b$iso3c_a == b$iso3c_b), 0L)        # no country borders itself
  # One direction per pair, not both.
  key <- paste(pmin(b$iso3c_a, b$iso3c_b), pmax(b$iso3c_a, b$iso3c_b))
  expect_equal(sum(duplicated(key)), 0L)
  expect_false(anyNA(c(b$iso3c_a, b$iso3c_b)))
})

test_that("neighbors() builds the adjacency once, however many countries", {
  # ?neighbors tells the reader to pass a vector rather than loop, because every
  # call rebuilds the whole world's st_touches() adjacency. Pin the fact that
  # claim rests on -- one country_borders() call per neighbors() call, not one
  # per country -- rather than a wall-clock assertion, which would be flaky.
  # Measured cost of getting this wrong: 0.43s for one country, 0.37s for 153,
  # so looping over them would be ~66s, about 177x a single vectorised call.
  skip_if_no_sf_geometry()
  calls <- 0L
  fake <- function(scale = "small", region = NULL) {
    calls <<- calls + 1L
    tibble::tibble(iso3c_a = c("FRA", "FRA", "DEU"),
                   country_a = c("France", "France", "Germany"),
                   iso3c_b = c("DEU", "ESP", "POL"),
                   country_b = c("Germany", "Spain", "Poland"))
  }
  testthat::local_mocked_bindings(country_borders = fake)

  calls <- 0L
  one <- neighbors("FRA", origin = "iso3c")
  expect_identical(calls, 1L)

  calls <- 0L
  many <- neighbors(c("FRA", "DEU", "ESP", "POL"), origin = "iso3c")
  expect_identical(calls, 1L)

  # And the vectorised answer really is the union of the individual ones.
  expect_setequal(one$neighbor, c("DEU", "ESP"))
  expect_setequal(many$neighbor[many$iso3c == "FRA"], c("DEU", "ESP"))
  expect_gt(nrow(many), nrow(one))
})

test_that("neighbors() is symmetric even though country_borders() is not", {
  skip_if_no_sf_geometry()
  # neighbors() returns a tibble (iso3c, neighbor, neighbor_country) -- pin the
  # shape too, since the symmetry check depends on reading the right column.
  nb <- neighbors("France")
  expect_s3_class(nb, "tbl_df")
  expect_named(nb, c("iso3c", "neighbor", "neighbor_country"))

  b <- country_borders()
  codes <- sort(unique(c(b$iso3c_a, b$iso3c_b)))
  # One vectorised call, not one per country. neighbors() recomputes the whole
  # world's st_touches() adjacency on every call, and asking per country -- then
  # again per neighbour, to check the reverse edge -- meant ~465 rebuilds and 292
  # seconds, four fifths of the entire test suite. The function is vectorised, so
  # a single call does exactly the same work and exercises the same code.
  all_nb <- neighbors(codes, origin = "iso3c")
  expect_setequal(unique(all_nb$iso3c), codes)

  # No self-border, no repeated pair -- reported as the offending rows, so a
  # failure still names the country rather than just a count.
  expect_equal(all_nb$iso3c[all_nb$iso3c == all_nb$neighbor], character(0))
  dup <- all_nb[duplicated(all_nb[, c("iso3c", "neighbor")]), ]
  expect_equal(nrow(dup), 0L)

  # Symmetry: every (a, b) edge has its (b, a) twin.
  fwd <- paste(all_nb$iso3c, all_nb$neighbor)
  rev <- paste(all_nb$neighbor, all_nb$iso3c)
  expect_equal(setdiff(fwd, rev), character(0))

  nbr <- function(a) all_nb$neighbor[all_nb$iso3c == a]
  # A land border across an overseas territory is real, not a bug: French
  # Guiana borders Brazil and Suriname.
  expect_true(all(c("BRA", "SUR") %in% nbr("FRA")))
  # Vectorised input returns the union, keyed by the country asked for, and
  # agrees with the same lookup by name.
  v <- neighbors(c("France", "Germany"), origin = "country.name")
  expect_equal(nrow(v), length(nbr("FRA")) + length(nbr("DEU")))
  expect_setequal(unique(v$iso3c), c("FRA", "DEU"))
  expect_setequal(v$neighbor[v$iso3c == "FRA"], nbr("FRA"))
})
