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

test_that("country_overrides is extensible", {
  ov <- country_overrides(c(Somaliland = "SOM"))
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

test_that("NFD-decomposed accented names resolve, and NFC ones are untouched", {
  skip_slow_on_cran()
  # The section above covers the *locale* half of the accented-name problem.
  # This is the other half: the same accent can be one precomposed code point
  # (NFC, the form countrycode's tables carry) or a base letter followed by a
  # combining mark (NFD, the form macOS hands back for filenames). Those are
  # different strings, so the NFD spellings used to resolve to NA even in a
  # UTF-8 locale -- exactly where ?country_overrides says accented names work.
  #
  # Every string here is assembled from code points rather than written
  # literally, for two reasons: NFC and NFD render identically, so a literal
  # would make this test unreadable and unreviewable, and it keeps the file
  # ASCII like the rest of the package.
  cp <- function(...) intToUtf8(c(...))
  DIAERESIS <- 0x308L; TILDE <- 0x303L; ACUTE <- 0x301L
  RING <- 0x30AL; CEDILLA <- 0x327L

  pairs <- list(
    TUR = c(nfc = paste0("T", cp(0xFC), "rkiye"),
            nfd = paste0("T", cp(0x75, DIAERESIS), "rkiye")),
    STP = c(nfc = paste0("S", cp(0xE3), "o Tom", cp(0xE9), " and Principe"),
            nfd = paste0("S", cp(0x61, TILDE), "o Tom", cp(0x65, ACUTE),
                         " and Principe")),
    ALA = c(nfc = paste0(cp(0xC5), "land Islands"),
            nfd = paste0(cp(0x41, RING), "land Islands")),
    CUW = c(nfc = paste0("Cura", cp(0xE7), "ao"),
            nfd = paste0("Cura", cp(0x63, CEDILLA), "ao")),
    REU = c(nfc = paste0("R", cp(0xE9), "union"),
            nfd = paste0("R", cp(0x65, ACUTE), "union"))
  )

  for (code in names(pairs)) {
    pr <- pairs[[code]]
    # Guard the premise: if these ever stopped being distinct strings the test
    # would pass while exercising nothing.
    expect_false(identical(pr[["nfc"]], pr[["nfd"]]))
    # NFC is the form that already worked; it has to keep working everywhere.
    expect_equal(suppressWarnings(convert_country(pr[["nfc"]], to = "iso3c")),
                 code)
    got <- suppressWarnings(convert_country(pr[["nfd"]], to = "iso3c"))
    if (l10n_info()$`UTF-8`) {
      expect_equal(got, code)
    } else {
      # The weaker invariant the de-accenting test above settles for: outside
      # UTF-8 the platform's regex engine decides whether the mark is seen at
      # all, but a decomposed name must never resolve to a *different*
      # country.
      expect_true(is.na(got) || identical(got, code))
    }
  }

  # Only the NA results are retried, so the second pass can add a match but
  # never move one -- the property that makes this safe. Nothing that resolved
  # before may change, and a non-country stays unresolved.
  nms <- c(country_meta$country, names(country_overrides()))
  nms <- unique(nms[!is.na(nms) & nzchar(nms)])
  direct <- suppressWarnings(countrycode::countrycode(
    nms, "country.name", "iso3c",
    custom_match = country_overrides(), warn = FALSE))
  through <- suppressWarnings(convert_country(nms, to = "iso3c"))
  expect_equal(through[!is.na(direct)], direct[!is.na(direct)])
  expect_true(is.na(suppressWarnings(convert_country("Freedonia", to = "iso3c"))))

  # A vector mixing NFD, NFC, ASCII, junk and NA resolves element-wise: the
  # retry has to write its results back into the right positions.
  mixed <- c(pairs$TUR[["nfd"]], "France", "Freedonia", pairs$ALA[["nfd"]],
             NA, "USA")
  got <- suppressWarnings(convert_country(mixed, to = "iso3c"))
  expect_equal(got[c(2, 3, 5, 6)], c("FRA", NA, NA, "USA"))
  if (l10n_info()$`UTF-8`) expect_equal(got[c(1, 4)], c("TUR", "ALA"))

  # The helper itself: marks go, everything else stays byte-for-byte.
  strip <- countryatlas:::strip_combining
  expect_identical(strip(c("France", "USA", NA)), c("France", "USA", NA))
  expect_identical(strip(character(0)), character(0))
  expect_identical(strip(pairs$TUR[["nfd"]]), "Turkiye")
  # A precomposed character is not a combining mark, so NFC is left alone.
  expect_identical(strip(pairs$TUR[["nfc"]]), pairs$TUR[["nfc"]])
})


test_that("origin = iso3c trims Unicode whitespace, and keys overrides on it", {
  # Two halves of one defect in the iso3c branch. It trims, deliberately, so
  # that a code carrying spreadsheet padding still resolves -- but trimws()'s
  # default class is [ \t\r\n], ASCII only, so a non-breaking space survived;
  # and the override lookup matched the *raw* value while the whitelist was
  # built from the trimmed one, so padding was tolerated for a real code and
  # not for an overridden spelling.
  cp <- function(...) intToUtf8(c(...))
  NB <- cp(0xA0)      # non-breaking space, what a web-table paste carries
  THIN <- cp(0x2009)  # thin space
  cm <- c(Somaliland = "SOM", Kosovo = "XKX")

  conv <- function(v) {
    suppressWarnings(convert_country(v, origin = "iso3c", to = "iso3c",
                                     custom_match = cm))
  }
  # A real code, with each flavour of padding.
  expect_equal(conv("FRA"), "FRA")
  expect_equal(conv("FRA "), "FRA")
  expect_equal(conv(paste0("FRA", NB)), "FRA")
  expect_equal(conv(paste0("FRA", THIN)), "FRA")
  expect_equal(conv("\tFRA\n"), "FRA")
  expect_equal(conv(paste0(NB, "fra", NB)), "FRA")

  # An overridden spelling, same padding. A plain trailing space was enough to
  # break this one -- no Unicode needed.
  expect_equal(conv("Somaliland"), "SOM")
  expect_equal(conv("Somaliland "), "SOM")
  expect_equal(conv(paste0("Somaliland", NB)), "SOM")
  expect_equal(conv("Kosovo "), "XKX")

  # A BOM and a zero-width space are format characters, not whitespace, and
  # are deliberately left in place -- so they still fail rather than being
  # silently accepted.
  expect_true(is.na(conv(paste0(cp(0xFEFF), "FRA"))))

  # Nothing that resolved before may change: every known code, and every name
  # in the shipped override table.
  k <- countryatlas:::wdj_known_iso3c()
  expect_equal(suppressWarnings(convert_country(k, origin = "iso3c", to = "iso3c")), k)
  ov <- country_overrides()
  expect_false(any(is.na(suppressWarnings(
    convert_country(names(ov), origin = "iso3c", to = "iso3c", custom_match = ov)))))
  # Junk is still junk.
  expect_true(is.na(conv("ZZZ")))
  expect_true(is.na(conv("")))
})

test_that("custom_match must be a name -> iso3c map", {
  skip_slow_on_cran()
  # `origin` was checked and the override table was not, though every value in
  # it lands in the iso3c column -- and wdj_to_iso3c()'s iso3c branch
  # whitelists those values as valid by construction, so nothing downstream
  # rejected them either. custom_match = c(Freedonia = 1) put "1" in iso3c.
  d <- tibble::tibble(n = c("France", "Freedonia"))
  expect_error(standardize_country(d, n, custom_match = c(Freedonia = 1)),
               "named character vector")
  expect_error(standardize_country(d, n, custom_match = c("FRA")),
               "named character vector")
  expect_error(standardize_country(d, n, custom_match = c(Freedonia = TRUE)),
               "named character vector")

  # The shapes that worked still work.
  ok <- suppressWarnings(
    standardize_country(d, n, custom_match = c(Freedonia = "FRA")))
  expect_equal(ok$iso3c, c("FRA", "FRA"))
  expect_no_error(suppressWarnings(
    standardize_country(d, n, custom_match = character(0))))
  expect_no_error(suppressWarnings(standardize_country(d, n)))
  # Including the bundled table, which is exactly this shape.
  expect_type(country_overrides(), "character")
  expect_false(is.null(names(country_overrides())))
})

test_that("`add` reports its own problems, not countrycode's", {
  skip_slow_on_cran()
  # `add` names attributes to derive from iso3c. Unvalidated, its problems came
  # back under somebody else's argument: countrycode's `destination` for an
  # unknown name ("must be ... one of the column names in the conversion
  # directory"), convert_country()'s `to` in locate_country(), and base R's
  # bare "missing value where TRUE/FALSE needed" for an NA.
  d <- tibble::tibble(n = "France")
  expect_error(standardize_country(d, n, add = "nope"), "`add` names")
  expect_error(standardize_country(d, n, add = 1), "`add` must be a character")
  expect_error(standardize_country(d, n, add = NA), "`add` must be a character")
  expect_error(standardize_country(d, n, add = TRUE), "`add` must be a character")

  # Both kinds of valid name still work: the shortcuts and any raw countrycode
  # destination.
  expect_no_error(suppressWarnings(standardize_country(d, n, add = "continent")))
  expect_no_error(suppressWarnings(standardize_country(d, n, add = "iso4217c")))
  expect_no_error(suppressWarnings(standardize_country(d, n, add = character(0))))
  expect_equal(ncol(suppressWarnings(standardize_country(d, n))), 5L)

  # locate_country() shares the check.
  skip_if_no_sf_geometry()
  expect_error(locate_country(2.35, 48.86, add = "nope"), "`add` names")
  expect_error(locate_country(2.35, 48.86, add = 1), "`add` must be a character")

  # The shortcut table and the validator cannot drift: check_add() validates
  # against exactly the map wdj_derive_from_iso3c() uses.
  expect_true(all(names(countryatlas:::WDJ_DEST_MAP) %in%
                    c("iso2c", "continent", "region", "region23", "un_region",
                      "country", "flag", "currency", "tld")))
})

test_that("standardize_country says when it clobbers columns you did not ask for", {
  skip_slow_on_cran()
  # `add` defaults to c("iso3c", "iso2c", "continent", "region"), so the call
  # everyone makes -- standardize_country(d, country), to get iso3c -- also
  # replaced any continent/region/iso2c the caller already had, silently. Eleven
  # other column-adding verbs report exactly this via warn_overwrite(); the
  # package's headline function did not. A user's own regional classification is
  # not the package's to discard without a word.
  d <- data.frame(country = c("France", "Brazil"),
                  continent = c("MY-EU", "MY-SA"), region = c("R1", "R2"),
                  v = 1:2)
  expect_warning(standardize_country(d, country),
                 class = "countryatlas_unasked_overwrite")
  expect_warning(standardize_country(d, country), "continent")
  expect_warning(standardize_country(d, country), "region")

  # Naming `add` yourself means you asked for it: no warning, per the
  # documented contract that `add` names the columns literally.
  expect_silent(standardize_country(d, country, add = c("iso3c", "continent")))
  # And asking only for the code leaves your columns alone.
  expect_silent(r <- standardize_country(d, country, add = "iso3c"))
  expect_identical(r$continent, d$continent)
  expect_identical(r$region, d$region)
  expect_equal(r$iso3c, c("FRA", "BRA"))
  # warn = FALSE silences it; a frame with nothing to clobber is quiet anyway.
  expect_silent(standardize_country(d, country, warn = FALSE))
  expect_silent(standardize_country(data.frame(country = "France"), country))
  # iso3c is never counted: replacing it is the point of the function.
  d2 <- data.frame(country = "France", iso3c = "XXX")
  expect_silent(s2 <- standardize_country(d2, country, add = "iso3c"))
  expect_equal(s2$iso3c, "FRA")
})

test_that("names in other languages match, and say how", {
  skip_slow_on_cran()
  # Built with escapes: the package source is ASCII.
  ru <- "\u0413\u0435\u0440\u043c\u0430\u043d\u0438\u044f"
  zh <- "\u5fb7\u56fd"
  ja <- "\u30c9\u30a4\u30c4"
  x <- c("Allemagne", "Deutschland", "Alemania", "Elfenbeinkueste", ru, zh, ja,
         "U.K.", "Kosovo", "Wakanda")
  r <- check_country_match(x, suggest = FALSE)
  expect_identical(r$iso3c, c("DEU", "DEU", "DEU", "CIV", "DEU", "DEU", "DEU",
                              "GBR", "XKX", NA))
  expect_identical(r$method, c("name_fr", "name_de", "name_es", "name_de",
                               "cldr", "cldr", "cldr", "regex_en", "override",
                               "none"))
  # Exact, so a territory the English patterns leave alone stays alone, and
  # a two-letter code is not taken for a name.
  guard <- check_country_match(c("Somaliland", "Indian Ocean Territories",
                                 "FR", "DE"), suggest = FALSE)
  expect_true(all(is.na(guard$iso3c)))
  # Lower case in any script, without the locale: Cyrillic too.
  expect_identical(convert_country(
    "\u0433\u0435\u0440\u043c\u0430\u043d\u0438\u044f"), "DEU")
  # The tiers reach every verb that matches names.
  expect_identical(convert_country(ru), "DEU")
  # A name the CLDR tables give to more than one country names none.
  # Russian "Kongo", for both Congos.
  amb <- "\u041a\u043e\u043d\u0433\u043e"
  expect_true(countryatlas:::fold_name(amb) %in% countryatlas:::cldr_index()$ambiguous)
  expect_identical(check_country_match(amb, suggest = FALSE)$method, "ambiguous")
  # Built once per session, and quickly (measured at about 0.2 s).
  rm(list = ls(countryatlas:::.name_index), envir = countryatlas:::.name_index)
  t0 <- proc.time()[["elapsed"]]
  invisible(countryatlas:::cldr_index())
  expect_lt(proc.time()[["elapsed"]] - t0, 2)
})

test_that("standardize_country() derives once per distinct value", {
  set.seed(2)
  nm <- c("France", "Germany", "Allemagne", "Wakanda", "U.K.", NA)
  d <- data.frame(country = sample(nm, 5000, TRUE))
  got <- suppressWarnings(standardize_country(d, country))
  ref <- suppressWarnings(countryatlas:::wdj_to_iso3c(d$country))
  expect_identical(got$iso3c, ref)
  expect_identical(got$continent[got$iso3c %in% "FRA"][1], "Europe")
  expect_identical(nrow(got), 5000L)
})
