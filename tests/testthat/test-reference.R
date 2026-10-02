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

test_that("country_overrides merges extra overrides on top of built-ins", {
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
  out <- repair_country_names(inp, quiet = TRUE)
  expect_equal(out[1], "United States")           # already correct
  expect_false(identical(out[2], "Brzil"))         # was repaired
  expect_false(identical(out[3], "Germny"))        # was repaired
})

test_that("repair_country_names respects threshold (low threshold = no repairs)", {
  inp <- c("Brzil", "Germny")
  out <- repair_country_names(inp, threshold = 0, quiet = TRUE)
  # No repairs at threshold 0, but the repairs attribute is always attached
  expect_equal(as.character(out), inp)
  expect_equal(nrow(attr(out, "repairs")), 0)
})

test_that("repair_country_names attaches repairs attribute", {
  inp <- c("Brzil", "United States")
  out <- repair_country_names(inp, quiet = TRUE)
  repairs <- attr(out, "repairs")
  expect_s3_class(repairs, "tbl_df")
  expect_true("from" %in% names(repairs))
  expect_true("to" %in% names(repairs))
})

test_that("repair_country_names leaves matched names unchanged", {
  inp <- c("United States", "France", "Japan")
  out <- repair_country_names(inp, quiet = TRUE)
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
  skip_slow_on_cran()
  messy <- c("Czech Republic", "Korea, Rep.", "Brzil", "Ivory Coast", "Burma",
             "Swaziland", "Macedonia", "Kosovo", "United States", "Xyzzy")
  # The canonical name is a fixed point: naming an already-named vector must not
  # drift.
  nm <- suppressWarnings(convert_country(messy, to = "country",
                                        origin = "country.name"))
  expect_equal(suppressWarnings(convert_country(nm, to = "country",
                                               origin = "country.name")), nm)
  # repair_country_names() is idempotent in its *values*. The documented
  # "repairs" attribute is expected to differ -- the second pass has nothing
  # left to repair -- so compare the vectors, not the objects.
  r1 <- suppressWarnings(repair_country_names(messy, quiet = TRUE))
  r2 <- suppressWarnings(repair_country_names(r1, quiet = TRUE))
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
  expect_equal(convert_country("DEU", to = "name_fr", origin = "iso3c"),
               "Allemagne")
  expect_error(convert_country("Allemagne", to = "iso3c", origin = "name_fr"),
               "origin")
  # An unknown origin fails the same clear way.
  expect_error(convert_country("Germany", to = "iso3c", origin = "bogus"),
               "origin")
  # A French name is matched by the French regex tier since 4.0.0 (3.0.0
  # left it unmatched), with nothing to warn about.
  expect_no_warning(res <- convert_country("Allemagne", to = "iso3c",
                                           origin = "country.name"))
  expect_identical(res, "DEU")
})


test_that("splitting the note off left the override table identical", {
  # The deprecation note used to live in the shared body, so it fired for
  # country_overrides() -- the replacement it recommends -- and for every
  # public function taking `overrides = country_overrides()` as a default.
  # That is the regression worth pinning, and it was untested: the old
  # assertions here compared country_overrides() to build_overrides(), which
  # is the same function, and so could not fail.
  b <- expect_silent(country_overrides())
  expect_identical(b, countryatlas:::build_overrides())
  expect_gt(length(b), 0L)
  # The note must not reach a caller that merely defaults to the replacement.
  expect_silent(countryatlas:::get_world_polygons(region = "Europe"))
  # extra= still merges, and the named-vector check still fires.
  expect_equal(unname(country_overrides(c(Freedonia = "FRE"))[["Freedonia"]]),
               "FRE")
  expect_error(country_overrides(c("FRE")), "fully named")
  # A curated override still resolves through the public API. Take the entry
  # from the table rather than naming one: "Somaliland" appears only in
  # ?country_overrides's example of adding your own, not in the built-in set.
  key <- names(b)[1]
  expect_equal(
    suppressWarnings(standardize_country(data.frame(c = key), c,
                                         warn = FALSE))$iso3c,
    unname(b[[key]]))
})

test_that("convert_country routes overrides through iso3c for all destinations", {
  skip_slow_on_cran()
  expect_equal(convert_country("Canary Islands", to = "iso3c"), "ESP")
  expect_equal(convert_country("Canary Islands", to = "continent"), "Europe")
  expect_equal(convert_country(c("Japan", "Brazil"), to = "flag"),
               c("\U0001F1EF\U0001F1F5", "\U0001F1E7\U0001F1F7"))
  # Kosovo's XKX has NO row at all in countrycode::codelist, so routing every
  # destination through the iso3c round-trip is NA for everything, even ones
  # (flag/region/country) that 1.0.0 already got right via direct name
  # matching -- recover those from the original name rather than regress
  # them. iso2c/continent never resolved even via direct name matching;
  # those come from the same curated fallback standardize_country() uses.
  expect_equal(convert_country("Kosovo", to = "continent"), "Europe")
  expect_equal(convert_country("Kosovo", to = "region"), "Europe & Central Asia")
  expect_equal(convert_country("Kosovo", to = "iso2c"), "XK")
  expect_equal(convert_country("Kosovo", to = "flag"), "\U0001F1FD\U0001F1F0")
  expect_equal(convert_country("Kosovo", to = "country"), "Kosovo")
  # Genuinely missing data (countrycode has no currency for Kosovo) stays NA,
  # not silently invented -- both before and after this fix.
  expect_true(is.na(convert_country("Kosovo", to = "currency")))
  # from = "iso3c" has no name to recover from, so everything it resolves for
  # XKX comes from the curated fallback table -- which covers name and flag
  # too, so country_borders() / locate_country(add = "country") don't hand
  # back NA for Kosovo.
  expect_equal(convert_country("XKX", to = "continent", origin = "iso3c"), "Europe")
  expect_equal(convert_country("XKX", to = "region", origin = "iso3c"),
               "Europe & Central Asia")
  expect_equal(convert_country("XKX", to = "iso2c", origin = "iso3c"), "XK")
  expect_equal(convert_country("XKX", to = "country", origin = "iso3c"), "Kosovo")
  expect_equal(convert_country("XKX", to = "flag", origin = "iso3c"),
               "\U0001F1FD\U0001F1F0")
  # Genuinely missing data still stays NA rather than being invented.
  expect_true(is.na(convert_country("XKX", to = "currency", origin = "iso3c",
                                    warn = FALSE)))
})

test_that("convert_country(warn = TRUE) actually warns about misses", {
  skip_slow_on_cran()
  # It used to be a no-op: every internal countrycode() call is wrapped in
  # suppressWarnings(), so `warn` never reached the user.
  expect_warning(convert_country("Wakanda", to = "continent"),
                 "could not be matched")
  expect_warning(convert_country("Wakanda"), "could not be matched")
  expect_warning(convert_country("ZZ", to = "country", origin = "iso2c"),
                 "could not be matched")
  expect_silent(convert_country("Wakanda", to = "continent", warn = FALSE))
  expect_silent(convert_country(c("France", "Japan"), to = "continent"))
  # NA in, NA out is not a matching failure.
  expect_silent(convert_country(c(NA, "France"), to = "continent"))
  # Neither is a recognised country with no value for that destination:
  # countrycode simply has no currency for Kosovo.
  expect_silent(convert_country("Kosovo", to = "currency"))
})

test_that("new country groups are present and correctly sized", {
  expect_equal(nrow(country_groups("GCC")), 6)
  expect_equal(nrow(country_groups("Nordic")), 5)
  expect_equal(nrow(country_groups("Visegrad")), 4)
  expect_true("BRA" %in% country_groups("Mercosur")$iso3c)
  # Existing groups unchanged.
  expect_equal(nrow(country_groups("EU")), 27)
})

# --- multilingual names ---------------------------------------------------------

test_that("convert_country(to = 'name_<lang>') returns localized names", {
  expect_equal(convert_country("Germany", to = "name_fr"), "Allemagne")
  expect_equal(convert_country("Germany", to = "name_es"), "Alemania")
  expect_equal(convert_country(c("Japan", "Brazil"), to = "name_de"),
               c("Japan", "Brasilien"))
  # Override-only entities work too (resolved via iso3c first).
  expect_equal(convert_country("Canary Islands", to = "name_fr"), "Espagne")
})

test_that("as_of gives point-in-time membership", {
  expect_equal(nrow(country_groups("EU", as_of = 2016)), 28L)
  expect_equal(nrow(country_groups("EU", as_of = 2021)), 27L)
  expect_equal(nrow(country_groups("EU", as_of = 1990)), 12L)
  expect_true(in_group("United Kingdom", "EU", as_of = 2016))
  expect_false(in_group("United Kingdom", "EU", as_of = 2021))
  # NATO grew; EFTA shrank.
  expect_equal(nrow(country_groups("NATO", as_of = 1950)), 12L)
  expect_gt(nrow(country_groups("EFTA", as_of = 1965)),
            nrow(country_groups("EFTA", as_of = Sys.Date())))
})

test_that("as_of accepts dates, years and strings, and rejects the rest", {
  skip_slow_on_cran()
  expect_equal(nrow(country_groups("EU", as_of = as.Date("2016-06-01"))), 28L)
  expect_equal(nrow(country_groups("EU", as_of = "2016-06-01")), 28L)
  for (bad in list("nope", 42, c(2000, 2001), NA, TRUE)) {
    expect_error(country_groups("EU", as_of = bad), "must be a")
  }
})

test_that("an undated group warns and falls back rather than inventing dates", {
  expect_warning(g <- country_groups("OPEC", as_of = 2000), "No dated membership")
  expect_equal(nrow(g), nrow(country_groups("OPEC")))
})

# --- the extended functions stayed backward compatible ------------------------------

test_that("positional calls that worked before still mean the same thing", {
  # Every function that gained an argument this release: the new ones were
  # appended, so an existing positional call must be unaffected.
  expect_equal(nrow(country_groups("EU")), 27L)
  expect_true(in_group("FRA", "EU", "iso3c"))
  a <- data.frame(country = c("Czechia", "South Korea"), gdp = 1:2)
  b <- data.frame(nation = c("Czech Republic", "Korea, Rep."), pop = c(10, 51))
  j <- country_join(a, b, country, nation, "country.name", "country.name",
                    "left", c(".x", ".y"))
  expect_equal(nrow(j), 2L)
  expect_true("iso3c" %in% names(j))
  q <- world_query(gdp, "src", "robinson", "magma", "log10", "T", "spatial")
  expect_match(q, "PROJECT TO robinson")
  expect_gt(nrow(world_geometry("countries", "polygon", "small", NULL,
                                "equal_earth", NULL)), 1000)
  expect_gt(nrow(attach_geometry(snap, "iso3c", "polygon", "small", NULL,
                                 "equal_earth", NULL)), 1000)
})

test_that("a bare `as_of` year means 1 January of that year", {
  skip_slow_on_cran()
  # The convention decides the answer at every mid-year accession, and reading
  # `as_of = 2013` as "during 2013" gives the opposite result. Pinned so it
  # cannot drift away from what the documentation now promises.
  expect_equal(countryatlas:::as_of_date(2013), as.Date("2013-01-01"))
  # Croatia joined on 2013-07-01.
  expect_false(in_group("Croatia", "EU", as_of = 2013))
  expect_false(in_group("Croatia", "EU", as_of = "2013-06-30"))
  expect_true(in_group("Croatia", "EU", as_of = "2013-07-01"))
  expect_true(in_group("Croatia", "EU", as_of = 2014))
  # The UK left at the end of 2020-01-31, so a bare 2020 still counts it in.
  expect_true(in_group("United Kingdom", "EU", as_of = 2020))
  expect_false(in_group("United Kingdom", "EU", as_of = "2020-06-01"))
  # The 2004 enlargement -- ten countries on 2004-05-01 -- is the largest
  # single accession and the one most likely to be entered as a bare year.
  for (cty in c("Poland", "Czechia", "Hungary", "Estonia")) {
    expect_false(in_group(cty, "EU", as_of = 2004), info = cty)
    expect_false(in_group(cty, "EU", as_of = "2004-04-30"), info = cty)
    expect_true(in_group(cty, "EU", as_of = "2004-05-01"), info = cty)
    expect_true(in_group(cty, "EU", as_of = 2005), info = cty)
  }
  # A 1 January accession is in on the day: Estonia adopted the euro
  # 2011-01-01, so a bare 2011 counts it in where a bare 2004 did not.
  expect_true(in_group("Estonia", "EuroZone", as_of = 2011))
  expect_false(in_group("Estonia", "EuroZone", as_of = 2010))
})

test_that("wdi_search and spin_globe validate the arguments they were missing", {
  skip_slow_on_cran()
  # wdi_search() checked `field` and nothing else. A non-string `pattern` went
  # straight into the regex and matched something: wdi_search(1) returned
  # 10,125 rows and wdi_search(NA) the entire catalogue, both silently.
  for (bad in list(1, NA, c("a", "b"), list(), character(0))) {
    expect_error(wdi_search(bad), "must be a single string")
  }
  expect_gt(nrow(wdi_search("energy")), 0L)
  # `cache` is a WDIcache() object; anything atomic reached WDI and died on
  # "$ operator is invalid for atomic vectors".
  expect_error(wdi_search("energy", cache = "yes"), "WDIcache")
  expect_error(wdi_search("energy", cache = TRUE), "WDIcache")
  expect_gt(nrow(wdi_search("energy", cache = NULL)), 0L)

  # spin_globe() validates every other argument before gating on the animation
  # packages -- its own comment says a bad argument is the caller's bug -- but
  # `file` slipped through to base R's "invalid 'path' argument".
  snap <- world_snapshot$countries
  for (bad in list(1, NA, c("a", "b"))) {
    expect_error(spin_globe(snap, gdp_per_capita, file = bad,
                            backend = "polygon", n_frames = 2),
                 "must be a single string")
  }
})

test_that("convert_country names its own from and to on a bad value", {
  skip_slow_on_cran()
  # Every scheme other than "country.name" and "iso3c" skips the iso3c hop, so
  # the origin reaches countrycode() directly -- the one call the guard inside
  # wdj_to_iso3c() could not cover -- and was blamed on countrycode's own
  # argument. `to` was not checked at all.
  err <- tryCatch(convert_country("FRA", origin = "country", to = "iso2c"),
                  error = identity)
  expect_s3_class(err, "countryatlas_bad_origin")
  expect_match(cli::ansi_strip(conditionMessage(err)), "`origin`", fixed = TRUE)
  # Through the deprecated `from`, the error names `from`.
  err <- withr::with_options(list(lifecycle_verbosity = "quiet"),
    tryCatch(convert_country("FRA", from = "country", to = "iso2c"),
             error = identity))
  expect_match(cli::ansi_strip(conditionMessage(err)), "`from`", fixed = TRUE)

  bad_to <- tryCatch(convert_country("France", to = "nonsense"),
                     error = identity)
  expect_s3_class(bad_to, "countryatlas_bad_destination")
  expect_match(cli::ansi_strip(conditionMessage(bad_to)), "`to`", fixed = TRUE)

  # The suggestion has to work for a destination too.
  msg <- function(e) gsub("[[:space:]]+", " ",
                          cli::ansi_strip(conditionMessage(tryCatch(e,
                            error = identity))))
  expect_match(msg(convert_country("France", to = "contnent")),
               "Did you mean [^?]*continent")
  expect_match(msg(convert_country("France", to = "iso")),
               "Did you mean [^?]*iso3c")

  # Every documented destination, including the package's own shortcuts and
  # the localised names, still resolves.
  for (d in c("iso3c", "iso2c", "iso3n", "country", "name", "continent",
              "region", "region23", "un_region", "flag", "currency", "tld",
              "calling_code", "cown", "name_fr")) {
    expect_false(is.na(suppressWarnings(convert_country("France", to = d))),
                 info = d)
  }
  # And so does every scheme that skips the iso3c hop.
  expect_identical(suppressWarnings(convert_country("FR", origin = "iso2c",
                                                    to = "iso3c")), "FRA")
  expect_identical(suppressWarnings(convert_country("FRA", origin = "wb",
                                                    to = "iso2c")), "FR")
})

test_that("country_codes rejects an unknown column instead of dropping it", {
  # A typo used to return a table quietly missing the requested column.
  expect_error(country_codes("curency"), class = "countryatlas_error")
  expect_error(country_codes(c("iso2c", "curency")), "Unknown column")
  # Friendly shortcuts and raw codelist column names both still work.
  expect_true(all(c("country", "iso3c", "iso2c", "currency") %in%
                    names(country_codes(c("iso2c", "currency")))))
  # A raw codelist column is accepted as input but comes back under its
  # friendly name, which is what country_codes() documents.
  expect_true("currency" %in% names(country_codes("iso4217c")))
  expect_gt(ncol(country_codes()), 5L)
})

# --- reference data -----------------------------------------------------------

test_that("the United Kingdom is an EU member through 31 January 2020", {
  # `to` is the first day of non-membership, as for every EFTA departure.
  expect_true(in_group("United Kingdom", "EU", as_of = "2020-01-31"))
  expect_false(in_group("United Kingdom", "EU", as_of = "2020-02-01"))
  expect_true(in_group("Austria", "EFTA", as_of = "1994-12-31"))
  expect_false(in_group("Austria", "EFTA", as_of = "1995-01-01"))
  expect_true(in_group("Austria", "EU", as_of = "1995-01-01"))
})

test_that("wdi_search returns a tidy indicator/name tibble", {
  skip_slow_on_cran()
  # Runs offline against WDI's bundled cache -- no network needed.
  out <- wdi_search("CO2 emissions")
  expect_s3_class(out, "tbl_df")
  expect_named(out, c("indicator", "name"))
  expect_gt(nrow(out), 0L)
  expect_true(all(grepl("CO2", out$name, ignore.case = TRUE)))
  # No match is an empty tibble with the same shape, not an error.
  none <- wdi_search("zzzz_no_such_indicator_zzzz")
  expect_s3_class(none, "tbl_df")
  expect_equal(nrow(none), 0L)
  expect_named(none, c("indicator", "name"))
  # Exactly one match still comes back as a one-row tibble (the branch that
  # reshapes a dimension-less result).
  one <- wdi_search("^Official Moderate Poverty Rate-National$")
  expect_equal(nrow(one), 1L)
  expect_named(one, c("indicator", "name"))
  # Searching the code field works too.
  codes <- wdi_search("SP.POP", field = "indicator")
  expect_gt(nrow(codes), 0L)
  expect_true(all(grepl("SP.POP", codes$indicator, fixed = TRUE)))
})

test_that("in_group() takes one as_of per element, as a panel needs", {
  # as_of had to be length 1, so the natural panel call
  # mutate(eu = in_group(iso3c, "EU", "iso3c", as_of = year)) was impossible
  # and dated membership could not serve the panels it was built for.
  expect_identical(
    in_group(c("GBR", "GBR"), "EU", origin = "iso3c", as_of = c(2016, 2021)),
    c(TRUE, FALSE))
  pan <- data.frame(iso3c = rep(c("GBR", "HRV", "USA"), each = 3),
                    year = rep(c(2012, 2014, 2021), 3))
  pan$eu <- in_group(pan$iso3c, "EU", "iso3c", as_of = pan$year)
  expect_identical(pan$eu, c(TRUE, TRUE, FALSE, FALSE, TRUE, TRUE,
                             FALSE, FALSE, FALSE))
  # Dates, year strings and factors read the same way; a bare year is
  # 1 January, so Croatia (joined 2013-07-01) is out at 2013 and in at mid-year.
  expect_identical(
    in_group(c("HRV", "HRV", "HRV"), "EU", "iso3c",
             as_of = c("2013", "2013-06-30", "2013-07-01")),
    c(FALSE, FALSE, TRUE))
  expect_identical(
    in_group("HRV", "EU", "iso3c", as_of = as.Date("2013-07-01")), TRUE)
  expect_identical(
    in_group(c("FRA", "DEU"), "EU", "iso3c", as_of = factor(c("2016", "2021"))),
    c(TRUE, TRUE))
  # Length 1 is recycled, as before.
  expect_identical(in_group(c("FRA", "GBR"), "EU", "iso3c", as_of = 2021),
                   c(TRUE, FALSE))
})

test_that("in_group() answers NA for a missing date, and validates as_of", {
  skip_slow_on_cran()
  expect_identical(
    in_group(c("FRA", "FRA"), "EU", "iso3c", as_of = c(2020, NA)),
    c(TRUE, NA))
  expect_identical(
    in_group(c("FRA", "FRA"), "EU", "iso3c", as_of = c("2020-01-01", NA)),
    c(TRUE, NA))
  # An unresolvable country is still FALSE, not NA, as documented.
  expect_identical(
    in_group(c("Wakanda", "France"), "EU", as_of = c(2020, 2020)),
    c(FALSE, TRUE))
  expect_error(in_group(c("FRA", "GBR", "DEU"), "EU", "iso3c",
                        as_of = c(2000, 2001)),
               "length 1 or the length")
  expect_error(in_group("FRA", "EU", "iso3c", as_of = "garbage"), "garbage")
  expect_error(in_group("FRA", "EU", "iso3c", as_of = 20.5), "four-digit")
  expect_error(in_group("FRA", "EU", "iso3c", as_of = list(2000)),
               class = "countryatlas_error")
  # country_groups() returns one table, so it stays scalar.
  expect_error(country_groups("EU", as_of = c(2000, 2001)), "single date")
  # An undated group still warns and answers from the snapshot, per row.
  expect_warning(cw <- in_group(c("GBR", "GBR"), "Commonwealth", "iso3c",
                                as_of = c(2000, NA)),
                 "No dated membership")
  expect_identical(cw, c(TRUE, NA))
  # Zero rows in, zero rows out.
  expect_identical(in_group(character(), "EU", "iso3c", as_of = integer()),
                   logical())
})

test_that("dated groups carry spells and suspensions", {
  # Syria was suspended from the Arab League from 2011 to 2023.
  expect_identical(in_group(rep("SYR", 3), "ArabLeague", "iso3c",
                            as_of = c(2010, 2015, 2024)), c(TRUE, FALSE, TRUE))
  # Seychelles left SADC in 2004 and rejoined in 2008; Madagascar was
  # suspended from 2009 to 2014.
  expect_identical(in_group(c("SYC", "SYC", "MDG", "MDG"), "SADC", "iso3c",
                            as_of = c(2006, 2010, 2012, 2015)),
                   c(FALSE, TRUE, FALSE, TRUE))
  h <- countryatlas::country_groups_history
  expect_true(all(h$status %in% c("member", "suspended")))
  # Spells never overlap within a country and group.
  h <- h[order(h$group, h$iso3c, h$from), ]
  same <- h$group[-1] == h$group[-nrow(h)] & h$iso3c[-1] == h$iso3c[-nrow(h)]
  prev_to <- h$to[-nrow(h)]
  expect_false(any(same & (is.na(prev_to) | h$from[-1] < prev_to)))
  # The 4.0.0 groups, dated as documented.
  expect_identical(nrow(country_groups("SCO", as_of = "2017-06-08")), 6L)
  expect_identical(nrow(country_groups("SCO", as_of = "2017-06-09")), 8L)
  expect_true("TWN" %in% country_groups("APEC", as_of = 2000)$iso3c)
  expect_false("MMR" %in% country_groups("RCEP")$iso3c)
  expect_true(in_group("GBR", "CPTPP", "iso3c", as_of = "2024-12-15"))
  expect_false(in_group("GBR", "CPTPP", "iso3c", as_of = "2024-12-14"))
  # Still undated, and said so.
  expect_warning(country_groups("Commonwealth", as_of = 2000), "No dated membership")
})
