test_that("country_timeline reads the crosswalk both ways", {
  # "Wakanda" matches neither spine, which the function now reports rather than
  # leaving as a row of NA to be noticed.
  expect_warning(
    tl <- country_timeline(c("USSR", "Estonia", "France", "Wakanda")),
    "matched neither")
  expect_equal(tl$iso3c[1], "SUN")
  expect_equal(tl$dissolved[1], 1991L)
  expect_length(tl$successors[[1]], 15L)
  expect_true("RUS" %in% tl$successors[[1]])
  # Read in reverse: Estonia's predecessor is the USSR.
  expect_equal(tl$predecessors[[2]], "SUN")
  expect_true(is.na(tl$iso3c[4]))
  expect_equal(nrow(country_timeline(character(0))), 0L)
})

test_that("audit_time_coverage catches rows outside a country's existence", {
  panel <- data.frame(iso3c = c("SSD", "CZE", "FRA", "RUS"),
                      year = c(1995L, 2001L, 2001L, 1985L))
  out <- audit_time_coverage(panel, quiet = TRUE)
  expect_true("SSD" %in% out$iso3c)
  expect_true(all(out$issue %in% c("before_existence", "after_dissolution")))
  expect_false("FRA" %in% out$iso3c)
  expect_equal(nrow(audit_time_coverage(data.frame(iso3c = "FRA", year = 2000L),
                                        quiet = TRUE)), 0L)
  expect_error(audit_time_coverage(data.frame(x = 1)), "iso3c")
})

test_that("historical_geometry draws the world as it was", {
  skip_slow_on_cran()
  skip_if_not_installed("cshapes")
  skip_if_not_installed("sf")
  g70 <- historical_geometry(1970)
  expect_s3_class(g70, "sf")
  expect_true(all(c("gwcode", "country", "iso3c") %in% names(g70)))
  # Decolonisation is visible: 1950 with dependencies has far more entities.
  g50 <- historical_geometry(1950, dependencies = TRUE)
  expect_gt(nrow(g50), nrow(g70))
  # gwcode is complete; iso3c is best-effort and NA for pre-ISO entities.
  expect_false(anyNA(g70$gwcode))
  expect_true(anyNA(g50$iso3c))
  expect_error(historical_geometry(2030), "1886-2019")
  expect_error(historical_geometry("x"), "single year")
})

test_that("interpolate_missing flags every value it invents", {
  p <- data.frame(iso3c = "USA", year = 2000:2008,
                  gdp = c(1, NA, NA, 4, NA, NA, NA, NA, 9))
  out <- interpolate_missing(p, "gdp")
  expect_true("gdp_imputed" %in% names(out))
  expect_equal(out$gdp[2:3], c(2, 3))
  expect_true(all(out$gdp_imputed[2:3]))
  # A gap longer than max_gap is left alone rather than invented across.
  expect_true(all(is.na(out$gdp[5:8])))
  expect_false(any(out$gdp_imputed[5:8]))
  # Observed values are never flagged.
  expect_false(any(out$gdp_imputed[c(1, 4, 9)]))
  expect_equal(attr(out, "countryatlas_imputed"), "gdp_imputed")
})

test_that("interpolate_missing flags the rows it actually filled", {
  # The "was missing" vectors were captured off the input and compared against
  # the output further down -- but the pipeline in between arranges by
  # (iso3c, year), so the two lined up only for an already-sorted input. Given
  # anything else the flags landed on the wrong rows: observed values came back
  # marked imputed, imputed ones came back marked observed, and world_map()
  # believes this column when it writes its caption.
  unsorted <- tibble::tibble(
    iso3c = c("FRA", "DEU", "FRA", "DEU", "FRA", "DEU"),
    year  = c(2022, 2022, 2021, 2021, 2020, 2020),
    v     = c(30, 300, NA, NA, 10, 100))
  out <- interpolate_missing(unsorted, "v")

  # Only the two 2021 cells were ever missing.
  filled <- out$iso3c[out$v_imputed]
  expect_setequal(paste(out$iso3c, out$year)[out$v_imputed],
                  c("DEU 2021", "FRA 2021"))
  expect_equal(sum(out$v_imputed), 2L)
  # and they are the interpolated midpoints, not the observed endpoints.
  expect_equal(out$v[out$v_imputed], c(200, 20))
  expect_false(any(out$v_imputed[out$year != 2021]))

  # An already-sorted frame gives the same answer, as it always did.
  sorted <- dplyr::arrange(unsorted, iso3c, year)
  expect_equal(interpolate_missing(sorted, "v")$v_imputed,
               c(FALSE, TRUE, FALSE, FALSE, TRUE, FALSE))
})

test_that("interpolate_missing reports a repeated country-year", {
  # Worse here than a wrong lag: stats::approx() collapses tied x-values to
  # their mean, so the two rows for the repeated year were *overwritten* with
  # the average -- 20 and 999 both became 509.5 -- and `_imputed` said FALSE for
  # them, because it compares "was NA" against "is not NA" and neither was ever
  # NA. The safeguard the code documents (a filler that changes an observed
  # value shows up as a flagged cell) cannot catch that, so the input is
  # reported instead.
  dup <- tibble::tibble(iso3c = rep("FRA", 5),
                        year = c(2018L, 2019L, 2019L, 2020L, 2021L),
                        v = c(10, 20, 999, NA, 40))
  expect_warning(interpolate_missing(dup, "v"), "repeated country-year")

  # A clean panel is silent, fills the gap linearly, and flags exactly it.
  clean <- tibble::tibble(iso3c = rep("FRA", 4), year = 2018:2021,
                          v = c(10, 20, NA, 40))
  expect_no_warning(out <- interpolate_missing(clean, "v"))
  expect_equal(out$v[out$year == 2020], 30)
  expect_true(out$v_imputed[out$year == 2020])
  expect_false(any(out$v_imputed[out$year != 2020]))
  # Observed values are untouched.
  expect_equal(out$v[out$year != 2020], c(10, 20, 40))

  # complete_years() shares the interpolator and must stay quiet too.
  expect_no_warning(cy <- complete_years(clean, value = "v", method = "linear"))
  expect_equal(cy$v[cy$year == 2020], 30)
})

test_that("a year is read the same way outside the source adapters too", {
  skip_slow_on_cran()
  # The bare as.integer() assumption was not confined to sources.R. Two more
  # sites took a year from the caller and read it wrong.
  # audit_time_coverage(): a Date year column became day counts
  # (1990-01-01 -> 7305), and the existence audit then flagged *both* USSR rows
  # as post-dissolution -- silently wrong output from the one verb whose job is
  # catching that class of mistake.
  ussr <- function(y) data.frame(iso3c = c("SUN", "SUN"), year = y)
  for (y in list(c(1990L, 1995L), as.Date(c("1990-01-01", "1995-01-01")),
                 c("1990", "1995"))) {
    got <- suppressWarnings(audit_time_coverage(ussr(y), quiet = TRUE))
    expect_equal(nrow(got), 1L)
    expect_equal(got$year, 1995L)   # the USSR dissolved in 1991
  }

  # deflate(): a Date base_year was reported back as its day count, a number
  # the caller never supplied.
  p <- data.frame(iso3c = "USA", year = 2000:2002, v = c(1, 2, 3),
                  d = c(90, 100, 105))
  expect_equal(nrow(deflate(p, v, 2001, deflator = d)), 3L)
  expect_equal(nrow(deflate(p, v, as.Date("2001-06-01"), deflator = d)), 3L)
  expect_equal(nrow(deflate(p, v, "2001", deflator = d)), 3L)
  # Bad input now shows what was actually passed, not a day count.
  expect_error(deflate(p, v, NA, deflator = d), "single year")
  expect_error(deflate(p, v, c(2000, 2001), deflator = d), "2000, 2001")
  expect_error(deflate(p, v, 1999, deflator = d), "1999 is not in")
})

test_that("country_timeline reports a name it cannot resolve", {
  skip_slow_on_cran()
  # It returned a row of NA in silence, where dissolve_country() -- same input
  # shape -- has always warned.
  w <- tryCatch(country_timeline("Nowhereland"), warning = function(x) x)
  msg <- gsub("[[:space:]]+", " ",
              cli::ansi_strip(paste(conditionMessage(w), collapse = " ")))
  expect_match(msg, "1 name matched neither", fixed = TRUE)
  expect_match(msg, "Nowhereland", fixed = TRUE)
  expect_match(msg, "check_country_match", fixed = TRUE)
  # Agrees at n = 2.
  expect_match(gsub("[[:space:]]+", " ", cli::ansi_strip(paste(conditionMessage(
    tryCatch(country_timeline(c("Nowhereland", "Atlantis")),
             warning = function(x) x)), collapse = " "))),
    "2 names matched neither", fixed = TRUE)

  # A historical name must stay silent: "USSR" is meant to fail the ISO lookup
  # and be picked up by the historical spine.
  expect_no_warning(country_timeline(c("USSR", "Estonia", "France")))
  expect_no_warning(country_timeline(character(0)))
  expect_no_warning(country_timeline("Nowhereland", warn = FALSE))
  expect_error(country_timeline("France", warn = "x"), "`warn`")

  # The returned values are unchanged.
  out <- suppressWarnings(country_timeline(c("France", "Nowhereland")))
  expect_equal(out$iso3c, c("FRA", NA))
  expect_equal(out$input, c("France", "Nowhereland"))
})

test_that("a bare column in a string-taking verb says what to write", {
  skip_slow_on_cran()
  # Nine of these verbs take a bare column through tidy eval; three take
  # strings -- interpolate_missing(value), complete_years(value) and
  # audit_coverage(indicator). Writing the bare column that works everywhere
  # else got base R's "object 'v' not found", which names neither the argument
  # nor the string it wanted.
  pan <- data.frame(iso3c = rep(c("USA", "FRA"), each = 4),
                    year = rep(2017:2020, 2),
                    v = c(1, NA, 3, 4, 5, 6, NA, 8),
                    d = c(2, 2, 2, 2, 4, 4, 4, 4))
  expect_error(interpolate_missing(pan, v), class = "countryatlas_bare_column")
  expect_error(complete_years(pan, value = v),
               class = "countryatlas_bare_column")
  # audit_coverage() takes one row per country, so it gets a cross-section --
  # handing it the panel makes it warn about the span, which is a separate and
  # correct complaint.
  xs <- data.frame(iso3c = c("USA", "FRA"), v = c(1, 2))
  expect_error(audit_coverage(xs, v), class = "countryatlas_bare_column")

  # The message quotes the column back, so the fix is copy-pasteable, and
  # handles a c() of bare columns too.
  msg <- function(e) cli::ansi_strip(conditionMessage(tryCatch(e,
    error = identity)))
  expect_match(msg(interpolate_missing(pan, v)), 'value = "v"', fixed = TRUE)
  expect_match(msg(interpolate_missing(pan, c(v, d))),
               'value = c("v", "d")', fixed = TRUE)
  expect_match(msg(audit_coverage(xs, v)), 'indicator = "v"', fixed = TRUE)

  # Strings, and the NULL default, still work.
  expect_s3_class(interpolate_missing(pan, "v"), "data.frame")
  expect_s3_class(interpolate_missing(pan, c("v", "d")), "data.frame")
  expect_s3_class(interpolate_missing(pan), "data.frame")
  expect_s3_class(complete_years(pan, value = "v"), "data.frame")
  expect_s3_class(audit_coverage(xs, "v"), "countryatlas_coverage")

  # Only a bare symbol is claimed: a genuine error in the argument, and a
  # string naming a column that is not there, must both survive intact.
  expect_error(interpolate_missing(pan, stop("boom")), "boom")
  expect_error(interpolate_missing(pan, "nope"), class = "countryatlas_error")
  expect_error(audit_coverage(xs, "nope"), class = "countryatlas_error")
})

test_that("interpolate_missing rejects duplicate column names", {
  # complete_years() and audit_coverage() both reject this frame -- vctrs does
  # it for them -- but interpolate_missing() did not, and the dplyr pipeline
  # quietly repaired the names instead: given two columns called `v` it filled
  # the first and handed back the second as `v.1`, a column the caller never
  # created and was never told about.
  d <- data.frame(iso3c = rep("USA", 3), year = 2018:2020,
                  v = c(1, NA, 3), v = c(10, 20, 30), check.names = FALSE)
  expect_error(interpolate_missing(d, "v"), class = "countryatlas_error")
  expect_error(interpolate_missing(d, "v"), "duplicated column name")

  ok <- data.frame(iso3c = rep("USA", 3), year = 2018:2020,
                   v = c(1, NA, 3), w = c(10, 20, 30))
  filled <- interpolate_missing(ok, "v")
  expect_identical(names(filled), c("iso3c", "year", "v", "w", "v_imputed"))
  expect_equal(filled$v, c(1, 2, 3))
})

test_that("interpolate_missing() neither crashes on nor overwrites an undated row", {
  d <- data.frame(iso3c = "A", year = c(2000, NA, 2002, 2003),
                  v = c(1, 5, NA, 4))
  out <- interpolate_missing(d, "v")
  # The undated observation survives (the filler used to write NA over it)
  # and is no anchor: 2002 sits between 2000 and 2003.
  expect_equal(out$v[is.na(out$year)], 5)
  expect_equal(out$v[out$year %in% 2002], 3)
  expect_false(out$v_imputed[is.na(out$year)])
  # And an undated missing value is not carried into.
  d2 <- data.frame(iso3c = "A", year = c(2000, 2001, NA), v = c(1, 2, NA))
  out2 <- interpolate_missing(d2, "v", method = "locf")
  expect_true(is.na(out2$v[is.na(out2$year)]))
  expect_false(out2$v_imputed[is.na(out2$year)])
})

test_that("pre-ISO historical entities are not reported as unmatched", {
  expect_silent(tl <- country_timeline(c("Tanganyika", "United Arab Republic",
                                         "Zanzibar")))
  expect_equal(tl$dissolved, c(1964L, 1961L, 1964L))
  w <- tryCatch(country_timeline(c("Tanganyika", "Freedonia", NA)),
                warning = function(w) conditionMessage(w))
  w <- gsub("\\s+", " ", w)
  expect_match(w, "1 name matched neither")
  expect_match(w, "Freedonia")
  expect_no_match(w, "Tanganyika")
  # A missing input is not a name that failed to match.
  expect_silent(dissolve_country(c("France", NA)))
})

test_that("audit_time_coverage() has no phantom row for an unreadable year", {
  p <- data.frame(iso3c = c("SUN", "SUN", "FRA"),
                  year = c("1995", "junk", "2000"))
  out <- suppressWarnings(audit_time_coverage(p, quiet = TRUE))
  expect_equal(nrow(out), 1L)
  expect_false(anyNA(out$iso3c))
  # And the dissolved code is named, which countrycode cannot do.
  expect_equal(out$country, "Soviet Union")
})

test_that("historical_geometry() refuses a year it cannot place", {
  skip_if_not_installed("cshapes")
  skip_if_not_installed("sf")
  expect_error(historical_geometry(Inf), class = "countryatlas_error")
  expect_error(historical_geometry(1e10), "1886-2019",
               class = "countryatlas_error")
})

test_that("historical_geometry() gives no code to a state not yet born", {
  skip_if_not_installed("cshapes")
  skip_if_not_installed("sf")
  skip_on_cran()
  g80 <- sf::st_drop_geometry(historical_geometry(1980, projection = NULL))
  # GW code 365 is the USSR in 1980 and Russia from 1992; historical_codes has
  # Russia as one of fifteen successors, born in 1991.
  expect_true(is.na(g80$iso3c[g80$gwcode == 365]))
  expect_equal(g80$iso3c[g80$gwcode == 2], "USA")
  g10 <- sf::st_drop_geometry(historical_geometry(2010, projection = NULL))
  expect_equal(g10$iso3c[g10$gwcode == 365], "RUS")
  # The documented `owner`: a sovereign state carries its own code.
  if ("owner" %in% names(g80)) {
    expect_false(anyNA(g80$owner[g80$gwcode == 2]))
    # cshapes stores it as text; the value is the state's own code.
    expect_equal(as.numeric(g80$owner[g80$gwcode == 2]), 2)
  }
  # attach_geometry(year = ) no longer paints the USSR with Russia's value.
  d <- data.frame(iso3c = c("RUS", "USA"), v = c(1, 2))
  out <- suppressWarnings(attach_geometry(d, year = 1980))
  expect_true(is.na(out$v[out$gwcode == 365]))
})

test_that("audit_time_coverage() and historical_geometry() agree on births", {
  born <- countryatlas:::successor_born_years()
  expect_equal(unname(born["RUS"]), 1991)
  flagged <- audit_time_coverage(data.frame(iso3c = "RUS", year = 1980L),
                                 quiet = TRUE)
  expect_equal(flagged$issue, "before_existence")
})

test_that("historical borders draw in the orthographic projection", {
  skip_if_not_installed("cshapes")
  skip_if_not_installed("sf")
  skip_on_cran()
  # Repairing CShapes geometry gives geometry collections (a polygon plus a
  # sliver of line), and casting one keeps only its first part, which failed
  # with "polygons require at least 4 points".
  hist <- suppressWarnings(historical_geometry(1950, dependencies = TRUE))
  cut <- countryatlas:::clip_to_hemisphere(hist, 0, 20)
  expect_equal(nrow(cut), nrow(hist))
  expect_true(all(sf::st_geometry_type(cut) == "MULTIPOLYGON"))
  f <- tempfile(fileext = ".png")
  grDevices::png(f, width = 120, height = 120)
  on.exit({ grDevices::dev.off(); unlink(f) }, add = TRUE)
  expect_no_error(print(suppressWarnings(
    world_map(hist, gwcode, projection = "orthographic", recenter = 120))))
})

test_that("audit_time_coverage() flags years before independence", {
  # 3.0.0 knew only the curated dissolutions and assumed every other country
  # existed throughout; Gleditsch-Ward's list dates independence.
  p <- data.frame(iso3c = c("NAM", "NAM", "ERI", "TLS", "EST", "EST", "FRA", "PRI"),
                  year = c(1985, 1995, 1990, 1995, 1930, 1960, 1900, 1950))
  r <- audit_time_coverage(p, quiet = TRUE)
  ind <- r[r$issue == "before_independence", ]
  expect_setequal(paste(ind$iso3c, ind$year), c("NAM 1985", "ERI 1990", "TLS 1995"))
  expect_true(all(ind$basis == "gleditsch_ward"))
  expect_match(ind$existed[ind$iso3c == "NAM"], "from 1990")
  # Estonia: independent 1918-1940 and from 1991. 1930 is inside a spell, which
  # overrules the crosswalk's succession from the USSR in 1991; 1960 is not.
  expect_false(any(r$iso3c == "EST" & r$year == 1930))
  expect_true(any(r$iso3c == "EST" & r$year == 1960))
  # An old state, and a territory off the list, are never flagged.
  expect_false(any(r$iso3c %in% c("FRA", "PRI")))
})
