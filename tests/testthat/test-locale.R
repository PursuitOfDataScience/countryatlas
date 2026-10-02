# Case folding under a locale where "i" and "I" are not a case pair.
#
# toupper()/tolower() follow LC_CTYPE. Turkish, Azeri and Crimean Tatar have a
# dotted and a dotless i, so toupper("idn") gives a dotted capital I and
# tolower("ISO3C") a dotless i -- neither of which matches the ASCII
# identifier it is compared against. Every ISO code containing an "i"
# (IDN, IND, IRL, IRN, ISL, ISR, ITA, BIH, CIV, FIN, ...) silently
# resolved to NA for those users.

test_that("ascii_upper / ascii_lower fold only ASCII", {
  expect_identical(ascii_upper("idn"), "IDN")
  expect_identical(ascii_lower("ISO3C"), "iso3c")
  expect_identical(ascii_upper(c("irl", "CHN", NA)), c("IRL", "CHN", NA))
  # Non-ASCII is deliberately left alone: these fold identifiers, not prose.
  # Written as escapes so this file stays pure ASCII: a literal here would
  # depend on how the source is decoded on a non-UTF-8 platform.
  expect_identical(ascii_upper("c\u00f4te"), "C\u00f4TE")
  expect_identical(ascii_lower(""), "")
  expect_identical(ascii_upper(character()), character())
})

test_that("identifier matching does not depend on LC_CTYPE", {
  # LC_CTYPE drives case folding and LC_COLLATE drives comparison; a real
  # Turkish user has both. Deliberately not LC_ALL: that would also move
  # LC_NUMERIC to a decimal comma and destabilise unrelated tests.
  old <- c(ctype = Sys.getlocale("LC_CTYPE"),
           collate = Sys.getlocale("LC_COLLATE"))
  set <- suppressWarnings(Sys.setlocale("LC_CTYPE", "tr_TR.UTF-8"))
  skip_if(!nzchar(set), "tr_TR.UTF-8 locale not available")
  on.exit({
    suppressWarnings(Sys.setlocale("LC_CTYPE", old[["ctype"]]))
    suppressWarnings(Sys.setlocale("LC_COLLATE", old[["collate"]]))
  }, add = TRUE)
  suppressWarnings(Sys.setlocale("LC_COLLATE", "tr_TR.UTF-8"))
  # Confirm the fixture bites: without this the test passes vacuously in any
  # locale that folds i the ASCII way.
  skip_if(identical(toupper("i"), "I"), "locale folds 'i' the ASCII way")

  expect_identical(wdj_to_iso3c("irl", origin = "iso3c"), "IRL")
  expect_identical(resolve_region("ind"), "IND")
  # One unfoldable code used to poison the whole vector: the all() test failed,
  # so the input was reinterpreted as country *names* and every element went NA.
  expect_identical(resolve_region(c("ind", "chn")), c("IND", "CHN"))
  expect_identical(normalize_historical("SOUTH VIETNAM"), "south vietnam")
  # A frame where matching the column *name* is what disambiguates. Folded in
  # the locale, "ISO3C" stopped matching the "iso3c" candidate and the loop fell
  # through to "geo" -- so join_world() joined on Japan/Brazil instead of the
  # ISO codes sitting right there, and said nothing.
  two <- data.frame(ISO3C = c("USA", "FRA"), geo = c("Japan", "Brazil"),
                    stringsAsFactors = FALSE)
  picked <- detect_country_col(two)
  expect_identical(as.character(picked), "ISO3C")
  expect_identical(attr(picked, "origin"), "iso3c")
})

test_that("the sf paths survive hostile formatting options", {
  skip_slow_on_cran()
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  for (opt in list(list(OutDec = ","), list(scipen = -9),
                   list(OutDec = ",", scipen = -9))) {
    old <- options(opt)
    expect_gt(nrow(suppressWarnings(attach_geometry(snap, geometry = "sf"))), 0L)
    expect_gt(nrow(suppressWarnings(
      world_geometry("countries", geometry = "sf",
                     projection = "orthographic", recenter = 48.9))), 0L)
    expect_gt(nrow(suppressWarnings(world_geometry("graticule",
                                                   geometry = "sf"))), 0L)
    expect_equal(nrow(suppressWarnings(locate_country(2.3, 48.9))), 1L)
    options(old)
  }
})

test_that("the verbs survive hostile number-formatting options", {
  skip_slow_on_cran()
  # A comma decimal mark is ordinary in much of the world, and fmt_num() exists
  # so a PROJ string never depends on it. (A *negative* scipen is not covered:
  # it breaks sf and ggplot2 on their own -- st_crs(paste0("EPSG:", 4326))
  # becomes "EPSG:4.326e+03" -- with this package not even loaded.)
  skip_if_no_sf_geometry()
  snap <- countryatlas::world_snapshot$countries
  sfd <- attach_geometry(snap, geometry = "sf")
  with_opts <- function(o, code) {
    old <- options(o)
    on.exit(options(old), add = TRUE)
    force(code)
  }
  # expect_no_error() takes no `info`, so report the option and the message.
  survives <- function(o, code) {
    tryCatch({
      with_opts(o, force(code))
      TRUE
    }, error = function(e) conditionMessage(e))
  }
  # stringsAsFactors is deliberately absent: R deprecated it, so merely setting
  # it warns, and it no longer affects data.frame() on the versions we support.
  for (o in list(list(OutDec = ","), list(scipen = 0L), list(digits = 3L),
                 list(warn = 2L), list(useFancyQuotes = FALSE))) {
    lbl <- paste(names(o), unlist(o), sep = "=")
    expect_true(isTRUE(survives(o, ggplot2::ggplot_build(
      world_map(sfd, gdp_per_capita)))), info = lbl)
    expect_true(isTRUE(survives(o, world_geometry("countries",
                                                 geometry = "sf"))), info = lbl)
    expect_true(isTRUE(survives(o, locate_country(lon = 2.3, lat = 48.8))),
                info = lbl)
    expect_true(isTRUE(survives(o, convert_country("France", to = "iso3c"))),
                info = lbl)
    expect_true(isTRUE(survives(o, world_query(gdp_per_capita))), info = lbl)
  }
})
