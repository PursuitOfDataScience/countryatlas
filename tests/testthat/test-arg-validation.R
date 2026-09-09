# Scalar arguments used to reach base R and dependency internals unchecked, so a
# typo or an NA surfaced as "missing value where TRUE/FALSE needed", classInt's
# "n less than 2", or a PROJ complaint about lat_0 -- none naming the argument.
# A few produced no error at all and silently drew nonsense.

snap <- countryatlas::world_snapshot$countries

test_that("check_number names the argument and the range", {
  cn <- countryatlas:::check_number
  expect_error(cn(NA, "k"), "single finite number")
  expect_error(cn(NA_real_, "k"), class = "countryatlas_error")
  expect_error(cn(Inf, "k"), "single finite number")
  expect_error(cn(c(1, 2), "k"), "single finite number")
  expect_error(cn("a", "k"), "single finite number")
  expect_error(cn(NULL, "k"), "single finite number")
  expect_error(cn(5, "k", lo = 0, hi = 1), "between 0 and 1")
  expect_error(cn(5, "k", lo = 0, hi = 1), "`k`")
  expect_silent(cn(0.5, "k", lo = 0, hi = 1))
  expect_silent(cn(0, "k", lo = 0, hi = 1))     # bounds are inclusive
  expect_silent(cn(1, "k", lo = 0, hi = 1))
})

test_that("n_bins is validated on every style path", {
  skip_if_not_installed("maps")
  mapdf <- attach_geometry(snap, geometry = "polygon")
  # quantile/jenks go through compute_breaks(); binned hands n_bins straight to
  # ggplot2, so both routes need the check.
  for (sty in c("quantile", "jenks", "binned", "continuous")) {
    expect_error(world_map(mapdf, gdp_per_capita, style = sty, n_bins = 1),
                 class = "countryatlas_error")
    expect_error(world_map(mapdf, gdp_per_capita, style = sty, n_bins = NA),
                 "single finite number")
  }
  expect_error(countryatlas:::compute_breaks(1:10, "quantile", 0), "`n_bins`")
})

test_that("wdj_crs refuses a latitude PROJ cannot build a CRS from", {
  # |lat_0| >= 90 built a string PROJ rejects, and the failure only surfaced
  # later as coord_sf()'s "crs not found: is it missing?".
  expect_error(countryatlas:::wdj_crs("orthographic", lat0 = 200), "`lat0`")
  expect_error(countryatlas:::wdj_crs("orthographic", lat0 = -91), "`lat0`")
  expect_error(countryatlas:::wdj_crs("equal_earth", recenter = 400), "`recenter`")
  expect_error(countryatlas:::wdj_crs("equal_earth", recenter = NA),
               "single finite number")
  # spin_globe() sweeps recenter from 0 to just under 360, so a full turn either
  # way must stay legal.
  expect_type(countryatlas:::wdj_crs("orthographic", recenter = 354, lat0 = 20),
              "character")
  expect_type(countryatlas:::wdj_crs("equal_earth", recenter = -360), "character")
  expect_type(countryatlas:::wdj_crs("orthographic", lat0 = 90), "character")
})

test_that("globe_map validates lon/lat on both backends", {
  # The sf backend gets this via wdj_crs(); the polygon backend uses coord_map()
  # and previously took a nonsense orientation without comment.
  skip_if_not_installed("maps")
  expect_error(globe_map(snap, gdp_per_capita, backend = "polygon", lat = 200),
               "`lat`")
  expect_error(globe_map(snap, gdp_per_capita, backend = "polygon", lon = 400),
               "`lon`")
  expect_error(globe_map(snap, gdp_per_capita, backend = "polygon", lat = NA),
               "single finite number")
})

test_that("plot scalars that would draw nonsense are rejected", {
  skip_if_not_installed("maps")
  # A negative max_height silently drew the spikes upside down.
  expect_error(spike_map(snap, population, max_height = -5), "`max_height`")
  expect_error(spike_map(snap, population, width = -1), "`width`")
  expect_error(spike_map(snap, population, alpha = 3), "between 0 and 1")
  expect_error(bubble_map(snap, population, max_size = -4), "`max_size`")
  expect_error(bubble_map(snap, population, alpha = -1), "between 0 and 1")
  # An arc needs two points; below that seq() errored on length.out.
  od <- data.frame(from = "China", to = "United States", value = 1)
  expect_error(flow_map(od, from, to, value, n = 1), "`n`")
  expect_error(flow_map(od, from, to, value, n = 0), "`n`")
})

test_that("analysis and diagnostic scalars are validated", {
  expect_error(repair_country_names("Brzil", threshold = 5), "between 0 and 1")
  expect_error(repair_country_names("Brzil", threshold = NA),
               "single finite number")
  panel <- data.frame(iso3c = "A", year = 2000:2003, g = 1:4)
  # n <= 0 used to be clamped to 1, so a lag of 0 quietly returned a lag of 1.
  expect_error(lag_by_country(panel, g, n = 0), "`n`")
  expect_error(lag_by_country(panel, g, n = -3), "`n`")
  expect_error(diff_by_country(panel, g, n = NA), "single finite number")
  expect_equal(lag_by_country(panel, g, n = 2)$g_lag2, c(NA, NA, 1L, 2L))
})

test_that("complete_years rejects a value column that isn't there", {
  # Silently ignored with the default method = "none", but errored from all_of()
  # with "locf"/"linear" -- inconsistent either way.
  df <- data.frame(iso3c = "A", year = c(2000L, 2002L), g = c(1, 3))
  for (m in c("none", "locf", "linear")) {
    expect_error(complete_years(df, value = "nope", method = m),
                 class = "countryatlas_error")
  }
  expect_no_error(complete_years(df, value = "g", method = "linear"))
})

test_that("morans_i validates n_perm", {
  # need_pkg("sf") runs before the scalar check.
  skip_if_no_sf_geometry()
  expect_error(morans_i(snap, gdp_per_capita, n_perm = -5), "`n_perm`")
  expect_error(morans_i(snap, gdp_per_capita, n_perm = NA),
               "single finite number")
})

test_that("simplify_geometry validates keep", {
  skip_if_no_sf_geometry()
  g <- world_geometry("countries", geometry = "sf")
  expect_error(simplify_geometry(g, keep = 1.5), "between 0 and 1")
  expect_error(simplify_geometry(g, keep = NA), "single finite number")
})

test_that("count arguments are bounded so as.integer() cannot make them NA", {
  # check_number() only required a finite number, but several call sites then
  # coerce with as.integer(), which returns NA past 2^31-1 -- surfacing as
  # "NAs introduced by coercion" or "missing value where TRUE/FALSE needed".
  panel <- data.frame(iso3c = "A", year = 2000:2003, g = 1:4)
  big <- 1e10
  expect_error(lag_by_country(panel, g, n = big), "2147483647")
  expect_error(diff_by_country(panel, g, n = big), "2147483647")
  expect_error(countryatlas:::compute_breaks(1:10, "quantile", big), "2147483647")
  od <- data.frame(f = "China", t = "United States", v = 1)
  expect_error(flow_map(od, f, t, v, n = big), "`n`")
  # Values just inside the bound are still accepted by the check itself.
  expect_silent(countryatlas:::check_number(.Machine$integer.max, "k", lo = 0,
                                            hi = .Machine$integer.max))
  expect_error(countryatlas:::check_number(.Machine$integer.max + 1, "k", lo = 0,
                                           hi = .Machine$integer.max))
  # And ordinary counts are untouched.
  expect_equal(lag_by_country(panel, g, n = 2)$g_lag2, c(NA, NA, 1L, 2L))
})

test_that("morans_i bounds n_perm and no longer clamps it redundantly", {
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  expect_error(morans_i(snap, gdp_per_capita, n_perm = 1e10), "2147483647")
  # n_perm = 0 skips the permutation test; validation admits it.
  out <- morans_i(snap, gdp_per_capita, n_perm = 0)
  expect_true(is.na(out$p_value))
  # A fractional count truncates rather than erroring.
  set.seed(1)
  expect_false(is.na(morans_i(snap, gdp_per_capita, n_perm = 9.7)$p_value))
})

test_that("simplify_geometry(keep = 0) is rejected on both backends", {
  # rmapshaper requires keep > 0, but the st_simplify() fallback silently
  # accepted 0 (dTolerance = 10000), so the same call errored or not depending
  # on which optional package the caller had.
  skip_if_no_sf_geometry()
  g <- world_geometry("countries", geometry = "sf")
  expect_error(simplify_geometry(g, keep = 0), class = "countryatlas_error")
  expect_error(simplify_geometry(g, keep = 0), "greater than 0")
  # Same message with rmapshaper unavailable, i.e. on the st_simplify path.
  testthat::local_mocked_bindings(
    has_pkg = function(pkg) {
      if (identical(pkg, "rmapshaper")) FALSE
      else isTRUE(requireNamespace(pkg, quietly = TRUE))
    }
  )
  expect_error(simplify_geometry(g, keep = 0), "greater than 0")
  # A valid proportion still works on the fallback path.
  expect_s3_class(suppressWarnings(simplify_geometry(g, keep = 0.1)), "sf")
})

test_that("fractional counts truncate consistently with their column names", {
  # check_number() admits non-integers; the call sites as.integer() them. The
  # effective value and the generated column name must not disagree.
  panel <- data.frame(iso3c = "A", year = 2000:2005, g = 1:6)
  out <- lag_by_country(panel, g, n = 2.9)
  expect_true("g_lag2" %in% names(out))            # named for the truncation
  expect_equal(out$g_lag2, c(NA, NA, 1L, 2L, 3L, 4L))   # and lagged by 2
  expect_equal(nrow(countryatlas:::great_circle(0, 0, 90, 0, n = 3.9)), 4L)
})

test_that("the bin count does not depend on whether classInt is installed", {
  # classInt truncates a fractional n_bins internally; the base-quantile
  # fallback would hand it to seq(length.out = ) and get one break more, so the
  # same call produced a different number of bins depending on the environment.
  with_classint <- countryatlas:::compute_breaks(1:100, "quantile", 2.1)
  fallback <- withr_free <- NULL
  testthat::local_mocked_bindings(
    has_pkg = function(pkg) {
      if (identical(pkg, "classInt")) FALSE
      else isTRUE(requireNamespace(pkg, quietly = TRUE))
    }
  )
  fallback <- countryatlas:::compute_breaks(1:100, "quantile", 2.1)
  expect_equal(length(with_classint), length(fallback))
  expect_equal(length(with_classint), 3L)          # 2 bins -> 3 breaks
  # Integer counts were always consistent; keep them that way.
  expect_equal(length(countryatlas:::compute_breaks(1:100, "quantile", 5)), 6L)
})

# world_query() and as_ggsql_source() sprintf() their arguments into a query
# string, and sprintf() vectorises silently. A length-2 value duplicated a whole
# clause ("PROJECT TO a" *and* "PROJECT TO b"), a length-0 one deleted the
# clause outright (source = character(0) produced a query with no FROM line),
# and NA became the literal text 'NA'. All of it reached ggsql's SQL parser as
# an opaque failure instead of erroring here.

test_that("check_string names the argument and the problem", {
  cs <- countryatlas:::check_string
  expect_error(cs(c("a", "b"), "k"), "single string")
  expect_error(cs(c("a", "b"), "k"), "Got 2 values")
  expect_error(cs(character(0), "k"), "Got 0 values")
  expect_error(cs(NA_character_, "k"), "single string")
  expect_error(cs(NA, "k"), class = "countryatlas_error")
  expect_error(cs(42, "k"), "single string")
  expect_error(cs(list("a"), "k"), "single string")
  expect_error(cs("", "k"), "must not be an empty string")
  expect_silent(cs("", "k", allow_empty = TRUE))
  expect_silent(cs("a", "k"))
})

test_that("world_query validates every clause it interpolates", {
  for (a in c("source", "draw", "projection", "palette", "transform")) {
    args <- list(quote(gdp)); args[[a]] <- c("x", "y")
    expect_error(do.call(world_query, args), paste0("`", a, "`"))
    args[[a]] <- character(0)
    expect_error(do.call(world_query, args), "Got 0 values")
  }
  expect_error(world_query(gdp, title = c("x", "y")), "`title`")
  expect_error(world_query(gdp, title = NA), "`title`")
  expect_error(world_query(gdp, source = ""), "empty string")
  # A NULL optional clause is still omitted rather than validated.
  q <- world_query(gdp, projection = NULL, palette = NULL)
  expect_false(grepl("PROJECT TO|SCALE", q))
  # An empty title is legal SQL and stays allowed.
  expect_match(world_query(gdp, title = ""), "LABEL title => ''", fixed = TRUE)
  # Quote-doubling still protects a title containing an apostrophe.
  expect_match(world_query(gdp, title = "O'Brien"), "'O''Brien'", fixed = TRUE)
})

test_that("as_ggsql_source validates its names and path", {
  df <- data.frame(iso3c = "USA", value = 1)
  expect_error(as_ggsql_source(df, name = c("a", "b")), "`name`")
  expect_error(as_ggsql_source(df, name = ""), "empty string")
  expect_error(as_ggsql_source(df, geometry_col = NA), "`geometry_col`")
  expect_error(as_ggsql_source(df, format = "parquet", path = character(0)),
               "Got 0 values")
})

test_that("a parquet path is quoted as a SQL literal, not interpolated", {
  # The path went into sprintf("... TO '%s' ...") bare, so an apostrophe -- legal
  # in a filename -- closed the string literal early and broke the statement.
  skip_if_not_installed("DBI")
  q <- as.character(DBI::dbQuoteString(DBI::ANSI(), "a'b.parquet"))
  expect_equal(q, "'a''b.parquet'")
  # And the source no longer builds that clause by hand.
  src <- paste(deparse(countryatlas::as_ggsql_source), collapse = " ")
  expect_false(grepl("TO '%s'", src, fixed = TRUE))
  expect_true(grepl("dbQuoteString", src, fixed = TRUE))
})

# `suffix` is paste0()'d onto the value-column name to make the output column.
# paste0("g", character(0)) is character(0), and dplyr's "{character(0)}" := is a
# silent no-op -- so growth_rate(x, g, suffix = character(0)) returned the input
# frame with no growth column at all, the whole computation quietly skipped.
# suffix = NA produced a column called "gNA", and suffix = "" overwrote the
# source column in place.

test_that("suffix must be a single non-empty string", {
  panel <- data.frame(iso3c = rep(c("USA", "FRA"), each = 4),
                      year = rep(2000:2003, 2), g = c(1:4, 10:13),
                      population = 1e6)
  bad <- list(character(0), NA, "", c("_a", "_b"), 42)
  for (b in bad) {
    expect_error(growth_rate(panel, g, suffix = b), "`suffix`")
    expect_error(share_of_world(panel, g, suffix = b), "`suffix`")
    expect_error(index_to(panel, g, base_year = 2000, suffix = b), "`suffix`")
    expect_error(per_capita(panel, g, pop = population, suffix = b), "`suffix`")
    expect_error(lag_by_country(panel, g, suffix = b), "`suffix`")
    expect_error(diff_by_country(panel, g, suffix = b), "`suffix`")
  }
  expect_error(growth_rate(panel, g, suffix = character(0)), "Got 0 values")
  # The computed column is what was silently lost; make sure it is there now.
  expect_true("g_growth" %in% names(growth_rate(panel, g)))
  expect_true("g_pct" %in% names(growth_rate(panel, g, suffix = "_pct")))
  # lag/diff default to NULL, which must stay legal.
  expect_true("g_lag" %in% names(lag_by_country(panel, g)))
  expect_true("g_diff" %in% names(diff_by_country(panel, g)))
  expect_true("g_prev" %in% names(lag_by_country(panel, g, suffix = "_prev")))
})

test_that("join and grouping keys reject a zero-length value", {
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  # `by = character(0)` reached `if (logical(0))` -- base R's "argument is of
  # length zero", which names nothing.
  expect_error(attach_geometry(snap, by = character(0), geometry = "polygon"),
               "`by`")
  expect_error(attach_geometry(snap, by = NA, geometry = "polygon"), "`by`")
  # aggregate_regions() grouped by nothing and collapsed the world to one row.
  expect_error(aggregate_regions(snap, gdp_per_capita, by = character(0)),
               "at least one grouping column")
  expect_error(aggregate_regions(snap, gdp_per_capita, by = NA),
               "at least one grouping column")
  # `by` is documented as plural, so multiple columns must keep working.
  expect_gt(nrow(aggregate_regions(snap, gdp_per_capita,
                                   by = c("region", "income"))),
            nrow(aggregate_regions(snap, gdp_per_capita, by = "region")))
})

test_that("convert_country's to/from must be single strings", {
  # `to %in% names(m)` fed if() directly: a length-0 `to` gave base R's
  # "argument is of length zero" and a length-2 one "the condition has length
  # > 1" -- the R >= 4.2 hard error, and neither named the argument. Asking for
  # two destinations at once is a plausible thing to try.
  for (b in list(character(0), c("country", "continent"), NA, 42)) {
    # class = too: countrycode raises its own messages mentioning these names,
    # so matching on text alone would pass even with our guard removed.
    expect_error(convert_country("FRA", to = b, from = "iso3c"), "`to`")
    expect_error(convert_country("FRA", to = b, from = "iso3c"),
                 class = "countryatlas_error")
    expect_error(convert_country("FRA", to = "country", from = b), "`from`")
    expect_error(convert_country("FRA", to = "country", from = b),
                 class = "countryatlas_error")
  }
  expect_equal(convert_country("FRA", to = "country", from = "iso3c"), "France")
  expect_equal(convert_country("FRA", to = "name_fr", from = "iso3c"), "France")
})

test_that("origin is validated once, for every function that resolves names", {
  # Checked in wdj_to_iso3c(), the shared internal, so all of these are covered
  # by one guard. The message says `origin` even where the formal is `origin_x`,
  # which is the trade-off for fixing them at a single site.
  df <- data.frame(c = "France")
  for (b in list(character(0), c("country.name", "iso3c"), NA)) {
    # Assert our own condition class: countrycode's message for a length-2
    # origin also contains "`origin`", so a text match alone would still pass
    # with the guard removed.
    for (call in list(
      function() standardize_country(df, c, origin = b),
      function() country_join(data.frame(a = "France"), data.frame(b = "France"),
                              a, b, origin_x = b),
      function() distance_between("France", "Spain", origin = b))) {
      expect_error(call(), "`origin`")
      expect_error(call(), class = "countryatlas_error")
    }
  }
  expect_equal(nrow(standardize_country(df, c)), 1L)
  expect_equal(nrow(country_join(data.frame(a = "France"),
                                 data.frame(b = "France"), a, b)), 1L)
})

# Logical arguments split into two failure modes, both fixed by check_bool().
# The bare `if (borders)` sites raised one of four opaque base R errors, none
# naming the argument. The isTRUE() sites were quieter and worse: any non-TRUE
# value became FALSE, so the caller silently got the opposite of what they asked
# for -- `desc = "yes"` ranked ascending (rank 1 = the lowest value) and
# `na.rm = "yes"` kept the NAs and returned NA.

test_that("check_bool names the argument and what it got", {
  cb <- countryatlas:::check_bool
  expect_error(cb(NA, "k"), "must be `TRUE` or `FALSE`")
  expect_error(cb(NA, "k"), "Got NA")
  expect_error(cb(character(0), "k"), "Got 0 values")
  expect_error(cb(c(TRUE, FALSE), "k"), "Got 2 values")
  expect_error(cb("yes", "k"), 'Got "yes"')
  expect_error(cb(1, "k"), class = "countryatlas_error")   # strict, as rlang is
  expect_error(cb(NULL, "k"), "Got 0 values")
  expect_silent(cb(TRUE, "k"))
  expect_silent(cb(FALSE, "k"))
})

test_that("borders is validated instead of reaching a bare if()", {
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  mapdf <- attach_geometry(snap, geometry = "polygon")
  for (b in list(NA, character(0), c(TRUE, FALSE), "yes")) {
    expect_error(world_map(mapdf, gdp_per_capita, borders = b), "`borders`")
    expect_error(world_map(mapdf, gdp_per_capita, borders = b),
                 class = "countryatlas_error")
    expect_error(globe_map(snap, gdp_per_capita, backend = "polygon",
                           borders = b), "`borders`")
  }
  expect_s3_class(world_map(mapdf, gdp_per_capita, borders = FALSE), "ggplot")
  expect_s3_class(world_map(mapdf, gdp_per_capita, borders = TRUE), "ggplot")
})

test_that("a bad logical no longer silently means FALSE", {
  df <- data.frame(iso3c = c("AAA", "BBB", "CCC"), v = c(1, 3, 2))
  for (b in list(NA, character(0), c(TRUE, FALSE), "yes")) {
    expect_error(rank_countries(df, v, desc = b), "`desc`")
    expect_error(gini(c(1, 2, NA, 4), na.rm = b), "`na.rm`")
    expect_error(theil(c(1, 2, NA, 4), na.rm = b), "`na.rm`")
    expect_error(standardize_country(df, iso3c, warn = b), "`warn`")
    expect_error(dissolve_country("USSR", warn = b), "`warn`")
    expect_error(check_country_match("France", suggest = b), "`suggest`")
    expect_error(repair_country_names("Brzil", verbose = b), "`verbose`")
  }
  # desc still reverses the ranking, and row order is still left alone.
  asc <- rank_countries(df, v, desc = FALSE)
  dsc <- rank_countries(df, v, desc = TRUE)
  expect_equal(dsc$rank, c(3L, 1L, 2L))     # rank 1 = the largest value
  expect_equal(asc$rank, c(1L, 3L, 2L))
  expect_equal(dsc$iso3c, df$iso3c)
  # And na.rm still does both things.
  expect_equal(round(gini(c(1, 2, NA, 4), na.rm = TRUE), 4), 0.2857)
  expect_identical(gini(c(1, 2, NA, 4), na.rm = FALSE), NA_real_)
})

# gini()/theil() recycled `weights` and `groups` with rep_len(), which accepts
# any length silently. gini(1:10, weights = c(1, 2)) returned 0.2902 -- a
# plausible number computed from an alternating 1,2 pattern -- where the
# correctly-weighted answer is 0.3. A wrong number with no error is the worst
# failure mode in the package, so the lengths must line up.

test_that("weights and groups must line up with x", {
  x <- 1:10
  for (w in list(c(1, 2), c(1, 2, 3), rep(1, 11), rep(1, 9))) {
    expect_error(gini(x, weights = w), "`weights`")
    expect_error(gini(x, weights = w), "length 1 or length 10")
    expect_error(theil(x, weights = w), "`weights`")
  }
  for (g in list(c("a", "b"), rep("a", 11))) {
    expect_error(theil(x, groups = g), "`groups`")
  }
  expect_error(gini(x, weights = "a"), "must be numeric")
  expect_error(gini(x, weights = TRUE), "must be numeric")
  # Length 1 is a uniform weight and stays legal; so does the exact length.
  expect_equal(round(gini(x), 4), 0.3)
  expect_equal(round(gini(x, weights = 1), 4), 0.3)
  expect_equal(round(gini(x, weights = rep(1, 10)), 4), 0.3)
  # A genuinely weighted answer differs from the unweighted one, which is the
  # whole point of the argument.
  expect_false(isTRUE(all.equal(gini(x, weights = 10:1), gini(x))))
  expect_named(theil(x, groups = rep(c("a", "b"), 5)),
               c("component", "value", "share"))
})

test_that("complete_years rejects a years vector it cannot use", {
  # as.integer("a") is NA with only base R's coercion warning, and a zero-length
  # `years` silently completed nothing.
  df <- data.frame(iso3c = "A", year = c(2000L, 2002L), g = c(1, 3))
  expect_error(complete_years(df, years = "a"), "`years`")
  expect_error(complete_years(df, years = numeric(0)), "Got 0 values")
  expect_error(complete_years(df, years = c(2000, NA)), "`years`")
  expect_equal(nrow(complete_years(df, years = 2000:2002)), 3L)
  expect_equal(nrow(complete_years(df)), 3L)     # NULL means the observed span
})

# rlang::as_name() on a missing argument raised `argument "x" is missing, with no
# default` -- naming rlang's own parameter. None of these functions has an
# argument called `x`, so the message told a caller who simply forgot an
# argument nothing at all. standardize_country() already got this right; the
# rest now do too.

test_that("omitting a required argument names that argument", {
  skip_if_not_installed("maps")
  snap <- countryatlas::world_snapshot$countries
  mapdf <- attach_geometry(snap, geometry = "polygon")
  expect_error(world_map(mapdf), "`fill` is required")
  expect_error(tile_map(snap), "`fill` is required")
  expect_error(facet_map(snap, gdp_per_capita), "`facet` is required")
  expect_error(spike_map(snap), "`height` is required")
  expect_error(bubble_map(snap), "`size` is required")
  expect_error(globe_map(snap, backend = "polygon"), "`fill` is required")
  expect_error(rank_countries(snap), "`value` is required")
  expect_error(growth_rate(snap), "`value` is required")
  expect_error(per_capita(snap), "`value` is required")
  expect_error(aggregate_regions(snap), "`value` is required")
  expect_error(index_to(snap), "`value` is required")
  expect_error(share_of_world(snap), "`value` is required")
  expect_error(world_query(), "`fill` is required")
  expect_error(country_join(data.frame(x = 1), data.frame(y = 2)),
               "`by_x` is required")
  expect_error(flow_map(data.frame(f = "China", t = "USA", v = 1)),
               "`from` is required")
  expect_error(world_map(mapdf), class = "countryatlas_error")
  # Optional tidy-eval arguments must stay optional.
  expect_s3_class(suppressWarnings(bubble_map(snap, population)), "ggplot")
  expect_s3_class(suppressWarnings(tile_map(snap, gdp_per_capita)), "ggplot")
  expect_s3_class(world_map(mapdf, gdp_per_capita), "ggplot")
})

# distance_between() combined `a` and `b` through vectorised arithmetic, so R's
# recycling rules applied. Equal lengths and a length-1 side are the documented,
# useful idioms; anything else paired the wrong countries. 2 against 3 returned
# a[1]-b[1], a[2]-b[2] and a[1]-b[3] behind only base R's "longer object length"
# warning, and 2 against 4 recycled cleanly with no warning at all.

test_that("distance_between refuses lengths it would have mis-paired", {
  expect_error(distance_between(c("France", "Spain"),
                                c("Italy", "Germany", "Japan")), "`a`")
  expect_error(distance_between(c("France", "Spain"),
                                c("Italy", "Germany", "Japan")),
               "Got 2 and 3")
  # A clean multiple is just as wrong, and used to pass without any warning.
  expect_error(distance_between(c("France", "Spain"),
                                c("Italy", "Germany", "Japan", "Brazil")),
               class = "countryatlas_error")
  expect_error(distance_between(character(0), c("Italy", "Germany")), "`a`")

  # The documented idioms still work, and give the same answers as before.
  # These kilometre figures were cross-checked against
  # geosphere::distHaversine(r = 6371.0088), which agrees exactly; geosphere is
  # not a dependency, so the comparison is not run here.
  one <- distance_between("France", "Spain")
  expect_length(one, 1L)
  expect_equal(round(one), 847)
  many <- distance_between("France", c("Spain", "Italy", "Japan"))
  expect_length(many, 3L)
  expect_equal(round(many), c(847, 978, 9624))
  # Length 1 on either side.
  expect_equal(round(distance_between(c("Spain", "Italy", "Japan"), "France")),
               c(847, 978, 9624))
  expect_length(distance_between(c("France", "Spain"), c("Japan", "Japan")), 2L)
  # Equal lengths includes the empty case.
  expect_length(distance_between(character(0), character(0)), 0L)
})

test_that("locate_country's documented lon/lat contract matches its code", {
  # ?locate_country said lon/lat were "recycled together" while the code has
  # always required equal lengths. The doc now says equal-length; pin the
  # behaviour so the two cannot drift apart again.
  skip_if_no_sf_geometry()
  expect_error(locate_country(c(2.3, 10), 48.9), "equal-length")
  expect_error(locate_country(2.3, c(48.9, 50)), "equal-length")
  expect_equal(nrow(locate_country(c(2.3, 10), c(48.9, 50))), 2L)
  expect_equal(nrow(locate_country(2.3, 48.9)), 1L)
})

# A factor value column is easy to end up with -- read.csv() on a column holding
# one stray non-numeric entry produces one -- and arithmetic on it gave either a
# column of NAs behind base R's "'/' not meaningful for factors" (growth_rate,
# per_capita), an opaque error from inside dplyr (share_of_world,
# rank_countries, aggregate_regions), "missing value where TRUE/FALSE needed"
# (gini), or, worst of all, a plausible-looking result (morans_i).

test_that("a non-numeric value column is rejected by name and type", {
  panel <- tibble::tibble(iso3c = rep(c("USA", "FRA"), each = 3),
                          year = rep(2000:2002, 2), g = c(1, 2, 3, 10, 11, 12),
                          region = rep(c("A", "B"), each = 3), population = 1e6)
  for (bad in list(factor(panel$g), as.character(panel$g))) {
    d <- panel; d$g <- bad
    for (call in list(
      function() growth_rate(d, g), function() share_of_world(d, g),
      function() rank_countries(d, g), function() per_capita(d, g, pop = population),
      function() index_to(d, g, base_year = 2000),
      function() diff_by_country(d, g), function() beta_convergence(d, g),
      function() sigma_convergence(d, g),
      function() aggregate_regions(d, g, by = "region"))) {
      expect_error(call(), 'must be numeric')
      expect_error(call(), class = "countryatlas_error")
    }
    expect_error(gini(bad), "`x` must be numeric")
    expect_error(theil(bad), "`x` must be numeric")
  }
  # Numeric and integer columns are untouched.
  expect_true("g_growth" %in% names(growth_rate(panel, g)))
  panel$g <- as.integer(panel$g)
  expect_true("g_growth" %in% names(growth_rate(panel, g)))
})

test_that("lagging a categorical column is still allowed", {
  # lag_by_country() does no arithmetic, so a factor or character column is a
  # legitimate thing to lag; it is deliberately left permissive.
  d <- tibble::tibble(iso3c = rep("USA", 3), year = 2000:2002,
                      g = factor(c("low", "mid", "high")))
  expect_no_error(lag_by_country(d, g))
  d$g <- as.character(d$g)
  expect_no_error(lag_by_country(d, g))
  expect_equal(lag_by_country(d, g)$g_lag, c(NA, "low", "mid"))
})

test_that("morans_i no longer accepts a factor and returns a number anyway", {
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  snap$gg <- factor(round(snap$gdp_per_capita))
  expect_error(morans_i(snap, gg, n_perm = 0), "must be numeric")
  expect_false(is.na(morans_i(snap, gdp_per_capita, n_perm = 0)$i))
})

test_that("a factor iso3c changes only row order, never a value", {
  # dplyr groups by factor level rather than alphabetically, so the output rows
  # come back in a different order. The values still attach to the right
  # countries, which is what matters; recorded here so it is not mistaken for a
  # bug later.
  chr <- tibble::tibble(iso3c = rep(c("USA", "FRA"), each = 3),
                        year = rep(2000:2002, 2), g = c(1, 2, 3, 10, 11, 12))
  fac <- chr
  fac$iso3c <- factor(fac$iso3c, levels = c("USA", "FRA", "ZZZ"))
  norm <- function(d) {
    d <- tibble::as_tibble(dplyr::ungroup(d))
    d$iso3c <- as.character(d$iso3c)
    d[order(d$iso3c, d$year), ]
  }
  for (f in list(function(d) growth_rate(d, g), function(d) lag_by_country(d, g),
                 function(d) complete_years(d, value = "g"))) {
    expect_equal(norm(f(chr)), norm(f(fac)), ignore_attr = TRUE)
  }
  # And an unused level does not become a phantom row.
  expect_false("ZZZ" %in% as.character(complete_years(fac, value = "g")$iso3c))
})

test_that("world_map()/globe_map() label and palette arguments are checked", {
  # These four reached viridisLite and ggplot2 unchecked, so the failures came
  # back in their vocabulary, not the package's: a length-2 `palette` hit a bare
  # switch() and produced "EXPR must be a length 1 vector", and a numeric one was
  # accepted without a word. world_query() already validated the same arguments.
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  sfd <- attach_geometry(snap, geometry = "sf")

  for (bad in list("", c("magma", "viridis"), 1, NA_character_)) {
    expect_error(world_map(sfd, gdp_per_capita, palette = bad),
                 class = "countryatlas_error",
                 info = paste(deparse(bad), collapse = ""))
    expect_error(globe_map(sfd, gdp_per_capita, backend = "sf", palette = bad),
                 class = "countryatlas_error",
                 info = paste(deparse(bad), collapse = ""))
  }
  expect_error(world_map(sfd, gdp_per_capita, title = c("a", "b")),
               "must be a single value")
  expect_error(world_map(sfd, gdp_per_capita, legend = c("a", "b")),
               "must be a single value")
  expect_warning(world_map(sfd, gdp_per_capita, style = "quantile",
                           na_label = c("a", "b")), "labels one key")

  # The legal values still pass, including the documented NA and empty labels.
  expect_s3_class(world_map(sfd, gdp_per_capita, palette = "magma"), "ggplot")
  expect_s3_class(world_map(sfd, gdp_per_capita, title = "", legend = ""), "ggplot")
  expect_s3_class(world_map(sfd, gdp_per_capita, style = "quantile",
                            na_label = NA), "ggplot")
  # A number is fine as a *label* -- ggplot2 renders it -- just not as a palette.
  expect_s3_class(world_map(sfd, gdp_per_capita, title = 2024), "ggplot")
})

test_that("latest= and panel= say which one they are dropping", {
  # A year range silently overrode `latest`, while a single year had `latest`
  # silently override `panel` -- opposite precedence, neither announced.
  fake <- function(country, indicator, start, end, extra = FALSE, ...) {
    out <- expand.grid(iso2c = c("US", "FR"), year = start:end,
                       stringsAsFactors = FALSE)
    out$country <- ifelse(out$iso2c == "US", "United States", "France")
    # names(indicator) is what the real WDI names the value column after; it
    # equals the code here only because the caller passes an unnamed one.
    nm <- names(indicator)[1]
    out[[if (is.null(nm) || !nzchar(nm)) indicator[[1]] else nm]] <- out$year * 1.0
    out
  }
  testthat::with_mocked_bindings(.package = "WDI", WDI = fake, {
    expect_warning(
      country_data(2010:2012, "NY.GDP.PCAP.CD", latest = TRUE,
                   cache = FALSE, parallel = FALSE),
      "`latest` is ignored")
    expect_warning(
      country_data(2015, "NY.GDP.PCAP.CD", latest = TRUE, panel = TRUE,
                   cache = FALSE, parallel = FALSE),
      "`panel` is ignored")
    expect_warning(
      world_data(2010:2012, "NY.GDP.PCAP.CD", geometry = "none", latest = TRUE,
                 cache = FALSE, parallel = FALSE),
      "`latest` is ignored")
    # No conflict, no warning -- and the shapes are unchanged by the fix.
    expect_silent(one <- country_data(2015, "NY.GDP.PCAP.CD", cache = FALSE,
                                      parallel = FALSE))
    expect_false("year" %in% names(one))
    expect_silent(pan <- country_data(2010:2012, "NY.GDP.PCAP.CD",
                                      cache = FALSE, parallel = FALSE))
    expect_true("year" %in% names(pan))
  })
})

# One block per argument. A bare error inside a test_that() aborts the rest of
# that block, so a single mega-block lets the first bad value mask every
# assertion after it -- which is exactly how the k/itermax checks below first
# went in toothless. Each assertion also matches the argument NAME, not just the
# condition class: dorling_map() on a non-sf frame raises countryatlas_error for
# the frame's shape, so a class-only expectation passes whatever k is.

test_that("locate_country validates tolerance_km", {
  # `dkm <= tolerance_km` compares as *strings* when the tolerance is character,
  # and "2650" <= "a" is TRUE, so every unmatched point snapped to its nearest
  # country -- a mid-Pacific point came back as Fiji, inverting the documented
  # "open ocean stays NA".
  for (bad in list(NA, "a", c(1, 2), -5)) {
    expect_error(locate_country(lon = 0, lat = 0, tolerance_km = bad),
                 "tolerance_km", info = paste(deparse(bad), collapse = ""))
  }
  skip_if_no_sf_geometry()
  expect_identical(locate_country(lon = -140, lat = -20, tolerance_km = 25)$iso3c,
                   NA_character_)
})

test_that("correlate_indicators validates min_n", {
  snap <- countryatlas::world_snapshot$countries
  for (bad in list(NA, "a", c(1, 2), -5)) {
    expect_error(correlate_indicators(snap, min_n = bad),
                 "min_n", info = paste(deparse(bad), collapse = ""))
  }
  expect_s3_class(correlate_indicators(snap, min_n = 5), "tbl_df")
})

test_that("dorling_map validates k and itermax", {
  # An sf frame, so the only thing left to reject is the scalar.
  skip_if_no_sf_geometry()
  skip_if_not_installed("cartogram")
  sfd <- attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf")
  for (bad in list(NA, "a", c(1, 2), -1)) {
    lbl <- paste(deparse(bad), collapse = "")
    expect_error(dorling_map(sfd, population, k = bad), "`k`", info = lbl)
    expect_error(dorling_map(sfd, population, itermax = bad), "itermax", info = lbl)
  }
})

test_that("a bad argument is reported before any optional-package gate", {
  # A mistyped column or an out-of-range scalar is the caller's bug; the message
  # must not depend on which optional packages happen to be installed. With
  # every optional package reported absent, each verb must still name the
  # argument. (spin_globe had this for its scalars but not for `fill`, and
  # interactive_map(engine = "ggsql") reported a missing ggsql for a non-sf
  # frame -- a package that has not shipped in the R bindings at all.)
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  sfd <- attach_geometry(snap, geometry = "sf")

  testthat::with_mocked_bindings(has_pkg = function(...) FALSE, {
    expect_error(spin_globe(sfd, nosuchcol), "not found in")
    expect_error(interactive_map(snap, gdp_per_capita, engine = "ggsql"),
                 "needs an sf frame")
    expect_error(locate_country(lon = 1, lat = 1, tolerance_km = -5),
                 "tolerance_km")
    expect_error(dorling_map(sfd, nosuchcol), "not found in")
    expect_error(cartogram_map(sfd, nosuchcol), "not found in")
  })
})

test_that("the verbs say when they overwrite a column the caller already had", {
  # A user's own `rank`, `percentile` or `<value>_share` column was replaced in
  # silence. Warn rather than error: re-running a verb on its own output is
  # legitimate and idempotent, it just should not be invisible.
  d <- tibble::tibble(iso3c = c("USA", "FRA", "CHN"), year = 2000L,
                      v = c(3, 1, 2), population = c(3e8, 7e7, 1.4e9))
  expect_warning(rank_countries(dplyr::mutate(d, rank = 999), v),
                 "Overwriting 1 existing column")
  expect_warning(rank_countries(dplyr::mutate(d, rank = 1, z_score = 1), v),
                 "Overwriting 2 existing columns")
  expect_warning(per_capita(dplyr::mutate(d, v_per_capita = -1), v,
                            pop = population), "v_per_capita")
  expect_warning(share_of_world(dplyr::mutate(d, v_share = -1), v), "v_share")
  expect_warning(index_to(dplyr::mutate(d, v_index = -1), v, base_year = 2000),
                 "v_index")
  pan <- tibble::tibble(iso3c = "USA", year = 2000:2002, v = c(1, 2, 4))
  expect_warning(lag_by_country(dplyr::mutate(pan, v_lag = -1), v), "v_lag")
  expect_warning(diff_by_country(dplyr::mutate(pan, v_diff = -1), v), "v_diff")
  expect_warning(growth_rate(dplyr::mutate(pan, v_growth = -1), v), "v_growth")

  # The value written is the freshly computed one, not the stale column.
  expect_warning(o <- share_of_world(dplyr::mutate(d, v_share = -1), v))
  expect_equal(sum(o$v_share), 1)

  # No warning when there is nothing to overwrite, or when a suffix avoids it.
  expect_silent(rank_countries(d, v))
  expect_silent(per_capita(d, v, pop = population))
  expect_silent(per_capita(dplyr::mutate(d, v_per_capita = -1), v,
                           pop = population, suffix = "_pc"))
  # standardize_country() is deliberately exempt: `add` names the column
  # literally, so replacing it is what was asked for.
  expect_silent(standardize_country(
    tibble::tibble(country = "France", continent = "MINE"), "country",
    add = "continent"))
})

test_that("every numeric bound is pinned at its own edge", {
  # A test that rejects -5 where the bound is 0 cannot tell lo = 0 from lo = -1:
  # loosening the bound by one goes undetected. Verified by mutation --
  # tolerance_km's bound survived a 0 -> -1 shift because its only rejection
  # test used -5. So assert the value *immediately* outside each bound, and the
  # boundary value itself, which iteration-24's lesson says must actually work.
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  sfd <- attach_geometry(snap, geometry = "sf")
  poly <- if (requireNamespace("maps", quietly = TRUE)) {
    attach_geometry(snap, geometry = "polygon")
  } else NULL
  pan <- tibble::tibble(iso3c = "A", year = 2000:2002, v = c(1, 2, 3))
  flows <- tibble::tibble(f = "France", t = "Japan")

  # arg, caller, just-below (or NULL), the bound value itself, just-above
  cases <- list(
    list("alpha", function(v) bubble_map(sfd, population, backend = "sf", alpha = v),
         -1, 0, NULL),
    list("alpha_hi", function(v) bubble_map(sfd, population, backend = "sf", alpha = v),
         NULL, 1, 1.5),
    list("max_size", function(v) bubble_map(sfd, population, backend = "sf", max_size = v),
         -1, 0, NULL),
    list("n_bins", function(v) world_map(sfd, gdp_per_capita, style = "quantile", n_bins = v),
         1, 2, NULL),
    list("lat", function(v) globe_map(sfd, gdp_per_capita, backend = "sf", lat = v),
         -91, -90, 91),
    list("lon", function(v) globe_map(sfd, gdp_per_capita, backend = "sf", lon = v),
         -361, -360, 361),
    list("recenter", function(v) world_map(sfd, gdp_per_capita, recenter = v),
         -361, -360, 361),
    list("tolerance_km", function(v) locate_country(lon = 2.3, lat = 48.8, tolerance_km = v),
         -1, 0, NULL),
    list("n_perm", function(v) morans_i(sfd, gdp_per_capita, n_perm = v), -1, 0, NULL),
    list("min_n", function(v) correlate_indicators(snap, min_n = v), 0, 1, NULL),
    list("threshold", function(v) repair_country_names("Frnace", threshold = v,
                                                      verbose = FALSE), -1, 0, 1.5),
    list("keep", function(v) simplify_geometry(sfd, keep = v), -1, 1, 1.5),
    list("flow_n", function(v) flow_map(flows, f, t, n = v), 1, 2, NULL),
    list("lag_n", function(v) lag_by_country(pan, v, n = v), 0, 1, NULL)
  )
  if (!is.null(poly)) {
    cases <- c(cases, list(
      list("max_height", function(v) spike_map(poly, population, max_height = v),
           -1, 0, NULL),
      list("spike_width", function(v) spike_map(poly, population, width = v),
           -1, 0, NULL)))
  }
  if (requireNamespace("cartogram", quietly = TRUE)) {
    cases <- c(cases, list(
      list("itermax", function(v) dorling_map(sfd, population, itermax = v), 0, 1, NULL)))
  }

  # globe_map's own lat/lon checks are only pinnable on the *polygon* backend:
  # the sf path also runs wdj_crs(), which rejects the same values, so loosening
  # one guard leaves the other refusing and no end-to-end test can tell. (The
  # redundancy is deliberate -- the polygon backend never calls wdj_crs().)
  # backend = "polygon" needs mapproj as well as maps.
  if (requireNamespace("maps", quietly = TRUE) &&
      requireNamespace("mapproj", quietly = TRUE)) {
    cases <- c(cases, list(
      list("poly_lat", function(v) globe_map(poly, gdp_per_capita,
                                            backend = "polygon", lat = v),
           -91, -90, 91),
      list("poly_lon", function(v) globe_map(poly, gdp_per_capita,
                                             backend = "polygon", lon = v),
           -361, -360, 361)))
  }

  for (cs in cases) {
    nm <- cs[[1]]; call <- cs[[2]]
    if (!is.null(cs[[3]])) {
      expect_error(call(cs[[3]]), class = "countryatlas_error",
                   info = paste(nm, "just below the bound:", cs[[3]]))
    }
    # The bound itself is legal and must build, not merely validate.
    expect_no_error(force(call(cs[[4]])))
    if (!is.null(cs[[5]])) {
      expect_error(call(cs[[5]]), class = "countryatlas_error",
                   info = paste(nm, "just above the bound:", cs[[5]]))
    }
  }
})

test_that("dorling_map rejects k = 0, which cartogram cannot use", {
  # check_number()'s bounds are inclusive, so lo = 0 admitted a zero that
  # cartogram then reported as "all sizes are missing and/or non-positive" --
  # a validator letting through a value the next layer cannot represent, which
  # is the same hole the integer.max ceilings were added to close. Anything
  # above zero is fine.
  skip_if_no_sf_geometry()
  skip_if_not_installed("cartogram")
  sfd <- attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf")
  expect_error(dorling_map(sfd, population, k = 0), "greater than 0",
               class = "countryatlas_error")
  expect_no_error(force(dorling_map(sfd, population, k = 1e-6)))
})

test_that("a user column named like an internal temp column is harmless", {
  # The package builds a few dot-prefixed working columns -- `.wdj_pop`,
  # `.wdj_bin`, `.from_iso`, `.to_iso`, `.id` -- and a user frame is perfectly
  # entitled to carry a column of the same name. Nothing may break, and the
  # answer must not change. (An earlier pass reported per_capita() failing on a
  # user `.wdj_pop`; that turned out to be the probe's WDI mock, not a
  # collision -- the control failed identically without the column.)
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  d <- snap[1:6, c("iso3c", "country", "continent", "gdp_per_capita",
                   "population")]
  sfd <- attach_geometry(snap, geometry = "sf")

  # per_capita with an explicit `pop` never touches `.wdj_pop`...
  ref <- per_capita(d, gdp_per_capita, pop = population)$gdp_per_capita_per_capita
  poisoned <- d
  poisoned$.wdj_pop <- -1
  got <- per_capita(poisoned, gdp_per_capita,
                    pop = population)$gdp_per_capita_per_capita
  expect_identical(got, ref)

  # ...but the *fetch* branch joins on that name, and a caller's column of the
  # same name collided: dplyr suffixed both sides to `.wdj_pop.x`/`.wdj_pop.y`,
  # `data[[".wdj_pop"]]` came back NULL, and the division died with base R's
  # "replacement has 0 rows, data has 2". Reaching this branch needs a WDI mock
  # that honours `names(indicator)` -- the real WDI names the value column after
  # the name it is given, and a mock that ignores that makes the fetch look
  # broken instead of exercising it.
  fake_wdi <- function(country, indicator, start, end, extra = FALSE, ...) {
    nm <- if (!is.null(names(indicator)) && nzchar(names(indicator)[1])) {
      names(indicator)[1]
    } else {
      indicator[[1]]
    }
    out <- data.frame(iso2c = c("US", "FR"), year = end,
                      stringsAsFactors = FALSE)
    out$country <- c("United States", "France")
    out[[nm]] <- c(330e6, 67e6)
    out
  }
  testthat::with_mocked_bindings(.package = "WDI", WDI = fake_wdi, {
    flat <- data.frame(iso3c = c("USA", "FRA"), gdp = c(21e12, 2.6e12))
    clean <- per_capita(flat, gdp, cache = FALSE)$gdp_per_capita
    dirty <- flat
    dirty$.wdj_pop <- -1
    expect_identical(per_capita(dirty, gdp, cache = FALSE)$gdp_per_capita, clean)
    expect_false(".wdj_pop" %in% names(per_capita(dirty, gdp, cache = FALSE)))
    # The panel branch takes the other join and must survive it too.
    pan <- data.frame(iso3c = rep(c("USA", "FRA"), each = 2),
                      year = c(2022, 2023, 2022, 2023), gdp = 1:4)
    pan$.wdj_pop <- -1
    # The point here is the column collision, not the fetched population, which
    # in this stubbed environment is unusable and now says so.
    expect_identical(nrow(suppressWarnings(
      per_capita(pan, gdp, cache = FALSE))), 4L)
  })

  # share_of_world computes its total in a local, so `.wdj_tot` cannot collide.
  ref2 <- share_of_world(d, population)$population_share
  d2 <- d
  d2$.wdj_tot <- -1
  expect_identical(share_of_world(d2, population)$population_share, ref2)

  # The binning column is overwritten, not merged.
  bins <- function(x) {
    levels(ggplot2::ggplot_build(
      world_map(x, gdp_per_capita, style = "quantile"))$plot$data$.wdj_bin)
  }
  sfd2 <- sfd
  sfd2$.wdj_bin <- "mine"
  expect_identical(bins(sfd2), bins(sfd))

  # flow_map builds .id/.from_iso/.to_iso on the frame it was handed.
  skip_if_not_installed("maps")
  flows <- data.frame(f = c("France", "China"), t = c("Japan", "Brazil"))
  n_arcs <- function(x) nrow(ggplot2::ggplot_build(flow_map(x, f, t))$data[[2]])
  base <- n_arcs(flows)
  for (col in c(".id", ".from_iso", ".to_iso")) {
    poisoned <- flows
    poisoned[[col]] <- if (col == ".id") 99 else "XX"
    expect_identical(n_arcs(poisoned), base, info = col)
  }
})


test_that("unknown-name errors survive a numeric argument", {
  # These messages put the pluralisation marker ahead of the value:
  # "Unknown group{?s}: {.val {bad}}". With no quantity set, cli reaches for
  # the most recent interpolation -- and a *numeric* vector there is read as
  # the quantity itself, which must be length 1. A length-2 numeric therefore
  # died on cli's own "length(object) == 1 is not TRUE" instead of reporting
  # the bad input. Character vectors worked, which is why it stayed hidden.
  #
  # cli::qty(length(x)) states the count outright. Note qty(x) is NOT enough
  # when x is numeric: it hits the same trap, because cli reads the numeric as
  # the count. That is the form reporting.R already uses.
  d <- data.frame(iso3c = c("FRA", "DEU"), year = 2020L, value = c(1, 2),
                  stringsAsFactors = FALSE)
  numeric_cases <- list(
    "country_groups"  = function(v) country_groups(v),
    "check_cols"      = function(v) countryatlas:::check_cols(d, v),
    "world_table"     = function(v) world_table(countryatlas::world_snapshot$countries,
                                                gdp_per_capita, columns = v)
  )
  for (nm in names(numeric_cases)) {
    for (v in list(1, c(1, 2), c(1, 2, 3))) {
      expect_error(numeric_cases[[nm]](v), class = "countryatlas_error",
                   info = paste(nm, length(v)))
    }
  }
  # Singular and plural both read correctly, for numeric and character alike.
  expect_error(country_groups(1), "Unknown group:")
  expect_error(country_groups(c(1, 2)), "Unknown groups:")
  expect_error(country_groups("nope"), "Unknown group:")
  expect_error(country_groups(c("a", "b")), "Unknown groups:")
  expect_error(countryatlas:::check_cols(d, 1), "^Column ")
  expect_error(countryatlas:::check_cols(d, c(1, 2)), "^Columns ")
  expect_error(countryatlas:::check_cols(d, "zz"), "^Column ")
  expect_error(countryatlas:::check_cols(d, c("zz", "yy")), "^Columns ")
  # A valid group is still accepted.
  expect_s3_class(country_groups("EU"), "data.frame")
})

test_that("the scalar validators can report a function or environment", {
  # These build their message with {.val {x}}, which coerces to character --
  # and that fails outright for a closure ("cannot coerce type 'closure' to
  # vector of type 'character'"). So the validator's own error crashed rather
  # than reporting the bad input, and every caller inherited it: passing a
  # function to register_country_source(), clear_country_cache(),
  # as_ggsql_source() or world_query() gave a bare simpleError from base R.
  #
  # length() is no help either -- length() of a closure is 1, so the
  # length branch never caught it, and length(globalenv()) counts bindings, so
  # an environment reported "Got 5 values".
  validators <- c("check_string", "check_bool", "check_number", "check_top_n")
  awkward <- list(fn = mean, env = globalenv(), lst = list(1, 2),
                  frm = y ~ x, mat = matrix(1:4, 2))
  for (v in validators) {
    f <- get(v, envir = asNamespace("countryatlas"))
    for (nm in names(awkward)) {
      expect_error(f(awkward[[nm]], "myarg"), class = "countryatlas_error",
                   info = paste(v, nm))
    }
  }
  # The message names the class rather than trying to print the value.
  expect_error(countryatlas:::check_string(mean, "myarg"), "<function>")
  expect_error(countryatlas:::check_string(globalenv(), "myarg"), "<environment>")
  expect_error(countryatlas:::check_number(mean, "myarg"), "<function>")
  # Ordinary values are unaffected, including the counts and the value itself.
  expect_error(countryatlas:::check_string(c("a", "b"), "myarg"), "Got 2 values")
  expect_error(countryatlas:::check_string(1, "myarg"), "Got 1")
  expect_error(countryatlas:::check_bool("yes", "myarg"), '"yes"')
  expect_silent(countryatlas:::check_string("ok", "myarg"))
  expect_silent(countryatlas:::check_bool(TRUE, "myarg"))
  expect_silent(countryatlas:::check_number(5, "myarg"))

  # And the public callers that surfaced it now fail cleanly.
  expect_error(register_country_source(mean, function(...) NULL),
               class = "countryatlas_error")
  expect_error(clear_country_cache(source = mean), class = "countryatlas_error")
  expect_error(world_query(gdp_per_capita, source = mean),
               class = "countryatlas_error")
})

test_that("arguments used before validation still refuse a function cleanly", {
  # Sibling of the scalar-validator fix above, but a different mechanism: here
  # the value was *consumed* before any check ran, so the crash came from the
  # consuming call rather than from the message.
  #   check_choice()   - as.character(x) on the default-detection line
  #   country_groups() - setdiff(group, valid) coerces
  #   complete_years() - anyNA(years) errors on an environment, inside the
  #                      condition of the guard meant to catch it
  d <- data.frame(iso3c = rep(c("FRA", "DEU"), each = 2),
                  year = rep(2000:2001, 2), value = 1:4,
                  stringsAsFactors = FALSE)
  awkward <- list(fn = mean, env = globalenv())
  for (nm in names(awkward)) {
    v <- awkward[[nm]]
    expect_error(countryatlas:::check_choice(v, "k", c("a", "b")),
                 class = "countryatlas_error", info = nm)
    expect_error(country_groups(v), class = "countryatlas_error", info = nm)
    expect_error(complete_years(d, years = v, value = "value"),
                 class = "countryatlas_error", info = nm)
  }
  # A formula reaches setdiff()'s duplicated(), which also refuses it.
  expect_error(country_groups(y ~ x), class = "countryatlas_error")
  # Each names the class rather than trying to print the value.
  expect_error(countryatlas:::check_choice(mean, "k", c("a", "b")), "<function>")
  expect_error(country_groups(mean), "<function>")
  expect_error(complete_years(d, years = mean, value = "value"), "<function>")

  # Ordinary values keep their existing behaviour.
  expect_equal(countryatlas:::check_choice("a", "k", c("a", "b")), "a")
  expect_equal(countryatlas:::check_choice(c("a", "b"), "k", c("a", "b")), "a")
  expect_error(countryatlas:::check_choice("zz", "k", c("a", "b")), 'Got "zz"')
  expect_s3_class(country_groups("EU"), "data.frame")
  expect_error(country_groups("nope"), "Unknown group:")
  expect_s3_class(complete_years(d, years = 2000:2002, value = "value"),
                  "data.frame")
  expect_error(complete_years(d, years = "a", value = "value"),
               class = "countryatlas_error")
})

test_that("a units value is refused by us, not by the units package", {
  # sf's st_area() and st_distance() return units objects, so a threshold
  # computed from geometry and handed to a numeric argument is a natural
  # mistake. is.numeric() is TRUE for one, so it passed the type check, and
  # the *range comparison* then raised the units package's own "both operands
  # of the expression should be units objects" -- naming neither the argument
  # nor this package.
  skip_if_not_installed("units")
  u <- units::set_units(5, "km")
  for (f in list(function(v) countryatlas:::check_number(v, "cutoff_km"),
                 function(v) countryatlas:::check_top_n(v))) {
    expect_error(f(u), class = "countryatlas_error")
    expect_error(f(u), "plain number")
    expect_error(f(u), "<units>")
  }
  # The hint tells the caller what to do, and names their argument.
  expect_error(countryatlas:::check_number(u, "cutoff_km"), "as.numeric\\(cutoff_km\\)")
  # Converting is accepted.
  expect_silent(countryatlas:::check_number(as.numeric(u), "cutoff_km"))

  # Everything that already worked is untouched, including a classed numeric
  # that *can* be compared, and a named scalar.
  expect_silent(countryatlas:::check_number(5, "k"))
  expect_silent(countryatlas:::check_number(structure(5, class = "myclass"), "k"))
  expect_silent(countryatlas:::check_number(c(a = 5), "k"))
  expect_silent(countryatlas:::check_top_n(5))
  expect_silent(countryatlas:::check_top_n(Inf))
  expect_error(countryatlas:::check_number(-1, "k", lo = 0), "between 0 and Inf")
  expect_error(countryatlas:::check_top_n(0), "at least 1")
})

test_that("every custom_match entry must be named", {
  x <- c("France", "Freedonia", "Germany")
  # Works, and is the shape country_overrides() returns.
  expect_equal(convert_country(x, to = "iso3c", custom_match = c(Freedonia = "FRA")),
               c("FRA", "FRA", "DEU"))

  # The bug: is.null(names()) passes a partly named vector, and the unnamed
  # entry can never match, so it was silently dead.
  for (bad in list(c(Freedonia = "FRA", "DEU"),
                   stats::setNames("FRA", ""),
                   stats::setNames("FRA", NA_character_))) {
    expect_error(convert_country(x, to = "iso3c", custom_match = bad),
                 "must be a named character vector", class = "countryatlas_error")
  }
  # The wholly unnamed and wrong-type cases still error as before.
  expect_error(convert_country(x, to = "iso3c", custom_match = c("FRA")),
               "no names", class = "countryatlas_error")
  expect_error(convert_country(x, to = "iso3c", custom_match = c(Freedonia = 1)),
               class = "countryatlas_error")
  # Zero-length means "no overrides", not a malformed one. It warns about
  # "Freedonia", which is the point of having no override for it.
  expect_no_error(suppressWarnings(
    convert_country(x, to = "iso3c", custom_match = character(0))))
  expect_warning(convert_country(x, to = "iso3c", custom_match = character(0)),
                 "could not be matched")

  # Values are deliberately not checked against the ISO list: the package's own
  # overrides map Kosovo to XKX, which is not in countrycode's iso3c column.
  expect_false("XKX" %in% countrycode::codelist$iso3c)
  expect_equal(unname(country_overrides()[["Kosovo"]]), "XKX")
  expect_no_error(convert_country("Kosovo", to = "iso3c",
                                  custom_match = country_overrides()))
  expect_true(all(nzchar(names(country_overrides()))))
})

test_that("a custom weights matrix must be non-negative and finite", {
  iso <- c("FRA", "DEU", "ITA", "ESP")
  good <- matrix(0, 4, 4, dimnames = list(iso, iso))
  good[1, 2] <- good[2, 1] <- good[2, 3] <- good[3, 2] <- 1
  expect_s3_class(country_weights("custom", w = good), "countryatlas_weights")

  # The bug: row standardisation divides by the row sum, so a negative weight
  # silently moved the statistic, and an all-negative matrix cancelled to
  # exactly the all-positive answer.
  neg <- good; neg[1, 2] <- neg[2, 1] <- -1
  expect_error(country_weights("custom", w = neg), "non-negative",
               class = "countryatlas_error")
  expect_error(country_weights("custom", w = -good), "non-negative",
               class = "countryatlas_error")
  # The bug: an infinite weight normalised to NaN and the verb then blamed
  # connectivity instead of the weight.
  inf <- good; inf[1, 2] <- Inf
  expect_error(country_weights("custom", w = inf), "finite",
               class = "countryatlas_error")

  # The long-frame form takes the same two checks.
  lf <- data.frame(iso3c = c("FRA", "DEU"), neighbor = c("DEU", "FRA"),
                   weight = c(1, 1), stringsAsFactors = FALSE)
  expect_s3_class(country_weights("custom", w = lf), "countryatlas_weights")
  expect_error(country_weights("custom", w = transform(lf, weight = c(1, -1))),
               "non-negative", class = "countryatlas_error")
  expect_error(country_weights("custom", w = transform(lf, weight = c(1, Inf))),
               "finite", class = "countryatlas_error")

  # What was already accepted stays accepted: zeros, a plain adjacency, an
  # asymmetric matrix and a non-zero diagonal are all legitimate.
  # An all-zero matrix is accepted, and says so -- it links nobody.
  zero <- matrix(0, 4, 4, dimnames = list(iso, iso))
  expect_warning(country_weights("custom", w = zero), "link no countries")
  expect_s3_class(suppressWarnings(country_weights("custom", w = zero)),
                  "countryatlas_weights")
  asym <- good; asym[1, 2] <- 5
  expect_s3_class(country_weights("custom", w = asym), "countryatlas_weights")
  dg <- good; diag(dg) <- 1
  expect_s3_class(country_weights("custom", w = dg), "countryatlas_weights")

  # Every built-in constructor satisfies the checks it now imposes on callers.
  # knn and distance work off the bundled centroids; contiguity needs sf, so it
  # is only exercised where sf is present -- without this the test fails under
  # _R_CHECK_DEPENDS_ONLY_ with sf's "is required" rather than anything to do
  # with weights.
  types <- list(list("knn", k = 4), list("distance", cutoff_km = 3000))
  if (requireNamespace("sf", quietly = TRUE)) {
    types <- c(list(list("contiguity")), types)
  }
  for (ty in types) {
    m <- as.matrix(suppressWarnings(do.call(country_weights, ty)))
    expect_true(all(is.finite(m)))
    expect_true(all(m >= 0))
    expect_s3_class(suppressWarnings(country_weights("custom", w = m)),
                    "countryatlas_weights")
  }
})

test_that("as_ggsql_source() checks its data and its connection", {
  # The data check fires before need_pkg(), so it holds with no DBI installed.
  expect_error(as_ggsql_source(1:5), "must be a data frame",
               class = "countryatlas_error")
  expect_error(as_ggsql_source(NULL), "must be a data frame",
               class = "countryatlas_error")
  expect_error(as_ggsql_source("a"), class = "countryatlas_error")

  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  snap <- countryatlas::world_snapshot$countries[1:5, c("iso3c", "gdp_per_capita")]

  # A connection the caller opened stays open; one the function opened is its
  # own business.
  # wdj_duckdb(), not duckdb::duckdb(): the wrapper passes shared_home = FALSE,
  # which is what silences duckdb's ?duckdb_storage notice.
  cn <- DBI::dbConnect(countryatlas:::wdj_duckdb())
  # suppressWarnings as well as try(): the test closes `cn` itself below, so
  # this second disconnect warns rather than errors, and try() only catches
  # errors.
  on.exit(suppressWarnings(try(DBI::dbDisconnect(cn, shutdown = TRUE),
                               silent = TRUE)), add = TRUE)
  out <- suppressWarnings(suppressMessages(as_ggsql_source(snap, con = cn)))
  expect_s4_class(out, "duckdb_connection")
  expect_true(DBI::dbIsValid(cn))

  # The bug: a closed connection reached dbWriteTable() as a bare
  # "Invalid connection".
  DBI::dbDisconnect(cn, shutdown = TRUE)
  expect_error(as_ggsql_source(snap, con = cn), "closed",
               class = "countryatlas_error")
  # And something that is not a connection at all.
  expect_error(as_ggsql_source(snap, con = 42), "DBIConnection",
               class = "countryatlas_error")

  # What already worked keeps working.
  expect_no_error(suppressWarnings(suppressMessages(as_ggsql_source(snap))))
  expect_no_error(suppressWarnings(suppressMessages(as_ggsql_source(snap[0, ]))))
})

# quo_arg_name() tells the user a column may be passed unquoted "or as a
# string", and check_cols() then validates the string. The plotting verbs
# spliced the raw quosure into aes() anyway, so the string form mapped the
# constant "value" and died inside ggplot2 at *build* time with "Discrete
# value supplied to a continuous scale" -- naming neither the argument nor the
# fix. world_map(d, "value") was affected: the package's most common call.
test_that("map verbs accept a column named as a string, not only unquoted", {
  skip_if_not_installed("maps")
  skip_if_not_installed("ggplot2")
  d <- data.frame(
    iso3c = c("FRA", "DEU", "ITA", "ESP", "POL", "NLD", "BEL", "AUT"),
    value = c(120, 340, 260, 180, 90, 410, 150, 220),
    grp = rep(c("a", "b"), 4), stringsAsFactors = FALSE)
  g <- attach_geometry(d, geometry = "polygon")

  # Both forms must build, and must build the *same* plot.
  same <- function(bare, str) {
    a <- ggplot2::ggplot_build(bare)
    b <- ggplot2::ggplot_build(str)
    expect_equal(a$data, b$data)
    expect_equal(a$plot$labels, b$plot$labels)
  }
  same(world_map(g, value), world_map(g, "value"))
  same(world_map(g, value, style = "binned"), world_map(g, "value", style = "binned"))
  same(world_map(g, value, style = "quantile"), world_map(g, "value", style = "quantile"))
  same(world_map(g, grp, style = "categorical"),
       world_map(g, "grp", style = "categorical"))
  same(coverage_map(g, value), coverage_map(g, "value"))
  same(tile_map(d, value), tile_map(d, "value"))
  same(bubble_map(d, value), bubble_map(d, "value"))
  same(bubble_map(d, value, color = grp), bubble_map(d, "value", color = "grp"))
  same(spike_map(d, value), spike_map(d, "value"))
})

test_that("the string form keeps the legend title the unquoted form gives", {
  skip_if_not_installed("maps")
  skip_if_not_installed("ggplot2")
  d <- data.frame(iso3c = c("FRA", "DEU", "ITA"), gdp = c(1, 2, 3),
                  stringsAsFactors = FALSE)
  g <- attach_geometry(d, geometry = "polygon")
  # ggplot2 unwraps `.data[["gdp"]]` to `gdp`, so resolving the mapping from
  # the validated name must not leave `.data[["gdp"]]` in the legend.
  lab <- ggplot2::ggplot_build(world_map(g, "gdp"))$plot$labels$fill
  expect_false(grepl(".data", lab, fixed = TRUE))
  expect_identical(lab, ggplot2::ggplot_build(world_map(g, gdp))$plot$labels$fill)
})

# abort_bare_column() exists because a few arguments take a column name as a
# *string* while the verbs around them take a bare column through tidy eval, so
# writing the bare column that works everywhere else produced base R's "object
# 'v' not found". It was applied to the six value/indicator/columns/codes/by
# arguments in analysis.R, disputes.R, diagnostics.R, reporting.R and
# reference.R, and not to the join-key and query arguments that have exactly
# the same shape -- aggregate_regions(by = region) explained itself while
# attach_geometry(by = iso3c) did not.
test_that("string column arguments report a bare column instead of 'not found'", {
  d <- data.frame(iso3c = c("FRA", "DEU"), value = 1:2, stringsAsFactors = FALSE)
  expect_error(attach_geometry(d, by = iso3c), class = "countryatlas_bare_column")
  expect_error(subnational_map(d, value, by = nuts_id),
               class = "countryatlas_bare_column")
  expect_error(
    register_country_source("bare-col-probe", function(...) d, key_col = iso3c),
    class = "countryatlas_bare_column")
  expect_error(world_query("value", facet = year), class = "countryatlas_bare_column")
  expect_error(world_query("value", size = pop), class = "countryatlas_bare_column")
  expect_error(as_ggsql_source(d, geometry_col = geom),
               class = "countryatlas_bare_column")
  # The message must name the argument and show the quoted form to write.
  err <- rlang::catch_cnd(attach_geometry(d, by = iso3c))
  expect_match(conditionMessage(err), "by", fixed = TRUE)
  expect_match(conditionMessage(err), 'by = "iso3c"', fixed = TRUE)
})

test_that("guarding the bare form leaves the string form and defaults working", {
  skip_if_not_installed("maps")
  d <- data.frame(iso3c = c("FRA", "DEU"), value = 1:2, stringsAsFactors = FALSE)
  expect_no_error(attach_geometry(d, geometry = "polygon"))
  expect_no_error(attach_geometry(d, by = "iso3c", geometry = "polygon"))
  expect_no_error(world_query("value"))
  # layer = "bubble" so `size` actually applies: on the default choropleth it
  # now draws a notice that the layer does not use it, which is correct and
  # beside the point here -- what is being checked is the string form.
  expect_no_error(world_query("value", facet = "year", size = "pop",
                              layer = "bubble"))
  # A real error inside the argument must still surface as itself, not be
  # reclassified as a bare column.
  expect_error(attach_geometry(d, by = stop("boom")), "boom")
})

# read_year()'s warning had two defects at once, both user-facing.
test_that("the unparseable-year warning names its source and lists real values", {
  d <- data.frame(iso3c = c("FRA", "DEU"), year = c("junk", "N/A"),
                  value = 1:2, stringsAsFactors = FALSE)
  w <- rlang::catch_cnd(audit_time_coverage(d), classes = "countryatlas_bad_year")
  msg <- conditionMessage(w)
  # cli does not re-interpolate a substituted value, so `{source_label}` used
  # to print the label's own markup verbatim.
  expect_false(grepl("{.arg", msg, fixed = TRUE))
  expect_false(grepl("{.val", msg, fixed = TRUE))
  expect_match(msg, "data", fixed = TRUE)
  expect_match(msg, "junk", fixed = TRUE)

  # And the public extension point interpolates the source's name, whose
  # braces referenced a variable living only in the caller's frame.
  register_country_source("read-year-probe", function(indicator, countries, years, ...)
    data.frame(iso3c = c("FRA", "DEU", "ITA", "ESP", "POL"),
               year = rep("N/A", 5), value = 1:5, stringsAsFactors = FALSE))
  w2 <- rlang::catch_cnd(fetch_indicator("read-year-probe", "x"),
                         classes = "countryatlas_bad_year")
  m2 <- conditionMessage(w2)
  expect_match(m2, "read-year-probe", fixed = TRUE)
  expect_false(grepl("{.val", m2, fixed = TRUE))
  # Five bad rows but one distinct value: the list must not be padded with NAs.
  # sum(bad) sized the slice, so this read `"N/A", NA, NA, and NA`.
  expect_false(grepl("NA", sub('"N/A"', "", m2, fixed = TRUE), fixed = TRUE))
})

# Every verb that takes a column name reports a missing one as
# `Column "x" not found in `data``. correlate_indicators() selects through
# tidyselect, whose own error for a name that does not exist is a
# vctrs_error_subscript_oob -- "Can't select columns that don't exist" --
# so it was the last unclassed error left at this boundary.
test_that("correlate_indicators reports a missing column like its siblings", {
  d <- data.frame(iso3c = c("FRA", "DEU", "ITA", "ESP"), year = rep(2000, 4),
                  value = c(1, 2, 3, 4), pop = c(6e7, 8e7, 5e7, 4e7),
                  gdp = c(9, 8, 7, 6), txt = letters[1:4], stringsAsFactors = FALSE)
  expect_error(correlate_indicators(d, "value", "nope"),
               class = "countryatlas_error")
  err <- rlang::catch_cnd(correlate_indicators(d, "value", "nope"))
  expect_match(conditionMessage(err), "not found", fixed = TRUE)
  expect_match(conditionMessage(err), "nope", fixed = TRUE)
  # A column that exists but is not numeric keeps its own message.
  expect_error(correlate_indicators(d, "value", "txt"), "not numeric")

  # The selection is a tidyselect expression, so every form must still work.
  expect_no_error(correlate_indicators(d, "value", "pop"))
  expect_no_error(correlate_indicators(d, value, pop))
  expect_no_error(correlate_indicators(d, dplyr::starts_with("p"), "value"))
  expect_no_error(correlate_indicators(d, dplyr::where(is.numeric)))
  expect_no_error(correlate_indicators(d, value:gdp))
  expect_no_error(correlate_indicators(d))
})

test_that("locate_country reports a points object with no CRS", {
  skip_if_not_installed("sf")
  df <- data.frame(lon = c(2.35, 13.40), lat = c(48.85, 52.52))
  # st_as_sf(coords = ) without `crs` leaves the CRS missing, and the object
  # then reached st_transform() and came back with sf's "cannot transform sfc
  # object with missing crs" -- naming neither the argument nor the fix. The
  # non-sf case one line above had already been given a proper message.
  nocrs <- sf::st_as_sf(df, coords = c("lon", "lat"))
  expect_error(locate_country(points = nocrs), class = "countryatlas_error")
  err <- rlang::catch_cnd(locate_country(points = nocrs))
  expect_match(conditionMessage(err), "points", fixed = TRUE)
  expect_match(conditionMessage(err), "coordinate reference system", fixed = TRUE)
  # An sfc is accepted by the same branch, so it must be guarded too.
  expect_error(locate_country(points = sf::st_geometry(nocrs)),
               class = "countryatlas_error")

  # The remedy the message prescribes has to work, and every path that already
  # worked must keep working.
  expect_no_error(locate_country(points = sf::st_set_crs(nocrs, 4326)))
  with_crs <- sf::st_as_sf(df, coords = c("lon", "lat"), crs = 4326)
  expect_equal(locate_country(points = with_crs)$iso3c, c("FRA", "DEU"))
  expect_equal(locate_country(points = sf::st_transform(with_crs, 3857))$iso3c,
               c("FRA", "DEU"))
  expect_equal(locate_country(df$lon, df$lat)$iso3c, c("FRA", "DEU"))
})

test_that("convergence_club on a panel too short for the log-t test finds no clubs", {
  # log_t_stat()'s regression window is start:ti with start = max(2, 0.3*ti),
  # so a 2-period panel fits one point and the coefficient table has one row.
  # Both defensive returns there were unexercised; the result must be "no
  # clubs", not an error and not an invented club.
  mk <- function(ny) {
    iso <- c("FRA", "DEU", "ITA", "ESP", "POL")
    data.frame(iso3c = rep(iso, each = ny), year = rep(seq_len(ny) + 1999, 5),
               value = as.numeric(unlist(lapply(1:5, function(i) i * 10 + seq_len(ny)))),
               stringsAsFactors = FALSE)
  }
  for (ny in c(2, 3, 4)) {
    out <- suppressWarnings(convergence_club(mk(ny), "value"))
    expect_true(all(is.na(out$club)), info = paste0(ny, " periods"))
    expect_equal(nrow(out), 5L)
  }
  # And the test does run on a long enough panel.
  long <- suppressWarnings(convergence_club(mk(20), "value"))
  expect_true(any(!is.na(long$club)))
})

# adapter_reshape() turns a provider's response into the package's shape. Its
# entity and value columns are both checked for existence; the year column was
# not, and its absence corrupted the value column rather than being reported.
test_that("adapter_reshape reports a missing year column instead of mangling the value", {
  R <- countryatlas:::adapter_reshape
  raw <- data.frame(entity = c("France", "Germany"), yr = c(2000L, 2000L),
                    val = c(1.5, 2.5), stringsAsFactors = FALSE)
  # The value auto-detection excludes the year BY NAME, so with year_col absent
  # the setdiff removed nothing and num[1] picked the provider's real time
  # column: the "indicator" came back as 2000, 2000 and `year` as all NA.
  expect_error(R(raw, "v", "entity", "nope"), class = "countryatlas_error")
  err <- rlang::catch_cnd(R(raw, "v", "entity", "nope"))
  expect_match(conditionMessage(err), "year column", fixed = TRUE)

  # The correct call is unaffected, and the value is the value.
  out <- R(raw, "v", "entity", "yr")
  expect_equal(out$v, c(1.5, 2.5))
  expect_equal(out$year, c(2000L, 2000L))
  expect_equal(out$iso3c, c("FRA", "DEU"))

  # The sibling guards still behave.
  expect_error(R(raw[0, ], "v", "entity", "yr"), class = "countryatlas_error")
  expect_error(R(raw, "v", "nope", "yr"), class = "countryatlas_error")
  expect_error(R(raw, "v", "entity", "yr", value_col = "values"),
               class = "countryatlas_error")
  expect_error(R(data.frame(entity = "Xanadu", yr = 2000L, val = 1,
                            stringsAsFactors = FALSE), "v", "entity", "yr"),
               class = "countryatlas_no_entities")
  expect_warning(R(data.frame(entity = c("France", "France"), yr = c(2000L, 2000L),
                              val = c(1, 2), stringsAsFactors = FALSE),
                   "v", "entity", "yr"),
                 class = "countryatlas_provider_duplicates")
})

# check_cols()'s message named `data` unconditionally, which is right for the
# twenty-odd verbs whose frame argument is called that and wrong for the three
# whose is not.
test_that("a missing-column error names the argument the caller actually passed", {
  expect_error(country_weights("custom", w = data.frame(a = 1, b = 2)),
               "`w`", fixed = TRUE)
  err <- rlang::catch_cnd(country_weights("custom", w = data.frame(a = 1, b = 2)))
  expect_false(grepl("`data`", conditionMessage(err), fixed = TRUE))

  # Duplicated column names come through the same helper.
  dup <- stats::setNames(data.frame(a = 1, b = 2, c = 3),
                         c("iso3c", "neighbor", "iso3c"))
  err2 <- rlang::catch_cnd(country_weights("custom", w = dup))
  expect_match(conditionMessage(err2), "`w`", fixed = TRUE)
  expect_s3_class(err2, "countryatlas_duplicate_columns")

  skip_if_not_installed("sf")
  sq <- function(i) sf::st_polygon(list(cbind(c(i, i+1, i+1, i, i),
                                              c(0, 0, 1, 1, 0))))
  sfd <- sf::st_sf(iso3c = c("FRA", "DEU"), value = c(1, 2),
                   geometry = sf::st_sfc(sq(0), sq(2)), crs = 4326)
  err3 <- rlang::catch_cnd(cartogram_diagnostics(sfd, weight = "nope"))
  expect_match(conditionMessage(err3), "`x`", fixed = TRUE)
  expect_false(grepl("`data`", conditionMessage(err3), fixed = TRUE))

  # And the verbs whose argument really is `data` keep saying so.
  d <- data.frame(iso3c = c("FRA", "DEU"), year = c(2000, 2000),
                  value = c(1, 2), stringsAsFactors = FALSE)
  expect_match(conditionMessage(rlang::catch_cnd(growth_rate(d, "nope"))),
               "`data`", fixed = TRUE)
})

test_that("a custom weights matrix rejects every unusable entry by name", {
  nm <- list(c("FRA", "DEU"), c("FRA", "DEU"))
  mk <- function(v) matrix(v, 2, 2, dimnames = nm)
  expect_error(country_weights("custom", w = matrix(c(0, 1, 1, 0), 2, 2)),
               class = "countryatlas_error")                       # no dimnames
  expect_error(country_weights("custom",
    w = matrix(0, 2, 2, dimnames = list(c("FRA","DEU"), c("DEU","FRA")))),
    class = "countryatlas_error")                                  # names differ
  expect_error(country_weights("custom", w = mk(c("0","1","1","0"))), "numeric")
  expect_error(country_weights("custom", w = mk(c(0, NA, 1, 0))), "NA")
  expect_error(country_weights("custom", w = mk(c(0, -1, -1, 0))), "non-negative")
  expect_error(country_weights("custom", w = mk(c(0, Inf, Inf, 0))), "finite")
  expect_no_error(country_weights("custom", w = mk(c(0, 1, 1, 0))))

  lf <- data.frame(iso3c = c("FRA","DEU"), neighbor = c("DEU","FRA"),
                   stringsAsFactors = FALSE)
  expect_error(country_weights("custom", w = cbind(lf, weight = c("a","b"))),
               "numeric")
  expect_error(country_weights("custom", w = cbind(lf, weight = c(1, NA))), "NA")
  expect_error(country_weights("custom",
    w = data.frame(iso3c = c("FRA", NA), neighbor = c("DEU","FRA"),
                   stringsAsFactors = FALSE)), "NA")
  expect_no_error(country_weights("custom", w = lf))
  # A subset with fewer than two members cannot form a graph.
  m <- matrix(c(0,1,0, 1,0,1, 0,1,0), 3, 3,
              dimnames = list(c("FRA","DEU","ITA"), c("FRA","DEU","ITA")))
  expect_error(country_weights("custom", w = m, countries = "FRA"), "Fewer than 2")
  expect_no_error(country_weights("custom", w = m, countries = c("FRA","DEU")))
})

# The package reports an argument that does not apply -- warn_projection_ignored(),
# warn_recenter_ignored(), warn_scale_ignored(), warn_engine_ignored(). The first
# two were applied to the verbs that *produce* polygon geometry and not to the
# ones that draw it, and `n_bins` was inert without a word under the styles that
# do not bin.
test_that("world_map reports arguments that do not apply", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("maps")
  d <- data.frame(iso3c = c("FRA","DEU","ITA","ESP","POL","NLD","BEL","AUT"),
                  value = c(10,20,40,80,15,55,33,66), grp = rep(c("a","b"), 4),
                  stringsAsFactors = FALSE)
  g <- attach_geometry(d, geometry = "polygon")

  # The polygon backend draws in unprojected long/lat, so both of these looked
  # honoured and changed nothing.
  expect_warning(world_map(g, value, projection = "mercator"),
                 class = "countryatlas_projection_ignored")
  expect_warning(world_map(g, value, recenter = 180),
                 class = "countryatlas_recenter_ignored")
  # n_bins means nothing to a colourbar or to categories.
  expect_warning(world_map(g, value, n_bins = 9),
                 class = "countryatlas_n_bins_ignored")
  expect_warning(world_map(g, grp, style = "categorical", n_bins = 9),
                 class = "countryatlas_n_bins_ignored")

  # None of it fires where the argument does apply, or at its default.
  expect_silent(suppressMessages(world_map(g, value)))
  expect_silent(suppressMessages(world_map(g, value, projection = "equal_earth")))
  expect_silent(suppressMessages(world_map(g, value, style = "binned", n_bins = 9)))
  expect_silent(suppressMessages(world_map(g, value, style = "quantile", n_bins = 3)))

  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  sf1 <- attach_geometry(d, geometry = "sf")
  expect_silent(suppressMessages(world_map(sf1, value, projection = "mercator")))
  expect_silent(suppressMessages(world_map(sf1, value, recenter = 180)))
})

test_that("value_by_alpha_map reports the same inert arguments", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("maps")
  d <- data.frame(iso3c = c("FRA","DEU","ITA","ESP"), value = c(10,20,40,80),
                  unc = c(1,2,3,4), stringsAsFactors = FALSE)
  g <- attach_geometry(d, geometry = "polygon")
  # It carries its own `projection` and `n_bins` rather than passing them to
  # world_map(), so it needed its own notices.
  expect_warning(value_by_alpha_map(g, value, unc, projection = "mercator"),
                 class = "countryatlas_projection_ignored")
  expect_warning(value_by_alpha_map(g, value, unc, style = "continuous", n_bins = 9),
                 class = "countryatlas_n_bins_ignored")
  expect_silent(suppressMessages(value_by_alpha_map(g, value, unc)))
  expect_silent(suppressMessages(
    value_by_alpha_map(g, value, unc, style = "quantile", n_bins = 3)))

  # n_bins really does bin here -- one class per bin plus the NA class -- which
  # is what makes ignoring it under "continuous" the right thing to report.
  nfill <- function(nb) length(unique(ggplot2::ggplot_build(suppressMessages(
    value_by_alpha_map(g, value, unc, style = "quantile", n_bins = nb)))$data[[2]]$fill))
  expect_true(nfill(3) < nfill(4))
})

# country_weights()'s `k`, `cutoff_km`, `w` and `scale` each belong to exactly
# one scheme. The other three ignored them silently -- and
# country_weights("knn", w = my_matrix) discarding the caller's own adjacency is
# the worst of them, because nearest-neighbour weights come back looking
# entirely reasonable.
test_that("country_weights reports arguments its scheme does not use", {
  iso <- c("FRA","DEU","ITA","ESP","POL","NLD","BEL","AUT")
  m <- matrix(0, 8, 8, dimnames = list(iso, iso))
  m[1, 2] <- m[2, 1] <- 1
  cls <- "countryatlas_weights_args_ignored"

  # Only schemes that need no geometry here: "contiguity" calls need_pkg("sf"),
  # and expect_warning() evaluates the whole call, so under
  # _R_CHECK_DEPENDS_ONLY_ the notice fires and the missing-sf error then
  # propagates out of it. The contiguity cases live in their own test below.
  expect_warning(country_weights("knn", iso, k = 2, w = m), class = cls)
  expect_warning(country_weights("knn", iso, k = 2, cutoff_km = 500), class = cls)
  expect_warning(country_weights("distance", iso, cutoff_km = 2000, k = 3), class = cls)
  expect_warning(country_weights("custom", iso, w = m, scale = "medium"), class = cls)
  expect_warning(country_weights("knn", iso, k = 2, scale = "medium"), class = cls)
  expect_warning(country_weights("custom", iso, w = m, k = 3), class = cls)
  expect_warning(country_weights("custom", iso, w = m, cutoff_km = 500), class = cls)

  # The message names both what was ignored and what the scheme does use.
  err <- rlang::catch_cnd(country_weights("knn", iso, k = 2, w = m), classes = cls)
  expect_match(conditionMessage(err), "w", fixed = TRUE)
  expect_match(conditionMessage(err), "k", fixed = TRUE)

  # Each scheme's own argument, the shared `style`, and an explicitly passed
  # default all stay quiet.
  expect_silent(suppressMessages(country_weights("knn", iso, k = 2)))
  expect_silent(suppressMessages(country_weights("distance", iso, cutoff_km = 2000)))
  expect_silent(suppressMessages(country_weights("custom", iso, w = m)))
  expect_silent(suppressMessages(country_weights("knn", iso, k = 2, style = "B")))
})

test_that("country_weights reports inert arguments for the contiguity scheme too", {
  # Separated because contiguity is built from geometry: need_pkg("sf") errors
  # without it, and that error would escape the expect_warning() below.
  skip_if_not_installed("sf")
  iso <- c("FRA","DEU","ITA","ESP","POL","NLD","BEL","AUT")
  m <- matrix(0, 8, 8, dimnames = list(iso, iso))
  m[1, 2] <- m[2, 1] <- 1
  cls <- "countryatlas_weights_args_ignored"
  expect_warning(country_weights("contiguity", iso, w = m), class = cls)
  expect_warning(country_weights("contiguity", iso, k = 3), class = cls)
  expect_warning(country_weights("contiguity", iso, cutoff_km = 500), class = cls)
  # `scale` is the one this scheme uses, and an explicit default stays quiet.
  expect_silent(suppressMessages(country_weights("contiguity", iso, scale = "medium")))
  expect_silent(suppressMessages(country_weights("contiguity", iso, k = 5)))
})

test_that("an orthographic globe draws from every viewpoint", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("ggplot2")
  # coord_sf()'s graticule is clipped at the horizon on the one genuinely
  # hemispheric projection, and a clipped line can reduce to a single point,
  # which GEOS rejects: lon = 90, lat = 30 died on "IllegalArgumentException:
  # point array must contain 0 or >1 elements" -- a foreign error naming
  # neither the projection nor the viewpoint. winkel_tripel already had
  # datum = NA for its own graticule trouble; orthographic did not.
  g <- world_geometry("countries", geometry = "sf")
  for (pt in list(c(90, 30), c(0, 20), c(45, 45), c(-90, 30), c(150, -30))) {
    # expect_no_error() takes no `info`, so name the viewpoint in the label.
    ok <- tryCatch({
      ggplot2::ggplot_build(
        ggplot2::ggplot(g) + ggplot2::geom_sf() +
          countryatlas:::wdj_coord_sf("orthographic", recenter = pt[1], lat0 = pt[2]))
      TRUE
    }, error = function(e) conditionMessage(e))
    expect_true(isTRUE(ok), label = paste0("orthographic at (", pt[1], ", ", pt[2], "): ",
                                           if (isTRUE(ok)) "" else ok))
  }
  d <- data.frame(iso3c = c("FRA", "DEU", "ITA"), value = 1:3,
                  stringsAsFactors = FALSE)
  sf1 <- attach_geometry(d, geometry = "sf")
  expect_no_error(ggplot2::ggplot_build(suppressMessages(
    globe_map(sf1, value, lon = 90, lat = 30))))
})

test_that("globe_map reports n_bins under a style that does not bin", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  d <- data.frame(iso3c = c("FRA","DEU","ITA","ESP"), value = c(1,2,3,4),
                  grp = c("a","b","a","b"), stringsAsFactors = FALSE)
  sf1 <- attach_geometry(d, geometry = "sf")
  expect_warning(globe_map(sf1, value, n_bins = 9),
                 class = "countryatlas_n_bins_ignored")
  expect_warning(globe_map(sf1, grp, style = "categorical", n_bins = 9),
                 class = "countryatlas_n_bins_ignored")
  expect_silent(suppressMessages(globe_map(sf1, value)))
  expect_silent(suppressMessages(globe_map(sf1, value, style = "quantile", n_bins = 3)))
})

# world_query()'s `size` belongs to layer = "bubble" and `n_bins` to
# layer = "binned". The other layers took them without a word: n_bins was
# dropped (only the binned layer emits a BIN clause) and size still went into
# the VISUALISE list as `pop AS size` on a choropleth, which has no size
# channel. The abort beside it already treats a layer/argument mismatch as
# worth naming.
test_that("world_query reports arguments its layer does not use", {
  cls <- "countryatlas_layer_args_ignored"
  expect_warning(world_query("value", size = "pop"), class = cls)
  expect_warning(world_query("value", n_bins = 4), class = cls)
  expect_warning(world_query("value", layer = "bubble", size = "pop", n_bins = 4),
                 class = cls)
  expect_warning(world_query("value", layer = "binned", n_bins = 4, size = "pop"),
                 class = cls)
  # Both at once are named together, not one warning each.
  w <- rlang::catch_cnd(world_query("value", size = "pop", n_bins = 4), classes = cls)
  expect_match(conditionMessage(w), "size", fixed = TRUE)
  expect_match(conditionMessage(w), "n_bins", fixed = TRUE)

  # Each layer's own argument, and the arguments common to all, stay quiet.
  expect_silent(world_query("value"))
  expect_silent(world_query("value", layer = "bubble", size = "pop"))
  expect_silent(world_query("value", layer = "binned", n_bins = 4))
  expect_silent(world_query("value", layer = "binned"))
  expect_silent(world_query("value", facet = "year", transform = "log10"))

  # "choropleth" is in neither branch of the lookup, so it must not error --
  # `[[` on a named vector throws for a name that is absent.
  expect_no_error(world_query("value", layer = "choropleth"))
})

# --- the four audits NEWS.md claimed complete --------------------------------
# In every case the miss was a path that bypassed the shared helper the audit
# reasoned about: compute_breaks() for n_bins, wdj_to_iso3c() for keys,
# ascii_lower() for folding, wdj_return_frame() for the return class.

test_that("n_bins is bounded on the tmap hand-off too", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("tmap")
  sf1 <- attach_geometry(data.frame(iso3c = "FRA", value = 1,
                                    stringsAsFactors = FALSE), geometry = "sf")
  # The branch returned before any check and handed n_bins to
  # tm_scale_intervals(), which coerces with as.integer(): 1e18 became NA.
  expect_error(suppressMessages(world_map(sf1, value, engine = "tmap", n_bins = 1e18)),
               class = "countryatlas_error")
  expect_error(suppressMessages(world_map(sf1, value, engine = "tmap", n_bins = "5")),
               class = "countryatlas_error")
})

test_that("n_bins is bounded on the uncertainty path too", {
  skip_if_not_installed("maps")
  g <- attach_geometry(data.frame(iso3c = c("FRA", "DEU"), value = c(1, 2),
                                  se = c(1, 2), stringsAsFactors = FALSE),
                       geometry = "polygon")
  # This path did as.integer(n_bins) and then seq_len() on it -- verbatim the
  # seq_len(NA) failure the changelog documents for od_map(origins = ).
  expect_error(suppressMessages(world_map(g, value, uncertainty = se, n_bins = 1e18)),
               class = "countryatlas_error")
  expect_error(suppressMessages(world_map(g, value, uncertainty = se, n_bins = "5")),
               class = "countryatlas_error")
})

test_that("the code-vector entry points standardise their keys", {
  # Both took the key verbatim, so a lowercase code matched nothing and the
  # verb blamed its own data: check_dispute_coverage() reported zero tracked
  # territories, and country_weights() blamed the centroid table.
  lower <- check_dispute_coverage(c("esh", "xkx", "pse"))
  upper <- check_dispute_coverage(c("ESH", "XKX", "PSE"))
  expect_equal(sum(lower$in_data), sum(upper$in_data))
  expect_gt(sum(lower$in_data), 0L)
  expect_equal(sum(check_dispute_coverage(" esh ")$in_data), 1L)
  # Nothing matching is now reported rather than read as a coverage finding.
  expect_warning(check_dispute_coverage(c("ZZZ", "YYY")))

  expect_no_error(w <- suppressMessages(
    country_weights("knn", c("usa", "fra", "deu"), k = 2)))
  expect_equal(nrow(as.matrix(w)), 3L)
  # A key that resolves to nothing says so, and names the fix.
  err <- rlang::catch_cnd(country_weights("knn", c("zz", "qq"), k = 1))
  expect_match(conditionMessage(err), "standardize_country", fixed = TRUE)
})

test_that("identifier folding is ASCII everywhere, including scheme names", {
  # tolower("ISO3C") returns a dotless i under tr_TR while the candidate list
  # stays ASCII, so the "Did you mean" suggestion silently vanished.
  #
  # Reads R/ directly, which only exists in the source tree -- under R CMD check
  # the package is installed and there is no R/*.R to read. The behavioural
  # half of this test runs either way; only the grep needs the guard.
  err <- rlang::catch_cnd(convert_country("France", to = "ISO3C"))
  expect_match(conditionMessage(err), "iso3c", fixed = TRUE)
  skip_if_no_source_tree()
  src <- readLines(test_path("../../R/standardize.R"), warn = FALSE)
  code <- sub("#.*$", "", src)          # strip comments before looking
  expect_length(grep("[^_a-zA-Z.]tolower\\(", code), 0)
})

test_that("standardize_subnational normalises its return class", {
  # A data.frame in gave a data.frame out and a grouped tibble stayed grouped,
  # while standardize_country() next door normalises.
  out <- suppressMessages(standardize_subnational(
    data.frame(region = "DE-BY", stringsAsFactors = FALSE), region,
    country = "Germany"))
  expect_s3_class(out, "tbl_df")
  grp <- suppressMessages(standardize_subnational(
    dplyr::group_by(tibble::tibble(region = "DE-BY", k = 1), k), region,
    country = "Germany"))
  expect_false(inherits(grp, "grouped_df"))
})

test_that("compare_sources takes the numeric column, whatever else a source returns", {
  # Reading `as.matrix(out[, sources])` followed by `abs()` suggests a
  # character column could reach abs() and fail with base R's "non-numeric
  # argument to mathematical function". It cannot: the per-source reshape picks
  # the first numeric column and aborts when there is none. Pinned so that
  # stays true if either half moves.
  withr::defer(suppressWarnings(
    remove_country_source(c("t_mixed", "t_numeric", "t_nonnum"))))
  register_country_source("t_mixed", function(indicator, countries = NULL,
                                              years = NULL, ...) {
    tibble::tibble(iso3c = c("FRA", "DEU"), year = 2020L,
                   gdp = c("1000", "2000"), other = c(1, 2))
  })
  register_country_source("t_numeric", function(indicator, countries = NULL,
                                                years = NULL, ...) {
    tibble::tibble(iso3c = c("FRA", "DEU"), year = 2020L, gdp = c(1000, 2000))
  })
  out <- compare_sources("gdp", sources = c("t_mixed", "t_numeric"),
                         year = 2020)
  expect_type(out$t_mixed, "double")
  expect_type(out$t_numeric, "double")
  expect_equal(nrow(out), 2L)

  # And a source with no numeric column at all is named, not left to abs().
  register_country_source("t_nonnum", function(indicator, countries = NULL,
                                               years = NULL, ...) {
    tibble::tibble(iso3c = c("FRA", "DEU"), year = 2020L,
                   gdp = c("1000", "2000"))
  })
  expect_error(compare_sources("gdp", sources = c("t_nonnum", "t_numeric"),
                               year = 2020),
               "no numeric column")
})

test_that("od_map tells `origin` and `origins` apart", {
  # One letter apart, adjacent in the signature, and unrelated in meaning.
  # `origin = 3` used to fail inside check_string() talking about a coding
  # scheme; `origins = "iso3c"` used to fail inside country-name matching.
  skip_if_not_installed("maps")
  od <- data.frame(from = rep(c("China", "Germany", "USA"), each = 2),
                   to = c("USA", "Japan", "France", "Italy", "Mexico", "Canada"),
                   value = c(500, 200, 80, 70, 300, 280),
                   stringsAsFactors = FALSE)
  expect_error(od_map(od, from, to, value, origin = 3), "Did you mean")
  expect_error(od_map(od, from, to, value, origins = "iso3c"),
               "not how to read them")
  # Both used correctly still work.
  expect_s3_class(suppressWarnings(suppressMessages(
    od_map(od, from, to, value, origins = 2))), "ggplot")
  expect_s3_class(suppressWarnings(suppressMessages(
    od_map(od, from, to, value, origins = c("China", "USA")))), "ggplot")
})
