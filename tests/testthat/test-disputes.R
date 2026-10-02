test_that("dispute_policy records a convention and warns about de jure", {
  old <- dispute_policy()
  on.exit(dispute_policy(old), add = TRUE)
  # A setter returns what it REPLACED, as options()/par()/sf_use_s2() do, so
  # `on.exit(dispute_policy(dispute_policy("neutral")))` restores the old
  # value. It used to return the value just set, making that idiom a no-op.
  expect_equal(dispute_policy("neutral"), old)
  expect_equal(dispute_policy(), "neutral")
  expect_equal(dispute_policy("de_facto"), "neutral")
  expect_equal(dispute_policy(), "de_facto")
  # Which makes the round-trip idiom work.
  restored <- dispute_policy(dispute_policy("neutral"))
  expect_equal(dispute_policy(), "de_facto")
  expect_equal(restored, "neutral")
  dispute_policy("neutral")
  # Selecting de jure must not silently imply the shapes changed.
  expect_warning(dispute_policy("de_jure"), "still de facto")
  expect_error(dispute_policy("nonsense"), "`policy`")
})

test_that("check_dispute_coverage reports both directions", {
  out <- check_dispute_coverage(snap, quiet = TRUE)
  expect_true("in_data" %in% names(out))
  expect_equal(nrow(out), nrow(countryatlas::disputed_territories))
  expect_true(any(out$in_data))
  expect_error(check_dispute_coverage(data.frame(x = 1)), "iso3c")
})

# --- options are validated where they are read --------------------------------------

test_that("an unrecognised dispute_policy option falls back rather than propagating", {
  skip_slow_on_cran()
  old <- getOption("countryatlas.dispute_policy")
  withr::defer(options(countryatlas.dispute_policy = old))
  # Every other option the package reads is validated on read; this one was not,
  # so a typo in .Rprofile printed "Convention: nonsense" on a published map --
  # on the very feature whose job is to state the convention truthfully.
  for (bad in list("nonsense", 42, c("none", "neutral"), TRUE)) {
    options(countryatlas.dispute_policy = bad)
    expect_equal(suppressWarnings(dispute_policy()), "none")
  }
  options(countryatlas.dispute_policy = NULL)
  expect_equal(dispute_policy(), "none")
  dispute_policy("neutral")
  expect_equal(dispute_policy(), "neutral")
})

test_that("a bogus dispute_policy cannot reach a map caption", {
  skip_slow_on_cran()
  old <- getOption("countryatlas.dispute_policy")
  withr::defer(options(countryatlas.dispute_policy = old))
  options(countryatlas.dispute_policy = "nonsense")
  cap <- suppressWarnings(
    world_map(poly_df(), gdp_per_capita, disputes = "mark")$labels$caption)
  expect_match(cap, "Convention: none")
  expect_false(grepl("nonsense", cap, fixed = TRUE))
})

test_that("check_dispute_coverage() reports each bad code once, and not NA", {
  msgs <- character(0)
  withCallingHandlers(
    check_dispute_coverage(c("ESH", NA, "xx", "xx"), quiet = TRUE),
    warning = function(w) {
      msgs <<- c(msgs, gsub("\\s+", " ", conditionMessage(w)))
      invokeRestart("muffleWarning")
    })
  expect_length(msgs, 1L)
  expect_match(msgs, "1 value in `data` is not")
  expect_no_match(msgs, "NA")
})
