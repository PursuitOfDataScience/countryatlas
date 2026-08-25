test_that("standardize_country adds ISO codes and classifications", {
  df <- data.frame(nation = c("U.S.", "S. Korea", "Czechia"), value = 1:3)
  out <- standardize_country(df, nation, warn = FALSE)
  expect_s3_class(out, "tbl_df")
  expect_equal(out$iso3c, c("USA", "KOR", "CZE"))
  expect_equal(out$iso2c, c("US", "KR", "CZ"))
  expect_true(all(c("continent", "region") %in% names(out)))
  expect_equal(out$value, 1:3)
})

test_that("overrides match entities the legacy code dropped", {
  df <- data.frame(region = c("Kosovo", "Micronesia", "Virgin Islands",
                              "Canary Islands", "Saint Martin"))
  out <- standardize_country(df, region, warn = FALSE)
  expect_equal(out$iso3c, c("XKX", "FSM", "VIR", "ESP", "MAF"))
  # Kosovo's continent/region come from the fallback table.
  expect_equal(out$continent[out$iso3c == "XKX"], "Europe")
  expect_false(is.na(out$region[out$iso3c == "XKX"]))
})

test_that("wdj_overrides is extensible", {
  ov <- wdj_overrides(c(Somaliland = "SOM"))
  expect_equal(unname(ov[["Somaliland"]]), "SOM")
  expect_equal(unname(ov[["Kosovo"]]), "XKX")
})

test_that("standardize_country errors on missing column", {
  expect_error(standardize_country(data.frame(a = 1), nope, warn = FALSE),
               class = "countryatlas_error")
})

test_that("standardize_country warns on unmatched", {
  df <- data.frame(x = c("United States", "Wakanda"))
  expect_warning(standardize_country(df, x), class = "countryatlas_warning")
})

# ?country_overrides used to offer de-accenting as an alternative to running in
# a UTF-8 locale. It is not one: iconv's //TRANSLIT is itself locale-dependent,
# so in the C locale -- exactly where the advice was needed -- it yields NA, or
# "Cura?ao" when given an explicit from=, and nothing resolves. The ASCII
# spellings in the override table are what actually work everywhere.

test_that("ASCII spellings resolve regardless of locale", {
  # The property the override table exists for. Run in whatever locale the
  # session has; ASCII must work in all of them.
  expect_equal(suppressWarnings(convert_country("Curacao", to = "iso3c")), "CUW")
  expect_equal(suppressWarnings(convert_country("Aland Islands", to = "iso3c")),
               "ALA")
  expect_equal(suppressWarnings(convert_country("Cote d'Ivoire", to = "iso3c")),
               "CIV")
  # And every key in the table is ASCII, which is what makes that true.
  expect_false(any(grepl("[^ -~]", names(country_overrides()))))
})

test_that("de-accenting resolves in UTF-8 and never resolves wrongly elsewhere", {
  # The behaviour the corrected documentation describes. Asserted against the
  # session's own locale rather than against the Rd text: reading Rd from a test
  # needs the source tree, which is not there under R CMD check.
  skip_on_os("windows")                       # iconv //TRANSLIT differs there
  accented <- "Cura\u00e7ao"
  de <- iconv(accented, to = "ASCII//TRANSLIT")
  if (grepl("UTF-8", Sys.getlocale("LC_CTYPE"), fixed = TRUE)) {
    # In UTF-8 the recipe works, and so does the accented spelling directly.
    expect_false(is.na(de))
    expect_equal(de, "Curacao")
    expect_equal(suppressWarnings(convert_country(de, to = "iso3c")), "CUW")
    expect_equal(suppressWarnings(convert_country(accented, to = "iso3c")), "CUW")
  } else {
    # Outside UTF-8 the outcome belongs to the platform's iconv, not to us. The
    # \u escape makes `accented` UTF-8 *marked* in every locale, so iconv reads
    # it as UTF-8 and only the target charmap varies: glibc has transliteration
    # data for latin1 and still yields "Curacao", while C/POSIX has none and
    # gives NA or "Cura?ao". This assertion used to demand the C outcome from
    # every non-UTF-8 locale, so it failed on CRAN's latin1 Fedora flavours
    # while passing under LC_CTYPE=C. ?country_overrides documents the C case;
    # the invariant that holds everywhere is weaker -- de-accenting may or may
    # not resolve, but it never resolves to a *different* country.
    res <- suppressWarnings(convert_country(de, to = "iso3c"))
    expect_true(is.na(res) || identical(res, "CUW"))
  }
  # Either way, the ASCII spelling in the override table resolves.
  expect_equal(suppressWarnings(convert_country("Curacao", to = "iso3c")), "CUW")
})
