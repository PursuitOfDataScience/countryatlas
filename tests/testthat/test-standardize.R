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

test_that("NFD-decomposed accented names resolve, and NFC ones are untouched", {
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
    suppressWarnings(convert_country(v, from = "iso3c", to = "iso3c",
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
  expect_equal(suppressWarnings(convert_country(k, from = "iso3c", to = "iso3c")), k)
  ov <- country_overrides()
  expect_false(any(is.na(suppressWarnings(
    convert_country(names(ov), from = "iso3c", to = "iso3c", custom_match = ov)))))
  # Junk is still junk.
  expect_true(is.na(conv("ZZZ")))
  expect_true(is.na(conv("")))
})
