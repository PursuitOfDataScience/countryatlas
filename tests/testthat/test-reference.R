test_that("convert_country handles shortcuts", {
  expect_equal(convert_country(c("Japan", "Brazil"), to = "flag"),
               c("\U0001F1EF\U0001F1F5", "\U0001F1E7\U0001F1F7"))
  expect_equal(convert_country("Germany", to = "currency"), "EUR")
  expect_equal(convert_country(c("USA", "France"), to = "continent"),
               c("Americas", "Europe"))
})

test_that("country_codes returns a tidy tibble", {
  cc <- country_codes()
  expect_s3_class(cc, "tbl_df")
  expect_true(all(c("country", "iso3c", "iso2c") %in% names(cc)))
  expect_false(anyNA(cc$iso3c))

  cc2 <- country_codes(c("continent", "currency"))
  expect_true(all(c("continent", "currency") %in% names(cc2)))
})

test_that("country_groups and in_group work", {
  eu <- country_groups("EU")
  expect_equal(nrow(eu), 27)
  expect_true("FRA" %in% eu$iso3c)

  expect_equal(in_group(c("France", "United States", "Japan"), "EU"),
               c(TRUE, FALSE, FALSE))
  expect_error(country_groups("NOPE"), class = "countryatlas_error")
})

test_that("bundled datasets have expected shape", {
  expect_true(nrow(common_indicators) >= 15)
  expect_true(all(c("name", "code", "description") %in% names(common_indicators)))
  expect_true(nrow(country_meta) > 200)
  expect_true(all(c("iso3c", "flag", "landlocked") %in% names(country_meta)))
  expect_true(nrow(world_tiles) > 150)
  expect_true(all(c("iso3c", "row", "col") %in% names(world_tiles)))
  expect_type(world_snapshot, "list")
  expect_true(nrow(world_snapshot$countries) > 150)
})

test_that("country_overrides returns the same overrides as wdj_overrides", {
  expect_equal(country_overrides(), wdj_overrides())
  expect_equal(
    country_overrides(c(Somaliland = "SOM")),
    wdj_overrides(c(Somaliland = "SOM"))
  )
})

test_that("country_overrides merges extra overrides on top of built-ins", {
  base <- wdj_overrides()
  ext <- country_overrides(c(Somaliland = "SOM"))
  expect_equal(ext[["Somaliland"]], "SOM")
  expect_equal(ext[["Kosovo"]], "XKX")  # built-in still present
  expect_equal(ext[["Canary Islands"]], "ESP")
})

test_that("country_overrides errors on unnamed extra", {
  expect_error(country_overrides(c("SOM")), class = "countryatlas_error")
})

test_that("repair_country_names corrects obvious typos", {
  inp <- c("United States", "Brzil", "Germny")
  out <- repair_country_names(inp, verbose = FALSE)
  expect_equal(out[1], "United States")           # already correct
  expect_false(identical(out[2], "Brzil"))         # was repaired
  expect_false(identical(out[3], "Germny"))        # was repaired
})

test_that("repair_country_names respects threshold (low threshold = no repairs)", {
  inp <- c("Brzil", "Germny")
  out <- repair_country_names(inp, threshold = 0, verbose = FALSE)
  # No repairs at threshold 0, but the repairs attribute is always attached
  expect_equal(as.character(out), inp)
  expect_equal(nrow(attr(out, "repairs")), 0)
})

test_that("repair_country_names attaches repairs attribute", {
  inp <- c("Brzil", "United States")
  out <- repair_country_names(inp, verbose = FALSE)
  repairs <- attr(out, "repairs")
  expect_s3_class(repairs, "tbl_df")
  expect_true("from" %in% names(repairs))
  expect_true("to" %in% names(repairs))
})

test_that("repair_country_names leaves matched names unchanged", {
  inp <- c("United States", "France", "Japan")
  out <- repair_country_names(inp, verbose = FALSE)
  expect_equal(as.character(out), inp)
  expect_equal(nrow(attr(out, "repairs")), 0)
})

test_that("convert_country resolves override-only entities for non-iso3c destinations", {
  # Bug 3.7: override-only names (Canary Islands, Azores) should resolve for
  # continent, region, flag etc -- not just iso3c.
  expect_equal(convert_country("Canary Islands", to = "continent"), "Europe")
  expect_equal(convert_country("Azores", to = "continent"), "Europe")
  expect_equal(convert_country("Canary Islands", to = "region"),
               "Europe & Central Asia")
})

test_that("convert_country Kosovo (XKX) fallback works for continent/iso2c", {
  # XKX has no row in countrycode::codelist; the iso3c round-trip leaves
  # continent/iso2c NA, so the fallback table must fill them.
  expect_equal(convert_country("Kosovo", to = "continent"), "Europe")
  expect_equal(convert_country("Kosovo", to = "iso2c"), "XK")
})

test_that("conversion and repair are stable when applied twice", {
  messy <- c("Czech Republic", "Korea, Rep.", "Brzil", "Ivory Coast", "Burma",
             "Swaziland", "Macedonia", "Kosovo", "United States", "Xyzzy")
  # The canonical name is a fixed point: naming an already-named vector must not
  # drift.
  nm <- suppressWarnings(convert_country(messy, to = "country",
                                        from = "country.name"))
  expect_equal(suppressWarnings(convert_country(nm, to = "country",
                                               from = "country.name")), nm)
  # repair_country_names() is idempotent in its *values*. The documented
  # "repairs" attribute is expected to differ -- the second pass has nothing
  # left to repair -- so compare the vectors, not the objects.
  r1 <- suppressWarnings(repair_country_names(messy, verbose = FALSE))
  r2 <- suppressWarnings(repair_country_names(r1, verbose = FALSE))
  expect_equal(as.character(r1), as.character(r2))
  expect_equal(nrow(attr(r1, "repairs")), 1L)      # "Brzil" -> "Brazil"
  expect_equal(nrow(attr(r2, "repairs")), 0L)      # nothing left to do
  # Standardising an already-standardised frame leaves the key alone.
  d1 <- suppressWarnings(standardize_country(data.frame(c = messy), c,
                                            warn = FALSE))
  d2 <- suppressWarnings(standardize_country(d1, iso3c, origin = "iso3c",
                                            warn = FALSE))
  expect_equal(d1$iso3c, d2$iso3c)
})

test_that("localized names are an output scheme only", {
  # `to = "name_<lang>"` is documented; using one as `from` is not, and
  # countrycode rejects it with a message listing the origins it accepts.
  expect_equal(convert_country("DEU", to = "name_fr", from = "iso3c"),
               "Allemagne")
  expect_error(convert_country("Allemagne", to = "iso3c", from = "name_fr"),
               "origin")
  # An unknown origin fails the same clear way.
  expect_error(convert_country("Germany", to = "iso3c", from = "bogus"),
               "origin")
  # A French name is simply unmatched by the English name matcher, with a
  # warning that points at the diagnostic.
  expect_warning(res <- convert_country("Allemagne", to = "iso3c",
                                        from = "country.name"),
                 "could not be matched")
  expect_true(is.na(res))
})

test_that("the soft-deprecation note belongs to the deprecated name alone", {
  # The notice used to live in the shared function body, so in an interactive
  # session it fired for country_overrides() -- the replacement it recommends --
  # and for every public function taking the override table as a default
  # argument, telling callers to stop using a function they never wrote.
  #
  # Checked structurally rather than by mocking base::interactive(): that mock
  # does not reliably take effect under R CMD check, and cli's `.frequency =
  # "once"` makes a behavioural test order-dependent within a session.
  # 3.0.0 escalated this from an interactive-only note to a real warning: an
  # interactive `cli_inform` never reaches the scripts still calling it, and the
  # cycle has now run a full release. The structural check is the same -- the
  # notice belongs to this name and to nothing else.
  has_note <- function(f) {
    src <- paste(deparse(f), collapse = " ")
    grepl("is deprecated", src, fixed = TRUE)
  }
  expect_true(has_note(countryatlas::wdj_overrides))
  expect_false(has_note(countryatlas::country_overrides))
  expect_false(has_note(countryatlas:::build_overrides))

  # And nothing else reaches the notice: every default argument and internal
  # caller must use the quiet builder.
  ns <- asNamespace("countryatlas")
  fns <- Filter(is.function, mget(setdiff(ls(ns, all.names = TRUE),
                                          "wdj_overrides"),
                                  envir = ns, ifnotfound = list(NULL)))
  src <- vapply(fns, function(f) paste(deparse(f), collapse = " "), character(1))
  callers <- names(src)[grepl("wdj_overrides(", src, fixed = TRUE)]
  expect_equal(callers, character(0))
})

test_that("splitting the note off left the override table identical", {
  # The deprecation note used to live in the shared body, so it fired for
  # country_overrides() -- the replacement it recommends -- and for every
  # public function taking `overrides = country_overrides()` as a default.
  # That is the regression worth pinning, and it was untested: the old
  # assertions here compared country_overrides() to build_overrides(), which
  # is the same function, and so could not fail.
  b <- expect_silent(country_overrides())
  # wdj_overrides()'s note is .frequency = "once", so whether it fires here
  # depends on test order; assert the table, not the note.
  expect_identical(suppressWarnings(wdj_overrides()), b)
  expect_gt(length(b), 0L)
  # The note must not reach a caller that merely defaults to the replacement.
  skip_if_not_installed("maps")
  expect_silent(countryatlas:::get_world_polygons(region = "Europe"))
  # extra= still merges, and the named-vector check still fires.
  expect_equal(unname(country_overrides(c(Freedonia = "FRE"))[["Freedonia"]]),
               "FRE")
  expect_error(country_overrides(c("FRE")), "fully named")
  # A curated override still resolves through the public API. Take the entry
  # from the table rather than naming one: "Somaliland" appears only in
  # ?wdj_overrides's example of adding your own, not in the built-in set.
  key <- names(b)[1]
  expect_equal(
    suppressWarnings(standardize_country(data.frame(c = key), c,
                                         warn = FALSE))$iso3c,
    unname(b[[key]]))
})
