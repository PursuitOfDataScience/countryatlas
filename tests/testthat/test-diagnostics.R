test_that("check_country_match reports matches and misses", {
  out <- check_country_match(c("USA", "Cote d'Ivoire", "Yugoslavia", "Wakanda"))
  expect_s3_class(out, "tbl_df")
  expect_equal(out$matched, c(TRUE, TRUE, FALSE, FALSE))
  expect_equal(out$iso3c[1:2], c("USA", "CIV"))
  expect_true(is.na(out$iso3c[4]))
})

test_that("check_country_match suggests near misses when stringdist available", {
  skip_if_not_installed("stringdist")
  out <- check_country_match("Germny")
  expect_false(out$matched)
  expect_equal(out$suggestion, "Germany")
})

test_that("audit_coverage summarises missingness", {
  cov <- audit_coverage(world_snapshot$countries)
  expect_s3_class(cov, "countryatlas_coverage")
  expect_true(all(c("unmatched", "na_rates", "by_group") %in% names(cov)))
  expect_true("gdp_per_capita" %in% cov$na_rates$indicator)
  expect_true(all(cov$na_rates$na_rate >= 0 & cov$na_rates$na_rate <= 1))
})

# repair_country_names() uses stringdist's Jaro-Winkler when available and a
# length-normalised edit distance otherwise, so its output depends on an
# optional package -- the same shape as the classInt bin-count bug. It is safe
# because of *where* the two metrics are used: check_country_match() picks the
# candidate, and only the accept/reject threshold differs. So the fallback can
# under-accept but can never choose a different country, whatever the threshold
# does. The metric-independence of the candidate selection is therefore the
# load-bearing property -- that is what the second test below pins, and
# perturbing the selection metric does fail it.

test_that("the adist fallback is a conservative subset of stringdist", {
  skip_if_not_installed("stringdist")
  set.seed(4)
  real <- sample(stats::na.omit(countryatlas::country_meta$country), 120)
  # One typo per name, cycling transposition / deletion / insertion.
  mut <- vapply(seq_along(real), function(i) {
    x <- real[i]; k <- nchar(x)
    if (k < 5) return(x)
    j <- sample(2:(k - 2), 1)
    switch(as.character(i %% 3),
      "0" = paste0(substr(x, 1, j - 1), substr(x, j + 1, j + 1),
                   substr(x, j, j), substr(x, j + 2, k)),
      "1" = paste0(substr(x, 1, j - 1), substr(x, j + 1, k)),
      paste0(substr(x, 1, j), "x", substr(x, j + 1, k)))
  }, character(1))

  with_sd <- as.character(suppressWarnings(
    repair_country_names(mut, verbose = FALSE)))
  without <- with_mocked_bindings(
    has_pkg = function(pkg) {
      if (identical(pkg, "stringdist")) FALSE
      else isTRUE(requireNamespace(pkg, quietly = TRUE))
    },
    as.character(suppressWarnings(repair_country_names(mut, verbose = FALSE))))

  fixed_sd <- with_sd != mut
  fixed_ad <- without != mut
  # The fallback repairs fewer names, never more.
  expect_lte(sum(fixed_ad), sum(fixed_sd))
  expect_equal(sum(fixed_ad & !fixed_sd), 0L)
  # And where both repair, they agree on the country.
  expect_equal(sum(fixed_sd & fixed_ad & with_sd != without), 0L)
  # Neither ever repairs to the *wrong* country.
  expect_equal(sum(fixed_sd & with_sd != real), 0L)
  expect_equal(sum(fixed_ad & without != real), 0L)
  # Both are actually useful, not just safe.
  expect_gt(sum(fixed_ad), 0.5 * length(mut))
})

test_that("check_country_match suggests the same names either way", {
  skip_if_not_installed("stringdist")
  messy <- c("Brzil", "Frnace", "Germny", "Unted States", "Swizerland",
             "Camboida", "Xyzzy", "Phillipines")
  a <- suppressWarnings(check_country_match(messy, suggest = TRUE))
  b <- with_mocked_bindings(
    has_pkg = function(pkg) {
      if (identical(pkg, "stringdist")) FALSE
      else isTRUE(requireNamespace(pkg, quietly = TRUE))
    },
    suppressWarnings(check_country_match(messy, suggest = TRUE)))
  expect_equal(a$input, b$input)
  expect_equal(a$matched, b$matched)
  expect_equal(a$suggestion, b$suggestion)
})
