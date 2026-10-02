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
  skip_slow_on_cran()
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
    repair_country_names(mut, quiet = TRUE)))
  without <- with_mocked_bindings(
    has_pkg = function(pkg) {
      if (identical(pkg, "stringdist")) FALSE
      else isTRUE(requireNamespace(pkg, quietly = TRUE))
    },
    as.character(suppressWarnings(repair_country_names(mut, quiet = TRUE))))

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

test_that("repair_country_names fixes confident misses", {
  # Threshold loosened so the test holds with either stringdist or the
  # base-R adist fallback.
  out <- repair_country_names(c("United States", "Brzil", "Germny"),
                              threshold = 0.3, quiet = TRUE)
  expect_equal(as.character(out), c("United States", "Brazil", "Germany"))
  expect_s3_class(attr(out, "repairs"), "tbl_df")
  expect_equal(nrow(attr(out, "repairs")), 2L)
})

test_that("repair_country_names does not record identity 'repairs'", {
  # "Yugoslavia" exists in the codelist by name (no ISO code), so its own name
  # is its closest suggestion; that must not count as a repair.
  out <- repair_country_names(c("Yugoslavia", "Brzil"), quiet = TRUE)
  reps <- attr(out, "repairs")
  expect_false("Yugoslavia" %in% reps$from)
  expect_true("Brzil" %in% reps$from)
  expect_equal(as.character(out)[1], "Yugoslavia")
})

test_that("check_country_match flags historical entities, even matched ones", {
  rep <- check_country_match(c("USSR", "Yugoslavia", "France", "Wakanda"))
  expect_true(all(c("historical", "matched") %in% names(rep)))
  # USSR silently matches RUS in countrycode -- the flag is the safety net.
  expect_true(rep$historical[rep$input == "USSR"])
  expect_true(rep$matched[rep$input == "USSR"])
  expect_true(rep$historical[rep$input == "Yugoslavia"])
  expect_false(rep$matched[rep$input == "Yugoslavia"])
  expect_false(rep$historical[rep$input == "France"])
  expect_false(rep$historical[rep$input == "Wakanda"])
})

test_that("repair_country_names returns the documented repairs attribute", {
  r <- suppressMessages(repair_country_names(c("Fr4nce", "France")))
  expect_identical(as.character(r), c("France", "France"))
  a <- attr(r, "repairs")
  expect_s3_class(a, "tbl_df")
  expect_equal(nrow(a), 1L)
  expect_equal(a$from, "Fr4nce")
  expect_equal(a$to, "France")
  # An input needing no repair still carries the attribute, empty.
  expect_equal(nrow(attr(suppressMessages(repair_country_names("France")),
                         "repairs")), 0L)
})

test_that("audit_coverage lists every unmatched country, not just one", {
  # The de-duplication that stops a polygon frame counting a country once per
  # vertex used distinct() on iso3c -- which treats NA as a single value, so
  # every *uncoded* country collapsed into one row. The tool the package points
  # at for "which countries are missing" named one of four, and `n` -- the
  # denominator of every na_rate it reports -- was short by the rest.
  d <- tibble::tibble(
    country = c("France", "Germany", "Freedonia", "Ruritania", "Elbonia"),
    iso3c   = c("FRA", "DEU", NA, NA, NA),
    gdp     = c(1, 2, 3, 4, 5))
  a <- audit_coverage(d)
  expect_equal(nrow(a$unmatched), 3L)
  expect_setequal(a$unmatched$country, c("Freedonia", "Ruritania", "Elbonia"))
  expect_equal(a$na_rates$n[1], 5L)
  expect_equal(a$na_rates$na_rate[1], 0)

  # Coded duplicates are still collapsed, so a polygon frame is not counted
  # once per vertex.
  dup <- tibble::tibble(country = c("France", "France", "Germany"),
                        iso3c = c("FRA", "FRA", "DEU"), gdp = c(1, 1, 2))
  expect_equal(audit_coverage(dup)$na_rates$n[1], 2L)
})

test_that("audit_coverage's numeric columns carry no vapply names", {
  # vapply() names its result after `indicator`, so a$na_rates$na_rate handed
  # back c(gdp = 0.1) rather than 0.1 -- the same wart country_network() calls
  # unname() on.
  d <- tibble::tibble(iso3c = c("FRA", "DEU"), country = c("France", "Germany"),
                      gdp = c(1, NA))
  a <- audit_coverage(d)
  expect_null(names(a$na_rates$na_rate))
  expect_null(names(a$na_rates$n_missing))
  expect_equal(a$na_rates$na_rate, 0.5)
})

test_that("a blank cell gets no country suggestion", {
  # The guard was nzchar() alone, so a whitespace-only cell went through to the
  # fuzzy matcher -- and Jaro-Winkler finds spurious similarity between a
  # two-space string and a name containing spaces, so "  " came back suggesting
  # "Congo - Kinshasa" at distance 0.29, well inside the 0.35 threshold. A
  # padded empty cell is the commonest thing a CSV import produces.
  r <- suppressWarnings(
    check_country_match(c("France", "  ", "", "\t\n", NA, "Frnace")))
  blank <- r$input %in% c("  ", "", "\t\n") | is.na(r$input)
  expect_true(all(is.na(r$suggestion[blank])))
  # A real typo still gets one. (%in%, not ==: `input` holds an NA, and
  # NA == "Frnace" is NA, which widens the subset rather than dropping it.)
  expect_equal(r$suggestion[r$input %in% "Frnace"], "France")
  expect_true(all(r$matched[r$input %in% "France"]))
})

test_that("audit_coverage's by_group names the indicator it measured", {
  # The rate has always been computed on indicator[1] -- with the default
  # indicator = NULL that is whichever numeric column comes first -- but the
  # column was called plain `na_rate` under a heading reading "Coverage by
  # group", so it read as the group's overall coverage while the other
  # indicators were silently left out.
  snap <- world_snapshot$countries
  a <- audit_coverage(snap)
  expect_true("indicator" %in% names(a$by_group))
  expect_equal(unique(a$by_group$indicator), a$na_rates$indicator[1])
  # na_rates still covers every indicator, and they genuinely differ -- which is
  # why naming the one in by_group matters.
  expect_gt(nrow(a$na_rates), 1L)
  expect_gt(length(unique(a$na_rates$na_rate)), 1L)
  # The by_group rate is that indicator's rate, not an average across them.
  first <- a$na_rates$indicator[1]
  expect_equal(
    weighted.mean(a$by_group$na_rate, a$by_group$n_countries),
    mean(is.na(snap[[first]])), tolerance = 1e-8)
  # An explicit indicator is named as itself.
  b <- audit_coverage(snap, indicator = "co2_per_capita")
  expect_equal(unique(b$by_group$indicator), "co2_per_capita")
})

test_that("audit_coverage refuses a bare vector instead of reporting nothing", {
  # as_tibble() turns a vector into a one-column tibble called `value`, which
  # has no iso3c and no indicators -- so a character vector of country codes
  # produced a coverage object whose three tables were all empty, reading as
  # "no missing data" when nothing had been examined.
  expect_error(audit_coverage(c("USA", "FRA")), class = "countryatlas_error")
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    audit_coverage(c("USA", "FRA")), error = identity))),
    "must be a data frame", fixed = TRUE)
  # A real frame still works, and so does the shape that legitimately takes a
  # vector.
  expect_s3_class(audit_coverage(data.frame(iso3c = c("USA", "FRA"),
                                            v = c(1, NA))),
                  "countryatlas_coverage")
  expect_s3_class(check_dispute_coverage(c("USA", "FRA")), "tbl_df")
})

test_that("audit_coverage rejects an indicator column that isn't there", {
  # Used to silently report n_missing = 0 / na_rate = NaN for it.
  expect_error(audit_coverage(snap, indicator = "not_a_column"),
               class = "countryatlas_error")
  expect_silent(audit_coverage(snap, indicator = "gdp_per_capita"))
})

test_that("audit_coverage() lists a blank code as unmatched", {
  d <- data.frame(iso3c = c("FRA", "", NA),
                  country = c("France", "Nowhere", "Elsewhere"), v = 1:3)
  a <- audit_coverage(d)
  expect_setequal(a$unmatched$country, c("Nowhere", "Elsewhere"))
})

test_that("audit_coverage() and coverage_map() agree about an infinity", {
  skip_slow_on_cran()
  d <- data.frame(iso3c = c("FRA", "DEU", "ITA", "ESP"),
                  region = c("Europe", "Europe", "Europe", "Europe"),
                  v = c(1, Inf, NA, 4))
  a <- audit_coverage(d, "v")
  expect_equal(a$na_rates$n_missing, 2L)
  expect_equal(a$by_group$na_rate, 0.5)
  g <- toy_polygons(c(FRA = 1, DEU = Inf, ITA = NA, ESP = 4))
  cm <- suppressWarnings(coverage_map(g, v))
  expect_equal(map_provenance(cm)$n_missing, 2L)
})

test_that("print.countryatlas_coverage prints every section", {
  skip_slow_on_cran()
  # The method had zero test coverage; each branch depends on a different part
  # of the report being non-empty.
  snap <- countryatlas::world_snapshot$countries
  # The cli headings go to the message stream and the tibbles to stdout; capture
  # both, or the report prints through the middle of the test run.
  msgs <- function(x) {
    out <- NULL
    m <- capture.output(out <- capture.output(print(x)), type = "message")
    c(m, out)
  }
  full <- msgs(audit_coverage(snap, by = "continent"))
  expect_true(any(grepl("Coverage audit", full)))
  expect_true(any(grepl("Missingness by indicator", full)))
  expect_true(any(grepl("Coverage by group", full)))
  # With nothing unmatched it reports success rather than a warning.
  expect_true(any(grepl("matched", full)))
  # An unmatched country takes the other branch.
  bad <- snap[1:3, ]
  bad$country[1] <- "Zzz"
  bad$iso3c[1] <- NA
  un <- msgs(audit_coverage(bad))
  expect_true(any(grepl("unmatched", un)))
  # And the object is returned invisibly, so it can be piped on.
  cv <- audit_coverage(snap)
  ret <- NULL
  invisible(capture.output(invisible(capture.output(ret <- print(cv))),
                           type = "message"))
  expect_identical(ret, cv)
})
