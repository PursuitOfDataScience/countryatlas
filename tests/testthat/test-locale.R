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
