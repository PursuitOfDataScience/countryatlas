test_that("dissolve_country expands historical entities to successors", {
  out <- dissolve_country("USSR")
  expect_equal(nrow(out), 15L)
  expect_true(all(c("RUS", "UKR", "EST") %in% out$iso3c))
  expect_true(all(out$historical == "Soviet Union"))
  expect_true(all(out$dissolved == 1991L))

  yug <- dissolve_country("Yugoslavia")
  expect_equal(nrow(yug), 7L)
  expect_true("XKX" %in% yug$iso3c)   # territory-based; documented
})

test_that("dissolve_country passes modern names through as single rows", {
  out <- dissolve_country(c("USSR", "France"))
  expect_equal(nrow(out), 16L)
  fra <- out[out$input == "France", ]
  expect_equal(fra$iso3c, "FRA")
  expect_true(is.na(fra$historical))
  expect_true(is.na(fra$dissolved))
})

test_that("dissolve_country matches aliases case-insensitively and warns on misses", {
  out <- dissolve_country(c("czechoslovakia", "German Democratic Republic"),
                          warn = FALSE)
  expect_equal(sum(out$historical == "Czechoslovakia", na.rm = TRUE), 2L)
  expect_true("DEU" %in% out$iso3c)

  expect_warning(res <- dissolve_country("Wakanda"),
                 class = "countryatlas_warning")
  expect_true(is.na(res$iso3c))
  expect_silent(dissolve_country("Wakanda", warn = FALSE))
})

test_that("'Sudan' alone is NOT treated as historical (current country)", {
  out <- dissolve_country("Sudan", warn = FALSE)
  expect_equal(nrow(out), 1L)
  expect_equal(out$iso3c, "SDN")
  expect_true(is.na(out$historical))
  # The explicitly historical spelling expands.
  expect_equal(nrow(dissolve_country("Sudan (former)")), 2L)
})

test_that("a non-breaking space does not turn the USSR into Russia", {
  nb <- intToUtf8(0xa0)
  x <- c(paste0("USSR", nb), paste0(nb, "Yugoslavia"), paste0("East", nb, "Germany"))
  d <- dissolve_country(x)
  expect_equal(sort(unique(d$historical)),
               c("East Germany", "Soviet Union", "Yugoslavia"))
  expect_equal(sum(d$input == x[1]), 15L)
  expect_true(all(check_country_match(x)$historical))
  expect_equal(country_timeline(x)$country,
               c("Soviet Union", "Yugoslavia", "East Germany"))
})
