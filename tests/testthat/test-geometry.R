test_that("distance_between computes great-circle distance (no sf needed)", {
  d <- distance_between("France", "Germany")
  expect_type(d, "double")
  expect_gt(d, 0)
  # Paris–Berlin ~ 878 km, centroids should be in that ballpark
  expect_gt(d, 500)
  expect_lt(d, 1500)
})

test_that("distance_between recycles vectors", {
  d <- distance_between("USA", c("Canada", "Mexico"))
  expect_length(d, 2)
  expect_true(all(d > 0))
})

test_that("distance_between resolves via iso3c", {
  d1 <- distance_between("France", "Germany")
  d2 <- distance_between("FRA", "DEU", origin = "iso3c")
  expect_equal(d1, d2)
})

test_that("distance_between returns NA for unknown countries", {
  d <- distance_between("France", "Atlantis")
  expect_true(is.na(d))
})

test_that("distance_between works on vectors of length 1 (no recycling)", {
  # Identical country -> zero distance
  d <- distance_between("France", "France")
  expect_true(abs(d) < 1e-9)
})

test_that("locate_country tags known capitals", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  out <- locate_country(lon = c(2.35, -74.0, 139.7), lat = c(48.85, 40.7, 35.7))
  # Paris, New York, Tokyo
  expect_equal(out$iso3c, c("FRA", "USA", "JPN"))
  expect_equal(out$country, c("France", "United States", "Japan"))
})

test_that("locate_country returns NA for open ocean", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  out <- locate_country(lon = -30, lat = -30)   # open Atlantic
  expect_true(is.na(out$iso3c))
})

test_that("locate_country supports extra attributes", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  out <- locate_country(lon = 2.35, lat = 48.85, add = c("country", "continent"))
  expect_equal(out$country, "France")
  expect_equal(out$continent, "Europe")
})

test_that("locate_country errors on mismatched lon/lat lengths", {
  skip_if_not_installed("sf")
  expect_error(locate_country(lon = 1:2, lat = 1), class = "countryatlas_error")
})

test_that("locate_country snaps coastal points but leaves open ocean NA", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  # New York sits ~0.5 km outside the coarse 110m US coastline: the default
  # tolerance snaps it to the US, strict mode (tolerance_km = 0) does not.
  expect_equal(locate_country(lon = -74.0, lat = 40.7)$iso3c, "USA")
  expect_true(is.na(locate_country(lon = -74.0, lat = 40.7, tolerance_km = 0)$iso3c))
  # Open ocean is hundreds of km from land, so it stays NA even with snapping.
  expect_true(is.na(locate_country(lon = -30, lat = -30)$iso3c))
})

test_that("country_borders returns a tidy edge list", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  edges <- country_borders()
  expect_s3_class(edges, "tbl_df")
  expect_true(all(c("iso3c_a", "country_a", "iso3c_b", "country_b") %in% names(edges)))
  # France borders Germany
  fra_deu <- dplyr::filter(
    edges,
    (.data$iso3c_a == "FRA" & .data$iso3c_b == "DEU") |
    (.data$iso3c_a == "DEU" & .data$iso3c_b == "FRA")
  )
  expect_equal(nrow(fra_deu), 1)
})

test_that("country_borders never lists a country bordering itself", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  edges <- country_borders()
  expect_false(any(edges$iso3c_a == edges$iso3c_b))
})

test_that("neighbors lists a country's bordering countries", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  nbr <- neighbors("France")
  expect_s3_class(nbr, "tbl_df")
  expect_true("DEU" %in% nbr$neighbor)
  expect_true("ESP" %in% nbr$neighbor)
})

test_that("neighbors returns zero rows for islands", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  nbr <- neighbors("Japan")
  expect_equal(nrow(nbr), 0)
})

test_that("locate_country names Kosovo (XKX has no countrycode row)", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  out <- locate_country(lon = 20.9, lat = 42.6, add = c("country", "continent"))
  expect_equal(out$iso3c, "XKX")
  expect_equal(out$country, "Kosovo")
  expect_equal(out$continent, "Europe")
})

test_that("country_borders names every endpoint, Kosovo included", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  edges <- country_borders()
  expect_false(anyNA(edges$country_a))
  expect_false(anyNA(edges$country_b))
  xkx <- edges[edges$iso3c_a == "XKX" | edges$iso3c_b == "XKX", ]
  expect_gt(nrow(xkx), 0)
})

test_that("world_geometry('coastline') works in every projection", {
  # Two Natural Earth rings are invalid once projected, and st_union() (unlike
  # the predicates) refuses them outright: the coastline used to error with
  # "TopologyException: side location conflict" in all but plate_carree.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  for (proj in c("equal_earth", "robinson", "mollweide", "mercator",
                 "plate_carree", "orthographic")) {
    cl <- world_geometry("coastline", geometry = "sf", projection = proj)
    expect_s3_class(cl, "sfc_MULTILINESTRING")
    expect_length(cl, 1)
  }
})

test_that("world_geometry accepts a bounding-box region on the sf backend", {
  # Regression: st_crop() under the strict S2 engine rejected Natural Earth's
  # self-intersecting rings, so region = c(xmin, ymin, xmax, ymax) errored.
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  eur <- world_geometry("countries", geometry = "sf",
                        region = c(-10, 35, 30, 60))
  expect_s3_class(eur, "sf")
  expect_gt(nrow(eur), 10)
  expect_lt(nrow(eur), 100)
  expect_true("FRA" %in% eur$iso3c)
  expect_false("AUS" %in% eur$iso3c)
})

test_that("polygon_centroids returns one centroid per iso3c", {
  # Bug 3.3: PRT / ESP / BES must each produce ONE row, not multiple.
  skip_if_not_installed("maps")
  poly <- countryatlas:::world_polygons()
  cent <- countryatlas:::polygon_centroids(poly)
  # Every iso3c appears exactly once
  expect_equal(anyDuplicated(cent$iso3c), 0)
  # Known multi-piece countries must have exactly one centroid row
  expect_equal(nrow(dplyr::filter(cent, .data$iso3c == "PRT")), 1)
  expect_equal(nrow(dplyr::filter(cent, .data$iso3c == "ESP")), 1)
  expect_equal(nrow(dplyr::filter(cent, .data$iso3c == "BES")), 1)
})

test_that("attach_geometry threads custom overrides into geometry matching", {
  # Regression: world_data(overrides=) / attach_geometry(overrides=) were
  # accepted but silently ignored -- the geometry backend always matched with
  # the default override set. A custom set must now actually take effect.
  skip_if_not_installed("maps")
  poly <- attach_geometry(
    data.frame(iso3c = "ZZ1", value = 42),
    geometry = "polygon",
    overrides = wdj_overrides(c(Greenland = "ZZ1"))
  )
  # Greenland's polygons carry the custom code and join to the value...
  expect_true(any(poly$iso3c == "ZZ1" & poly$value == 42, na.rm = TRUE))
  # ...and are no longer matched to the default GRL.
  expect_false(any(poly$iso3c == "GRL", na.rm = TRUE))
  # The default path is unaffected (separate cache key): Greenland -> GRL.
  poly_def <- attach_geometry(data.frame(iso3c = "GRL", value = 7),
                              geometry = "polygon")
  expect_true(any(poly_def$iso3c == "GRL", na.rm = TRUE))
})
