# Country-name standardisation --------------------------------------------------

# Convert raw country identifiers to iso3c, applying overrides and (optionally)
# warning about misses. `origin` is any countrycode origin scheme
# ("country.name", "iso2c", "iso3c", "wb", ...).
wdj_to_iso3c <- function(x, origin = "country.name", custom_match = country_overrides(),
                         call = rlang::caller_env(), arg = "origin") {
  check_string(origin, arg)
  # `origin` was checked and the override table was not, though every value in
  # it lands in the iso3c column -- and the iso3c branch below whitelists those
  # values as valid by construction, so nothing downstream rejects them either.
  # custom_match = c(Freedonia = 1) therefore put "1" in iso3c and every join
  # after it keyed on that. The table is a name -> iso3c map; require the shape.
  if (length(custom_match) &&
      (!is.character(custom_match) || is.null(names(custom_match)))) {
    wdj_abort(c(
      "{.arg custom_match} must be a named character vector.",
      "x" = if (!is.character(custom_match)) {
        "Got {.cls {class(custom_match)[1]}}."
      } else {
        "Got a character vector with no names."
      },
      "i" = "Names are the spellings to override, values are {.field iso3c}
             codes -- the shape {.fn country_overrides} returns."
    ))
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
    out <- ascii_upper(trimws(x))
    # Still let overrides repair known-bad spellings.
    if (length(custom_match)) {
      hit <- match(x, names(custom_match))
      out[!is.na(hit)] <- unname(custom_match[hit[!is.na(hit)]])
    }
    valid <- c(wdj_known_iso3c(), unname(custom_match))
    out[!is.na(out) & !(out %in% valid)] <- NA_character_
    return(out)
  }
  tryCatch(
    suppressWarnings(
      countrycode::countrycode(
        x,
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
    lo <- tolower(shown)
    vl <- tolower(ok)
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
    lo <- tolower(origin)
    vl <- tolower(valid)
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

# Derive a set of attributes from iso3c. `add` may name any countrycode
# destination; the common shortcuts (iso2c, continent, region) are handled
# explicitly with fallbacks for codes countrycode does not know.
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
  iso3c <- wdj_to_iso3c(raw, origin = origin, custom_match = custom_match)

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

  derived <- wdj_derive_from_iso3c(iso3c, add)
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
               your columns to keep them."
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
