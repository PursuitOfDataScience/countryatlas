# --- reporting --------------------------------------------------------------------

test_that("country_factsheet assembles what the package knows", {
  skip_slow_on_cran()
  fs <- country_factsheet("Brazil")
  expect_s3_class(fs, "countryatlas_factsheet")
  expect_equal(fs$iso3c, "BRA")
  expect_true(nrow(fs$groups) > 0)
  expect_true(nrow(fs$indicators) > 0)
  # Numbers are rounded rather than dumped at full double precision.
  area <- fs$geography$value[fs$geography$field == "area_km2"]
  expect_false(grepl("\\.", area))
  msg <- capture.output(out <- capture.output(print(fs)), type = "message")
  expect_match(paste(c(msg, out), collapse = "\n"), "Brazil")
  expect_error(country_factsheet("Wakanda"), "did not resolve")
  expect_error(country_factsheet(c("Brazil", "France")), "single country")
})

test_that("world_table ranks and formats", {
  skip_slow_on_cran()
  t1 <- world_table(snap, gdp_per_capita, top_n = 5, engine = "tibble")
  expect_equal(nrow(t1), 5L)
  expect_equal(t1$rank, 1:5)
  expect_true(all(diff(t1$gdp_per_capita) <= 0))
  t2 <- world_table(snap, gdp_per_capita, top_n = 5, desc = FALSE,
                    engine = "tibble")
  expect_true(all(diff(t2$gdp_per_capita) >= 0))
  skip_if_not_installed("gt")
  expect_s3_class(world_table(snap, gdp_per_capita, top_n = 5), "gt_tbl")
})

test_that("top_n is validated, not just tested for finiteness", {
  skip_slow_on_cran()
  # check_number() rejects Inf, which is the documented "no limit", so the guard
  # was `if (is.finite(top_n))` alone -- and everything is.finite() rejects then
  # skipped validation entirely. top_n = "5" and NA silently returned every row.
  snap <- world_snapshot$countries
  for (bad in list("5", NA, NULL, character(0), c(1, 2))) {
    expect_error(world_table(snap, gdp_per_capita, top_n = bad,
                             engine = "tibble"), "top_n")
  }
  expect_equal(nrow(world_table(snap, gdp_per_capita, top_n = 5,
                                engine = "tibble")), 5L)
  # Inf still means no limit.
  expect_gt(nrow(world_table(snap, gdp_per_capita, top_n = Inf,
                             engine = "tibble")), 5L)
  # country_network() carried the same unguarded pattern.
  od <- data.frame(from = "France", to = "Germany", w = 1)
  expect_error(country_network(od, from, to, w, top_n = "5"), "top_n")
})

test_that("world_table rejects a subtitle with no title", {
  skip_slow_on_cran()
  # gt draws the subtitle inside the header block a title opens, so on its own
  # it had nowhere to go and was dropped without a word.
  skip_if_not_installed("gt")
  snap <- world_snapshot$countries
  expect_error(world_table(snap, gdp_per_capita, top_n = 3, subtitle = "x"),
               "needs a")
  expect_s3_class(world_table(snap, gdp_per_capita, top_n = 3,
                              title = "t", subtitle = "x"), "gt_tbl")
})

test_that("one-row-per-country verbs say when they collapse a panel", {
  skip_slow_on_cran()
  # Collapsing to one row per country is for repeated *geometry* rows, not for
  # time. Handed a panel these kept whichever row sorted first -- France's 2018
  # value of 10 out of 10/20/30 -- and presented that year as the answer with
  # nothing to say a choice had been made.
  panel <- tibble::tibble(
    iso3c = rep(c("FRA", "DEU"), each = 3),
    year  = rep(2018:2020, 2),
    v     = c(10, 20, 30, 100, 200, 300),
    pop   = rep(c(1e6, 2e6), each = 3),
    cases = 1:6)
  expect_warning(world_table(panel, v, engine = "tibble"), "spans 3 years")
  expect_warning(rate_check(panel, cases, pop), "spans 3 years")
  expect_warning(correlate_indicators(panel, v, pop), "spans 3 years")
  expect_warning(audit_coverage(panel), "spans 3 years")
  expect_warning(gridded_cartogram(panel, v, cells = 50), "spans 3 years")

  # A cross-section is quiet, and so is a geometry frame with one year.
  cs <- panel[panel$year == 2020, ]
  expect_no_warning(world_table(cs, v, engine = "tibble"))
  poly <- suppressWarnings(
    attach_geometry(world_snapshot$countries, geometry = "polygon"))
  expect_no_warning(world_table(poly, gdp_per_capita, engine = "tibble"))
})

test_that("world_table only claims a rank when it ranked something", {
  # With value = NULL the frame keeps whatever order it arrived in (iso3c, for
  # the bundled snapshot), so head() takes an arbitrary slice. Numbering that
  # 1..n under a column called `rank` told the reader these were the top n by
  # something: world_table(snap, top_n = 5) labelled Afghanistan "rank 1" with
  # an empty GDP cell beside it.
  snap <- world_snapshot$countries
  expect_warning(w <- world_table(snap, top_n = 5, engine = "tibble"),
                 class = "countryatlas_unranked_top_n")
  expect_false("rank" %in% names(w))
  expect_equal(nrow(w), 5L)
  # Ranking on a column gives a real rank, in the right direction.
  r <- world_table(snap, gdp_per_capita, top_n = 5, engine = "tibble")
  expect_equal(r$rank, 1:5)
  expect_false(is.unsorted(rev(r$gdp_per_capita)))
  expect_false(anyNA(r$gdp_per_capita))
  # Ascending too.
  a <- world_table(snap, gdp_per_capita, top_n = 5, desc = FALSE,
                   engine = "tibble")
  expect_false(is.unsorted(a$gdp_per_capita))
  # No truncation, no warning: nothing was misrepresented.
  expect_silent(world_table(snap, top_n = Inf, engine = "tibble"))
})

test_that("the microstate border gap is named rather than silently counted", {
  skip_slow_on_cran()
  # country_borders() computes adjacency from Natural Earth, and the default
  # 110m basemap has no polygon at all for the European microstates. They
  # contribute no rows, so the five of them report zero land neighbours and
  # their neighbours report short: France came back with 8 instead of 10, under
  # a heading that stated the count as fact.
  expect_true(all(countryatlas:::WDJ_MICROSTATES %in% country_meta$iso3c))
  # The note is about neighbours that were computed, which takes sf. Without
  # it this passed only because a failed lookup was reported as the basemap's
  # doing; the sheet now says the neighbours were not computed instead.
  skip_if_no_sf_geometry()
  # cli_fmt(), not capture.output(type = "message"): testthat's reporter has
  # already redirected that stream, so the nested capture comes back empty.
  txt <- function(x) paste(cli::ansi_strip(cli::cli_fmt(print(x))),
                           collapse = " ")
  fr <- txt(country_factsheet("France"))
  expect_match(fr, "Excludes Andorra, Monaco")
  expect_match(fr, "scale = \"medium\"", fixed = TRUE)
  it <- txt(country_factsheet("Italy"))
  expect_match(it, "San Marino")
  # A microstate says its zero is an artefact, not a fact.
  mc <- txt(country_factsheet("Monaco"))
  expect_match(mc, "Not 0")
  # An unaffected country stays silent.
  expect_no_match(txt(country_factsheet("Germany")), "110m basemap")
})

test_that("a factsheet for a code with no metadata row is still named", {
  skip_slow_on_cran()
  # `name = first_or_na(row$country) %||% iso` -- but %||% only replaces NULL,
  # and first_or_na() returns NA_character_ when the code has no row in
  # country_meta. The fallback was written and never fired, so Kosovo, before
  # country_meta had a row for it, printed a header of literally "NA (XKX)"
  # while listing four real land neighbours underneath.
  k <- country_factsheet("Kosovo")
  expect_equal(k$iso3c, "XKX")
  expect_equal(k$name, "Kosovo")
  hdr <- paste(cli::ansi_strip(cli::cli_fmt(print(k))), collapse = " ")
  expect_match(hdr, "Kosovo (XKX)", fixed = TRUE)
  expect_no_match(hdr, "NA (XKX)", fixed = TRUE)
  # Kosovo has its row now, so the name comes from it for a bare code too.
  expect_equal(country_factsheet("XKX", origin = "iso3c")$name, "Kosovo")
  # Every known code has a row, so the fallback is checked on its own: no row
  # gives the caller's string, never NA.
  na_fallback <- countryatlas:::na_fallback
  first_or_na <- countryatlas:::first_or_na
  expect_identical(na_fallback(first_or_na(character(0)), "Kosovo"), "Kosovo")
  expect_identical(na_fallback(first_or_na(NA_character_), "XKX"), "XKX")
  expect_identical(na_fallback(first_or_na("  "), "XKX"), "XKX")
  # A country with metadata is unaffected.
  expect_equal(country_factsheet("France")$name, "France")
})

test_that('world_table(engine = "tibble") names the title it cannot draw', {
  d <- data.frame(iso3c = c("FRA", "DEU", "ESP"), gdp = c(3, 2, 1))
  # A tibble has no header, and both were dropped without a word.
  expect_warning(world_table(d, "gdp", engine = "tibble", title = "T"),
                 class = "countryatlas_engine_ignored")
  w <- tryCatch(
    world_table(d, "gdp", engine = "tibble", title = "T", subtitle = "S"),
    warning = function(x) x)
  msg <- cli::ansi_strip(paste(conditionMessage(w), collapse = " "))
  expect_match(msg, "these arguments", fixed = TRUE)
  expect_match(msg, "title", fixed = TRUE)
  expect_match(msg, "subtitle", fixed = TRUE)
  # Silent when there is nothing to drop, and on the engine that draws them.
  expect_no_warning(world_table(d, "gdp", engine = "tibble"))
  skip_if_not_installed("gt")
  expect_no_warning(world_table(d, "gdp", engine = "gt", title = "T"))
  # The gt path's existing objection is unchanged.
  expect_error(world_table(d, "gdp", engine = "gt", subtitle = "S"),
               "needs a")
})

test_that("world_table says when the value column emptied the table", {
  # Rows with no value cannot be ranked, so they go -- but if that empties the
  # table the caller gets a 0-row result from a frame that had rows in it, and
  # no way to tell "the column is empty" from "there was nothing to report".
  # gridded_cartogram() aborts on the same shape; a table is recoverable, so
  # this warns and carries on.
  allna <- data.frame(iso3c = c("USA", "FRA", "JPN"), v = rep(NA_real_, 3))
  expect_warning(out <- world_table(allna, v, engine = "tibble"),
                 class = "countryatlas_all_missing")
  expect_identical(nrow(out), 0L)
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    world_table(allna, v, engine = "tibble"), warning = identity))),
    "all 3 countries", fixed = TRUE)
  # Singular reads correctly too -- the count and the agreement sit together.
  one <- data.frame(iso3c = "USA", v = NA_real_)
  expect_match(cli::ansi_strip(conditionMessage(tryCatch(
    world_table(one, v, engine = "tibble"), warning = identity))),
    "all 1 country", fixed = TRUE)

  # Everything that is not "data in, nothing out" stays silent: a partial drop
  # is the normal case, and a 0-row frame returns 0 rows as every panel helper
  # does.
  expect_silent(world_table(data.frame(iso3c = c("USA", "FRA", "JPN"),
                                       v = c(1, NA, 3)), v, engine = "tibble"))
  expect_silent(world_table(data.frame(iso3c = c("USA", "FRA"), v = c(1, 2)),
                            v, engine = "tibble"))
  expect_silent(world_table(data.frame(iso3c = character(0), v = numeric(0)),
                            v, engine = "tibble"))
  expect_silent(world_table(data.frame(iso3c = c("USA", "FRA"), v = c(1, 2)),
                            engine = "tibble"))
})

test_that("world_table() gives tied values the same rank", {
  d <- data.frame(iso3c = c("A", "B", "C", "D"), v = c(5, 7, 7, 1))
  t1 <- world_table(d, v, engine = "tibble")
  expect_equal(t1$rank, c(1L, 1L, 3L, 4L))
  t2 <- world_table(d, v, desc = FALSE, engine = "tibble")
  expect_equal(t2$rank, c(1L, 2L, 3L, 3L))
})

test_that("a factsheet says when neighbours could not be computed", {
  skip_slow_on_cran()
  local_mocked_bindings(neighbors = function(...) {
    rlang::abort("The package \"sf\" is required.")
  })
  for (x in c("France", "Andorra")) {
    out <- cli::cli_fmt(print(country_factsheet(x)))
    expect_true(any(grepl("Not computed", out)))
    # The microstate note blamed the basemap for what the lookup never did.
    expect_false(any(grepl("basemap", out)))
    expect_false(any(grepl("None found", out)))
  }
})
