# Natural Earth worldviews (R/worldviews.R), on a tiny recorded fixture.

local_worldview_fixture <- function(env = parent.frame()) {
  cache <- withr::local_tempdir(.local_envir = env)
  withr::local_envvar(R_USER_CACHE_DIR = cache, .local_envir = env)
  local_mocked_bindings(
    worldview_download = function(suffix, dest) {
      file.copy(test_path("fixtures", "worldview_ind.zip"), dest, overwrite = TRUE)
      dest
    },
    .env = env)
  rm(list = ls(countryatlas:::.world_sf_cache, all.names = TRUE),
     envir = countryatlas:::.world_sf_cache)
  withr::defer(rm(list = ls(countryatlas:::.world_sf_cache, all.names = TRUE),
                  envir = countryatlas:::.world_sf_cache), envir = env)
}

test_that("a worldview draws that country's file, keyed on iso3c", {
  skip_slow_on_cran()
  skip_if_not_installed("sf")
  skip_if_not_installed("withr")
  local_worldview_fixture()
  w <- world_geometry("countries", geometry = "sf", worldview = "ind",
                      projection = "equal_earth")
  expect_s3_class(w, "sf")
  # The ISO_A3 column, then the name for a feature without one (Nepal is -99
  # in the fixture).
  expect_setequal(w$iso3c, c("IND", "PAK", "NPL"))
  d <- data.frame(iso3c = c("IND", "PAK"), v = 1:2)
  g <- attach_geometry(d, geometry = "sf", worldview = "IND")
  expect_identical(attr(g, "countryatlas_worldview"), "IND")
  expect_identical(map_provenance(world_map(g, v))$worldview, "IND")
})

test_that("a worldview is checked, and needs the sf backend", {
  expect_error(world_geometry(geometry = "sf", worldview = "XXX"),
               class = "countryatlas_unknown_worldview")
  expect_error(world_geometry(geometry = "polygon", worldview = "IND"),
               "geometry = \"sf\"")
  expect_error(countryatlas:::check_worldview(c("IND", "PAK")), "single code")
  # Natural Earth's two codes that are not ISO's.
  expect_identical(unname(countryatlas:::WORLDVIEWS[c("BGD", "NPL")]),
                   c("bdg", "nep"))
})

test_that("dispute_policy() can set a worldview, and then de_jure stops warning", {
  skip_if_not_installed("withr")
  withr::local_options(countryatlas.dispute_policy = NULL,
                       countryatlas.worldview = NULL)
  expect_warning(dispute_policy("de_jure"), "still de facto")
  expect_no_warning(dispute_policy("de_jure", worldview = "IND"))
  expect_identical(getOption("countryatlas.worldview"), "IND")
  # The session worldview reaches the sf backend...
  skip_if_not_installed("sf")
  local_worldview_fixture()
  g <- attach_geometry(data.frame(iso3c = "IND", v = 1), geometry = "sf")
  expect_identical(attr(g, "countryatlas_worldview"), "IND")
  # ...and the polygon backend says once that it draws the default view.
  expect_message(attach_geometry(data.frame(iso3c = "IND", v = 1)),
                 "polygon backend draws")
  # NA clears it.
  dispute_policy(worldview = NA)
  expect_null(getOption("countryatlas.worldview"))
})
