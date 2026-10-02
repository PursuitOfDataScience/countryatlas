# Country-name standardisation --------------------------------------------------

# Convert raw country identifiers to iso3c, applying overrides and (optionally)
# warning about misses. `origin` is any countrycode origin scheme
# ("country.name", "iso2c", "iso3c", "wb", ...).
wdj_to_iso3c <- function(x, origin = "country.name", custom_match = country_overrides(),
                         call = rlang::caller_env(), arg = "origin",
                         with_method = FALSE) {
  check_string(origin, arg, call = call)
  # `origin` was checked and the override table was not, though every value in
  # it lands in the iso3c column -- and the iso3c branch below whitelists those
  # values as valid by construction, so nothing downstream rejects them either.
  # custom_match = c(Freedonia = 1) therefore put "1" in iso3c and every join
  # after it keyed on that. The table is a name -> iso3c map; require the shape.
  # is.null(names()) catches a wholly unnamed vector but not a partly named
  # one: c(Freedonia = "FRA", "DEU") has names c("Freedonia", ""), and an entry
  # whose name is "" or NA can never match a spelling, so it sat there doing
  # nothing while the caller believed it was overriding something. That is the
  # same silent-but-useless entry the comment above describes, so require the
  # shape of every element, not just of the vector.
  unnamed <- if (is.null(names(custom_match))) {
    length(custom_match) > 0L
  } else {
    any(is.na(names(custom_match)) | !nzchar(names(custom_match)))
  }
  if (length(custom_match) && (!is.character(custom_match) || unnamed)) {
    wdj_abort(c(
      "{.arg custom_match} must be a named character vector.",
      "x" = if (!is.character(custom_match)) {
        "Got {.cls {class(custom_match)[1]}}."
      } else if (is.null(names(custom_match))) {
        "Got a character vector with no names."
      } else {
        "{sum(is.na(names(custom_match)) | !nzchar(names(custom_match)))} of
         {length(custom_match)} entries have no name, so they can never match."
      },
      "i" = "Names are the spellings to override, values are {.field iso3c}
             codes -- the shape {.fn country_overrides} returns."
    ), call = call)
  }
  # as.character() on a data frame deparses each *column* into a string, so a
  # frame handed to a verb that wants a country vector came back as the two
  # "countries" `c("USA", "FRA")` and `c(1, 2)` -- silently, because those are
  # just strings that match nothing and every row then reads as "not found".
  # Nearly every other verb here takes `data` first, so this is the natural
  # mistake: neighbors(my_df), convert_country(my_df), in_group(my_df, "EU"),
  # dissolve_country(), country_timeline(), check_country_match(),
  # repair_country_names() and distance_between() all accepted it. gini() and
  # theil() already refused a data frame; this is the same refusal, one level
  # down, where every one of them passes through.
  check_country_vector(x, call = call)
  x <- as.character(x)
  if (identical(origin, "iso3c")) {
    # trimws()'s default class is [ \t\r\n], which is ASCII whitespace only,
    # so a non-breaking space -- what a code copied out of a web table or a
    # Word document carries -- survived the trim and then matched nothing:
    # "FRA " resolved and "FRA<nbsp>" did not. [\h\v] is PCRE for every
    # horizontal and vertical Unicode space, and trimws() already substitutes
    # with perl = TRUE. A BOM or a zero-width space is a format character
    # rather than whitespace and is deliberately still left alone.
    xt <- trimws(x, whitespace = "[\\h\\v]")
    out <- ascii_upper(xt)
    # Still let overrides repair known-bad spellings -- keyed on the *trimmed*
    # value. The whitelist below is built from `out`, which is trimmed, so
    # matching raw `x` here meant padding was tolerated for a real code but
    # not for an overridden spelling: with country_overrides(),
    # "Somaliland" gave SOM and "Somaliland " gave NA, because the override
    # missed and "SOMALILAND" then failed the whitelist. An ordinary trailing
    # space out of a spreadsheet was enough.
    if (length(custom_match)) {
      hit <- match(xt, names(custom_match))
      out[!is.na(hit)] <- unname(custom_match[hit[!is.na(hit)]])
    }
    valid <- c(wdj_known_iso3c(), unname(custom_match))
    out[!is.na(out) & !(out %in% valid)] <- NA_character_
    if (isTRUE(with_method)) {
      return(list(iso3c = out, method = ifelse(is.na(out), "none", "code")))
    }
    return(out)
  }
  cc <- function(vals) {
    tryCatch(
      suppressWarnings(
        countrycode::countrycode(
          vals,
          origin = origin,
          destination = "iso3c",
          custom_match = if (length(custom_match)) custom_match else NULL,
          warn = FALSE
        )
      ),
      error = function(e) {
        if (grepl("`origin`", conditionMessage(e), fixed = TRUE)) {
          abort_bad_origin(origin, e, call, arg)
        }
        stop(e)
      }
    )
  }
  out <- cc(x)
  # The curated codes have no codelist row, so countrycode cannot read them
  # back: every iso2c column the package writes says "XK" for Kosovo, and
  # convert_country("XK", origin = "iso2c") then resolved to NA.
  if (identical(origin, "iso2c")) {
    fb <- wdj_code_fallback()
    up <- ascii_upper(trimws(x, whitespace = "[\\h\\v]"))
    k <- is.na(out) & up %in% fb$iso2c
    out[k] <- fb$iso3c[match(up[k], fb$iso2c)]
  }
  # Second pass for the spellings that resolved to nothing, on the
  # combining-mark-stripped form. See strip_combining() for why.
  miss <- is.na(out) & !is.na(x)
  if (any(miss)) {
    alt <- strip_combining(x[miss])
    redo <- alt != x[miss]
    if (any(redo)) {
      patch <- out[miss]
      patch[redo] <- cc(alt[redo])
      out[miss] <- patch
    }
  }
  method <- ifelse(is.na(out), NA_character_,
                   ifelse(x %in% names(custom_match), "override", "regex_en"))
  # Then the names in other languages: see match_name_tiers().
  if (identical(origin, "country.name")) {
    miss <- is.na(out) & !is.na(x) & nzchar(trimws(x))
    if (any(miss)) {
      ux <- unique(x[miss])
      tiers <- match_name_tiers(ux)
      at <- match(x[miss], ux)
      out[miss] <- tiers$iso3c[at]
      method[miss] <- tiers$method[at]
    }
  }
  if (isTRUE(with_method)) {
    method[is.na(method)] <- "none"
    return(list(iso3c = out, method = method))
  }
  out
}

# Drop Unicode combining marks: "Turkiye" written as `u` + a combining
# diaeresis rather than as the precomposed u-with-diaeresis becomes plain
# "Turkiye".
#
# Accented country names are a documented concern here (see the "Accented names
# and locales" section of country_overrides()), but only for the *locale* half
# of the problem -- the note says accented spellings match natively in a UTF-8
# locale, and they do, in NFC. NFD is a different byte sequence from the NFC
# form countrycode's tables carry, so it matched nothing even in a UTF-8
# locale: Turkiye, Sao Tome and Aland (in their accented spellings) all came
# back NA. macOS returns NFD for
# filenames and several export paths emit it, so this is input a user gets
# without ever choosing it, and the failure is silent -- just an unmatched
# name.
#
# Base R has no Unicode normaliser and DESCRIPTION pins no stringi, so rather
# than normalise to NFC this strips the marks, which turns an NFD spelling into
# the ASCII spelling the package already documents as resolving in any locale.
# Cote d'Ivoire matched before this and still does: countrycode's regex keys on
# the ASCII substring, which decomposition leaves alone.
strip_combining <- function(x) {
  out <- x
  # Only non-ASCII values can carry a mark, and combining marks are the one
  # thing removed, so an accent-free name is untouched either way.
  hi <- !is.na(x) & grepl("[^[:ascii:]]", x, perl = TRUE)
  if (any(hi)) {
    # U+0300-U+036F sits inside the BMP. A range over *astral* code points
    # would not be portable -- Windows wchar_t is 16-bit and TRE rejects
    # those (it broke a flag-emoji test here) -- but this one is fine.
    out[hi] <- gsub("[\\x{0300}-\\x{036F}]", "", x[hi], perl = TRUE)
  }
  out
}

# Refuse a data frame where a country vector belongs. Called from the three
# places that coerce a caller's identifiers -- wdj_to_iso3c(), and the two that
# run as.character() before reaching it.
check_country_vector <- function(x, call = rlang::caller_env()) {
  if (is.data.frame(x)) {
    wdj_abort(c(
      "Country identifiers must be a vector, not a data frame.",
      "x" = "Got a data frame with {ncol(x)} column{?s}.",
      "i" = "Pass the identifiers themselves, e.g. {.code data$iso3c}."
    ), call = call, class = "countryatlas_frame_as_vector")
  }
  # A data frame is only the common case: as.character() deparses *any* list
  # element that is not a single value, so list(c("FRA", "DEU")) collapses to
  # the one string `c("FRA", "DEU")` and convert_country() returned a single NA
  # where two codes were asked for. A flat list of scalars -- list("FRA",
  # "DEU") -- coerces correctly and is left alone, as is a matrix, which
  # flattens.
  if (is.list(x) && length(x) &&
      !all(lengths(x) == 1L & vapply(x, is.atomic, logical(1)))) {
    wdj_abort(c(
      "Country identifiers must be a vector, not a list.",
      "x" = "Some elements are not single values, so {.code as.character()}
             renders them as text like
             {.val {utils::head(as.character(x), 1L)}}.",
      "i" = "Flatten it first with {.code unlist()}."
    ), call = call, class = "countryatlas_frame_as_vector")
  }
  invisible(NULL)
}

# countrycode names the schemes it accepts in its own error. Read them back from
# there rather than hardcoding a list that would drift from whatever version is
# installed.
countrycode_schemes <- function(msg) {
  part <- sub("^.*one of these values:[[:space:]]*", "", msg)
  if (identical(part, msg)) return(character(0))
  vals <- sub("[.]$", "", trimws(strsplit(part, ",")[[1]]))
  vals[nzchar(vals)]
}

# countrycode's destination error names no valid values -- it points at "the
# column names in the conversion directory" -- so read them from codelist
# instead of parsing the message, as abort_bad_origin() has to.
abort_bad_destination <- function(shown, arg = "to",
                                  call = rlang::caller_env()) {
  valid <- tryCatch(names(countrycode::codelist),
                    error = function(e) character(0))
  extra <- tryCatch(names(convert_dest_map()), error = function(e) character(0))
  ok <- unique(c(extra, valid))
  near <- character(0)
  if (length(ok)) {
    # ascii_lower(), not tolower(): under tr_TR the latter returns a dotless
    # i, so "ISO3C" folded to "iso3c" with a dotless i while the candidate
    # list stayed ASCII -- and the "Did you mean" suggestion silently
    # vanished. The exemption for the fuzzy matchers does not apply here: the
    # candidate lists are already lowercase, so folding them is a no-op while
    # folding the *input* mangles it.
    lo <- ascii_lower(shown)
    vl <- ascii_lower(ok)
    hit <- grepl(lo, vl, fixed = TRUE) | startsWith(lo, vl)
    near <- ok[hit]
    if (!length(near)) {
      d <- utils::adist(lo, vl)[1, ]
      near <- ok[d <= 2L][order(d[d <= 2L])]
    } else {
      near <- near[order(nchar(near), near)]
    }
    near <- utils::head(near, 3L)
  }
  eg <- intersect(c("iso3c", "iso2c", "country", "continent", "region",
                    "currency"), ok)
  wdj_abort(c(
    "{.arg {arg}} {.val {shown}} is not a country attribute.",
    if (length(near)) c("i" = "Did you mean {.val {near}}?"),
    if (length(eg)) {
      c("i" = "Try one of {.val {eg}}, any
               {.fn countrycode::countrycode} destination, or a
               {.val name_fr}-style localised name.")
    }
  ), call = call, class = "countryatlas_bad_destination")
}

# `origin` is user-facing on seventeen exported functions -- neighbors(),
# country_join(), standardize_country(), flow_map(), country_timeline(),
# in_group(), convert_country(`from`) and friends -- and check_string() only
# proves it is a string. An
# invalid scheme therefore travelled all the way into countrycode() and died
# there, so `origin = "country"` (the obvious spelling for a column of names)
# raised "The `origin` argument must be a string of length 1 equal to one of
# these values:" followed by forty items, attributed to a call the user never
# made. Re-raise it as ours and name the scheme they probably meant.
abort_bad_origin <- function(origin, cnd, call = rlang::caller_env(),
                             arg = "origin") {
  valid <- countrycode_schemes(conditionMessage(cnd))
  near <- character(0)
  if (length(valid)) {
    lo <- ascii_lower(origin)
    vl <- ascii_lower(valid)
    # A half-remembered scheme is normally a fragment of the real name --
    # "country" for "country.name", "iso3" for "iso3c" -- which edit distance
    # ranks badly: "country" is five edits from "country.name", so the one
    # suggestion that mattered was missing, while "name" was answered with
    # "fao" and "imf" at distance three. Match on containment first, shortest
    # candidate first, and only fall back to a tight distance.
    hit <- grepl(lo, vl, fixed = TRUE) | startsWith(lo, vl)
    near <- valid[hit]
    if (!length(near)) {
      d <- utils::adist(lo, vl)[1, ]
      near <- valid[d <= 2L][order(d[d <= 2L])]
    } else {
      near <- near[order(nchar(near), near)]
    }
    near <- utils::head(near, 3L)
  }
  # Alphabetical order opens with "cctld", which nobody wants; lead with the
  # schemes this package's own callers actually pass.
  eg <- intersect(c("country.name", "iso3c", "iso2c", "wb", "un", "eurostat"),
                  valid)
  wdj_abort(c(
    "{.arg {arg}} {.val {origin}} is not a country-coding scheme.",
    if (length(near)) c("i" = "Did you mean {.val {near}}?"),
    if (length(eg)) {
      c("i" = "Any {.fn countrycode::countrycode} origin works, for example
               {.val {eg}}.")
    } else {
      c("i" = "{conditionMessage(cnd)}")
    }
  ), call = call, class = "countryatlas_bad_origin")
}

# The shortcut names `add` accepts, mapped to countrycode destinations. Lifted
# out of wdj_derive_from_iso3c() so check_add() validates against exactly the
# set the derivation understands, rather than a second copy that can drift.
WDJ_DEST_MAP <- c(
  iso2c     = "iso2c",
  continent = "continent",
  region    = "region",
  region23  = "region23",
  un_region = "un.region.name",
  country   = "country.name.en",
  flag      = "unicode.symbol",
  currency  = "iso4217c",
  tld       = "cctld"
)

# `add` names attributes to derive from iso3c: a shortcut above, or any raw
# countrycode destination. Unvalidated, its problems were reported under
# somebody else's argument -- countrycode's `destination` for an unknown name,
# convert_country()'s `to` in locate_country(), and base R's bare "missing
# value where TRUE/FALSE needed" for an NA.
check_add <- function(add, arg = "add", call = rlang::caller_env()) {
  if (!length(add)) return(invisible(add))
  if (!is.character(add) || anyNA(add)) {
    wdj_abort(c(
      "{.arg {arg}} must be a character vector of attribute names.",
      "x" = if (anyNA(add)) "It contains {.val {NA}}."
            else "Got {.cls {class(add)[1]}}."
    ), call = call)
  }
  known <- unique(c("iso3c", names(WDJ_DEST_MAP),
                    names(countrycode::codelist)))
  bad <- setdiff(add, known)
  if (length(bad)) {
    wdj_abort(c(
      "{.arg {arg}} names {length(bad)} attribute{?s} that cannot be derived:
       {.val {bad}}.",
      "i" = "Use one of {.val {names(WDJ_DEST_MAP)}}, or any column of
             {.code countrycode::codelist}."
    ), call = call)
  }
  invisible(add)
}

# Derive a set of attributes from iso3c. `add` may name any countrycode
# destination; the common shortcuts (iso2c, continent, region) are handled
# explicitly with fallbacks for codes countrycode does not know.
wdj_derive_from_iso3c <- function(iso3c, add) {
  check_add(add)
  out <- tibble::tibble(iso3c = iso3c)
  dest_map <- WDJ_DEST_MAP
  for (a in add) {
    if (a == "iso3c") next
    dest <- if (a %in% names(dest_map)) dest_map[[a]] else a # allow raw countrycode destinations
    out[[a]] <- suppressWarnings(
      countrycode::countrycode(iso3c, origin = "iso3c", destination = dest, warn = FALSE)
    )
  }
  out <- apply_code_fallback(out)
  out
}

#' Add ISO codes and classifications to any data frame
#'
#' The package's mission, exposed for *your* data: take a data frame keyed on
#' messy country names (or codes) and attach standardised ISO codes plus useful
#' classifications, reconciling spellings via [countrycode::countrycode()] and
#' the curated [country_overrides()] table. The result joins cleanly to anything
#' else keyed on `iso3c`.
#'
#' @param data A data frame / tibble.
#' @param country_col The column holding country names or codes
#'   (unquoted, tidy-eval).
#' @param origin How to read `country_col`; any [countrycode::countrycode()]
#'   origin scheme such as `"country.name"` (default), `"iso2c"`, `"iso3c"`,
#'   `"wb"`, `"un"`.
#' @param add Character vector of attributes to add. Defaults to
#'   `c("iso3c", "iso2c", "continent", "region")`. Any countrycode destination
#'   is accepted, plus the shortcuts `"flag"`, `"currency"`, `"tld"`.
#' @param custom_match A named character vector of name -> iso3c overrides;
#'   defaults to [country_overrides()]. Merged on top of the built-in matching.
#' @param warn Whether to warn about unmatched countries (default `TRUE`).
#'
#' @return `data` with the requested columns added (and existing same-named
#'   columns overwritten).
#' @export
#' @examples
#' df <- data.frame(nation = c("U.S.", "S. Korea", "Czechia"), value = 1:3)
#' standardize_country(df, nation)
standardize_country <- function(data,
                                country_col,
                                origin = "country.name",
                                add = c("iso3c", "iso2c", "continent", "region"),
                                custom_match = country_overrides(),
                                warn = TRUE) {
  check_bool(warn, "warn")
  # Whether the caller chose `add` or took the default decides, below, if
  # clobbering their columns is worth a word. missing() has to be read before
  # `add` is touched.
  add_defaulted <- missing(add)
  if (!is.data.frame(data)) {
    wdj_abort("{.arg data} must be a data frame.")
  }
  col_q <- rlang::enquo(country_col)
  if (rlang::quo_is_missing(col_q)) {
    wdj_abort("{.arg country_col} is required.")
  }
  col_name <- tryCatch(rlang::as_name(col_q), error = function(e) NULL)
  if (is.null(col_name) || !col_name %in% names(data)) {
    wdj_abort("Column {.val {col_name %||% rlang::as_label(col_q)}} not found in {.arg data}.")
  }

  # Before the c() below, which would coerce a numeric `add` to character and
  # make it look like an unknown attribute name rather than a wrong type.
  check_add(add)
  add <- unique(c("iso3c", add))
  raw <- data[[col_name]]
  # Matched and derived once per distinct value, then expanded: a million
  # rows of two hundred names spent most of their time deriving iso2c,
  # continent and region row by row.
  check_country_vector(raw)
  u <- unique(as.character(raw))
  pos <- match(as.character(raw), u)
  iso3c <- wdj_to_iso3c(u, origin = origin, custom_match = custom_match)[pos]

  if (isTRUE(warn) && anyNA(iso3c)) {
    miss <- unique(as.character(raw)[is.na(iso3c)])
    miss <- miss[!is.na(miss)]
    if (length(miss)) {
      wdj_warn(c(
        "{length(miss)} value{?s} could not be matched to an ISO code:",
        "*" = "{.val {miss}}",
        "i" = "Use {.fn check_country_match} to inspect, or pass {.arg custom_match}."
      ))
    }
  }

  ui <- unique(iso3c)
  derived <- wdj_derive_from_iso3c(ui, add)[match(iso3c, ui), , drop = FALSE]
  # Drop any columns we are about to (re)create, then bind. When the caller
  # passed `add` themselves, replacing an existing `continent` is precisely what
  # they asked for and no warning is due. But `add` *defaults* to four columns,
  # so `standardize_country(d, country)` -- the call everyone makes, to get
  # iso3c -- silently destroyed a user's own `continent`, `region` or `iso2c`.
  # That is the same data loss warn_overwrite() exists for; the eleven other
  # column-adding verbs all report it. iso3c is excluded: replacing it is the
  # entire purpose of the function.
  if (isTRUE(warn) && add_defaulted) {
    unasked <- setdiff(intersect(names(derived), names(data)), "iso3c")
    if (length(unasked)) {
      wdj_warn(c(
        "Overwriting {length(unasked)} column{?s} you did not ask for:
         {.val {unasked}}.",
        "i" = "{.arg add} defaults to
               {.code c(\"iso3c\", \"iso2c\", \"continent\", \"region\")}.
               Pass {.code add = \"iso3c\"} to add only the code, or rename
               {cli::qty(length(unasked))}{?that column/those columns} to keep
               {?it/them}."
      ), class = "countryatlas_unasked_overwrite")
    }
  }
  data[intersect(names(derived), names(data))] <- NULL
  # Assign rather than bind_cols(as_tibble(data), derived), which stripped the
  # sf class. `derived` has one row per row of `data`, so this appends the same
  # columns in the same order; wdj_return_frame() then keeps sf as sf and
  # normalises everything else to a tibble, as before.
  for (nm in names(derived)) data[[nm]] <- derived[[nm]]
  wdj_return_frame(data)
}

# --- Names in other languages (tiers 4 and 5) ---------------------------------------
#
# The English regex left Allemagne, Deutschland, Alemania and the Russian,
# Chinese and Japanese names for Germany unmatched, and Elfenbeinkueste for
# Cote d'Ivoire. Two more tiers, tried only for what is still unmatched: an
# exact match against countrycode's German, Spanish, French and Italian names,
# then against every CLDR name, short name and variant in
# countrycode::codelist, both folded to a common form. Exact, not
# countrycode's language regexes: those are unanchored, and matched
# Somaliland to Somalia and "Indian Ocean Territories" to India, two names
# the English patterns deliberately leave alone.

# Latin letters with diacritics, to their base letters: the NFC half of
# accent-folding (strip_combining() handles NFD). Written as escapes: the
# package source is ASCII.
LATIN_FOLD_FROM <- paste0(
  "\u00c0\u00c1\u00c2\u00c3\u00c4\u00c5\u00c7\u00c8\u00c9\u00ca\u00cb\u00cc",
  "\u00cd\u00ce\u00cf\u00d1\u00d2\u00d3\u00d4\u00d5\u00d6\u00d9\u00da\u00db",
  "\u00dc\u00dd\u00e0\u00e1\u00e2\u00e3\u00e4\u00e5\u00e7\u00e8\u00e9\u00ea",
  "\u00eb\u00ec\u00ed\u00ee\u00ef\u00f1\u00f2\u00f3\u00f4\u00f5\u00f6\u00f9",
  "\u00fa\u00fb\u00fc\u00fd\u00ff\u0100\u0101\u0102\u0103\u0104\u0105\u0106",
  "\u0107\u0108\u0109\u010a\u010b\u010c\u010d\u010e\u010f\u0112\u0113\u0114",
  "\u0115\u0116\u0117\u0118\u0119\u011a\u011b\u011c\u011d\u011e\u011f\u0120",
  "\u0121\u0122\u0123\u0124\u0125\u0128\u0129\u012a\u012b\u012c\u012d\u012e",
  "\u012f\u0130\u0134\u0135\u0136\u0137\u0139\u013a\u013b\u013c\u013d\u013e",
  "\u0143\u0144\u0145\u0146\u0147\u0148\u014c\u014d\u014e\u014f\u0150\u0151",
  "\u0154\u0155\u0156\u0157\u0158\u0159\u015a\u015b\u015c\u015d\u015e\u015f",
  "\u0160\u0161\u0162\u0163\u0164\u0165\u0168\u0169\u016a\u016b\u016c\u016d",
  "\u016e\u016f\u0170\u0171\u0172\u0173\u0174\u0175\u0176\u0177\u0178\u0179",
  "\u017a\u017b\u017c\u017d\u017e\u0110\u0111\u0126\u0127\u0131\u0141\u0142",
  "\u00d8\u00f8\u0166\u0167\u013f\u0140\u00f0\u00d0")
LATIN_FOLD_TO <- paste0(
  "AAAAAACEEEEI",
  "IIINOOOOOUUU",
  "UYaaaaaaceee",
  "eiiiinooooou",
  "uuuyyAaAaAaC",
  "cCcCcCcDdEeE",
  "eEeEeEeGgGgG",
  "gGgHhIiIiIiI",
  "iIJjKkLlLlLl",
  "NnNnNnOoOoOo",
  "RrRrRrSsSsSs",
  "SsTtTtUuUuUu",
  "UuUuUuWwYyYZ",
  "zZzZzDdHhiLl",
  "OoTtLldD")
LATIN_FOLD_MULTI <- c("\u00c6" = "AE", "\u00e6" = "ae", "\u00df" = "ss",
                      "\u0152" = "OE", "\u0153" = "oe", "\u00de" = "TH",
                      "\u00fe" = "th", "\u0132" = "IJ", "\u0133" = "ij")

# The common form a name is compared in: no combining marks, Latin accents
# folded, lower case, German umlaut digraphs collapsed (so "Elfenbeinkueste"
# meets "Elfenbeinkuste"), no punctuation, single spaces. Lower-cased without
# tolower(), which follows the locale: in Turkish, "I" lower-cases to a
# dotless i and the same name stopped matching.
fold_name <- function(x) {
  x <- strip_combining(as.character(x))
  hi <- !is.na(x) & grepl("[^[:ascii:]]", x, perl = TRUE)
  if (any(hi)) {
    y <- chartr(LATIN_FOLD_FROM, LATIN_FOLD_TO, enc2utf8(x[hi]))
    lig <- grepl(paste0("[", paste(names(LATIN_FOLD_MULTI), collapse = ""), "]"),
                 y, perl = TRUE)
    for (k in names(LATIN_FOLD_MULTI)) {
      y[lig] <- gsub(k, LATIN_FOLD_MULTI[[k]], y[lig], fixed = TRUE)
    }
    x[hi] <- chartr(CASE_FOLD_UPPER, CASE_FOLD_LOWER, y)
  }
  x <- ascii_lower(x)
  x <- gsub("(?<=[aou])e", "", x, perl = TRUE)
  x <- gsub("\\p{P}+", "", x, perl = TRUE)
  gsub("\\s+", " ", trimws(x))
}

# Upper to lower case for the Greek and Cyrillic alphabets, by code point.
CASE_FOLD_UPPER <- paste0(intToUtf8(c(0x0391:0x03A1, 0x03A3:0x03A9), multiple = FALSE),
                          intToUtf8(c(0x0400:0x042F), multiple = FALSE))
CASE_FOLD_LOWER <- paste0(intToUtf8(c(0x03B1:0x03C1, 0x03C3:0x03C9), multiple = FALSE),
                          intToUtf8(c(0x0450:0x045F, 0x0430:0x044F), multiple = FALSE))

.name_index <- new.env(parent = emptyenv())

# Folded names from codelist columns, with the countries each names: one
# index per tier. A key that names more than one country names none, and a
# key of three letters or fewer is a code, not a name (the CLDR tables carry
# "FR" and "DE"), so it is left out.
name_index <- function(cols) {
  cl <- countrycode::codelist
  raw <- unlist(cl[cols], use.names = FALSE)
  iso <- rep(cl$iso3c, length(cols))
  keep <- !is.na(raw) & !is.na(iso)
  raw <- raw[keep]
  iso <- iso[keep]
  # Folded once per distinct string: most names repeat across the columns.
  u <- unique(raw)
  folded <- fold_name(u)
  uk <- unique(folded)
  kid <- match(folded, uk)[match(raw, u)]
  iid <- match(iso, cl$iso3c)
  once <- !duplicated(kid * (nrow(cl) + 1) + iid) & nzchar(uk[kid]) &
    !grepl("^[a-z]{1,3}$", uk[kid])
  key <- uk[kid[once]]
  iso <- iso[once]
  ambiguous <- unique(key[duplicated(key)])
  keep <- !key %in% ambiguous
  list(key = key[keep], iso3c = iso[keep], ambiguous = ambiguous)
}

# Every CLDR name, short name and variant in countrycode::codelist. Built once
# per session.
cldr_index <- function() {
  if (is.null(.name_index$cldr)) {
    cl <- countrycode::codelist
    .name_index$cldr <- name_index(
      grep("^cldr\\.(name|short|variant)\\.", names(cl), value = TRUE))
  }
  .name_index$cldr
}

language_index <- function(lang) {
  key <- paste0("lang_", lang)
  if (is.null(.name_index[[key]])) {
    .name_index[[key]] <- name_index(paste0("country.name.", lang))
  }
  .name_index[[key]]
}

# Tiers 4 and 5 for the names English matching left unresolved: the iso3c and
# how it was found ("name_de" ... "cldr"), or "ambiguous" for a name the
# index has for several countries.
match_name_tiers <- function(x) {
  out <- rep(NA_character_, length(x))
  method <- rep(NA_character_, length(x))
  key <- fold_name(x)
  for (lang in c("de", "es", "fr", "it")) {
    k <- is.na(out) & !is.na(x)
    if (!any(k)) break
    idx <- language_index(lang)
    r <- idx$iso3c[match(key[k], idx$key)]
    hit <- !is.na(r)
    out[k][hit] <- r[hit]
    method[k][hit] <- paste0("name_", lang)
  }
  k <- is.na(out) & !is.na(x)
  if (any(k)) {
    idx <- cldr_index()
    r <- idx$iso3c[match(key[k], idx$key)]
    hit <- !is.na(r)
    out[k][hit] <- r[hit]
    method[k][hit] <- "cldr"
    method[k][!hit & key[k] %in% idx$ambiguous] <- "ambiguous"
  }
  list(iso3c = out, method = method)
}
