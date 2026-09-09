# Curated overrides -------------------------------------------------------------

#' Curated country-name overrides (replaces the silent drop-list)
#'
#' A documented `custom_match` table for entities that map backends
#' ([ggplot2::map_data()] and Natural Earth) get wrong or leave without an ISO
#' code. Earlier versions of the package *deleted* these regions; now they are
#' *matched* instead, so they stop silently disappearing from maps.
#'
#' The table maps a country/region name (as spelled by the geometry backends) to
#' an ISO 3166-1 alpha-3 code. Pass the result as the `custom_match` argument to
#' [standardize_country()], [world_data()] and friends. Every downstream code
#' (`iso2c`, continent, region, flag, ...) is derived from this `iso3c`, so a
#' single override is enough.
#'
#' @param extra An optional named character vector of additional overrides
#'   (names are country/region names, values are `iso3c` codes). Merged on top
#'   of the built-in table, so you can extend or override it, e.g.
#'   `wdj_overrides(c(Somaliland = "SOM"))`.
#'
#' @section Accented names and locales:
#' Every name in this table is plain ASCII, and that is deliberate: ASCII
#' spellings match in any locale. Accented spellings (`"Curacao"` with a
#' cedilla, `"Saint Barthelemy"` with an acute) are matched natively by
#' [countrycode::countrycode()] *in a UTF-8 locale*, which is why they are not
#' listed here -- but in a non-UTF-8 locale (`LC_CTYPE=C`) they cannot be
#' compared reliably and resolve to `NA`.
#'
#' Accented spellings also come in two Unicode forms that look identical: the
#' accent can be one precomposed code point (NFC) or a base letter followed by
#' a combining mark (NFD, which macOS returns for filenames). Only NFC matches
#' [countrycode::countrycode()]'s tables, so a name that resolves to nothing is
#' retried with its combining marks stripped, which turns an NFD spelling into the
#' ASCII spelling that resolves anywhere. Only unresolved names are retried, so
#' this never changes a name that already matched.
#'
#' If your input may contain accented country names, run in a UTF-8 locale.
#' De-accenting with `iconv(x, to = "ASCII//TRANSLIT")` gives ASCII spellings
#' that resolve everywhere, but it is not an escape from the locale problem:
#' `//TRANSLIT` is itself locale-dependent, so under `LC_CTYPE=C` it returns
#' `NA` (or, given an explicit `from = "UTF-8"`, replaces each accent with `?`)
#' and nothing resolves. De-accent while still in a UTF-8 locale, or supply the
#' ASCII spellings directly.
#'
#' @return A named character vector suitable for `countrycode(custom_match=)`.
#' @export
#' @examples
#' # `country_overrides()` is the current name; `wdj_overrides()` warns.
#' country_overrides()
#' country_overrides(c(Somaliland = "SOM"))
wdj_overrides <- function(extra = NULL) {
  # Soft-deprecated in 2.0.0, and now a real warning: the cycle has run a full
  # release and an interactive-only note never reaches the scripts that are
  # actually still calling it. The note belongs to *this* name only -- it used to
  # live in the shared body, so it fired for country_overrides(), the
  # replacement it recommends, and for every public function that takes
  # `overrides = country_overrides()` as a default.
  wdj_warn(
    c("{.fn wdj_overrides} is deprecated; use {.fn country_overrides} instead.",
      "i" = "The two return the same table. {.fn wdj_overrides} is a holdover
             from the {.pkg worlddatajoin} name and will be removed."),
    class = "deprecatedWarning", .frequency = "once",
    .frequency_id = "wdj_overrides-deprecated"
  )
  build_overrides(extra)
}

# The override table itself, with no deprecation notice attached.
build_overrides <- function(extra = NULL) {
  base <- c(
    # map_data("world") spellings the legacy code used to drop.
    "Ascension Island" = "SHN",
    "Azores"           = "PRT",
    "Barbuda"          = "ATG",
    "Bonaire"          = "BES",
    "Canary Islands"   = "ESP",
    "Chagos Archipelago" = "IOT",
    "Grenadines"       = "VCT",
    "Heard Island"     = "HMD",
    "Kosovo"           = "XKX",
    "Madeira Islands"  = "PRT",
    "Micronesia"       = "FSM",
    "Saba"             = "BES",
    "Saint Martin"     = "MAF",
    "Siachen Glacier"  = "IND",
    "Sint Eustatius"   = "BES",
    "Virgin Islands"   = "VIR",
    # Common Natural Earth / WDI variants and other frequent offenders.
    # (Accented spellings such as "Curacao"/"Saint Barthelemy" are matched
    # natively by countrycode, so only the de-accented forms need overriding.)
    "Saint Barthelemy" = "BLM",
    "Curacao"          = "CUW",
    "Madeira"          = "PRT",
    "Federated States of Micronesia" = "FSM",
    "Micronesia, Fed. Sts." = "FSM",
    "Virgin Islands, U.S." = "VIR",
    "British Virgin Islands" = "VGB",
    "Channel Islands"  = "GBR",
    "Kosovo, Republic of" = "XKX"
  )
  if (!is.null(extra)) {
    nms <- names(extra)                    # capture before as.character()
    extra <- as.character(extra)
    # is.na() as well as !nzchar(): nzchar(NA) is TRUE, so an NA name walked
    # straight through this guard -- while wdj_to_iso3c() *does* reject one, so
    # the two validators disagreed about what a valid override table is. An NA
    # name also cannot be matched by anything, which is the silent-but-useless
    # entry both guards exist to prevent.
    if (is.null(nms) || any(is.na(nms) | !nzchar(nms))) {
      wdj_abort(c(
        "{.arg extra} must be a fully named character vector.",
        "i" = "Each name is the country string to recognise; each value is the
               {.field iso3c} code to map it to."
      ))
    }
    # The VALUES were unvalidated, and wdj_to_iso3c() then whitelists every
    # override value as a legitimate code -- so country_overrides(c(Freedonia =
    # "1")) put "1" in the iso3c column and every join keyed on it, with
    # nothing said. ISO 3166-1 alpha-3 is three uppercase letters; that also
    # admits the user-assigned range (XKX for Kosovo is in the base table
    # above), which is the only reason not to require membership of the known
    # set outright.
    # ^[A-Z][A-Z0-9]{2}$, not ^[A-Z]{3}$: the point is to refuse a value that is
    # plainly not a code -- "1", "fra", "FRANCE", NA -- because wdj_to_iso3c()
    # whitelists every override value as a legitimate code and every join then
    # keys on it. A user's own three-character code such as "ZZ1" is a
    # deliberate choice that behaves consistently wherever it lands, so it is
    # allowed; the package's own tests thread exactly that through geometry
    # matching.
    bad <- extra[!grepl("^[A-Z][A-Z0-9]{2}$", extra)]
    if (length(bad)) {
      wdj_abort(c(
        "Every value in {.arg extra} must be an {.field iso3c} code.",
        "x" = "Not {.val {unique(bad)}}.",
        "i" = "Three characters, starting with an uppercase letter: a real
               alpha-3 code, a user-assigned one like {.val XKX}, or your own
               such as {.val ZZ1}. Anything else would be whitelisted as a
               real code and then joined on."
      ))
    }
    if (anyNA(extra)) {
      wdj_abort(c(
        "{.arg extra} must not contain {.code NA}.",
        "i" = "An override maps a name TO a code; use a real code, or leave
               the name out and let it resolve to {.code NA} on its own."
      ))
    }
    base[nms] <- extra
  }
  base
}

#' @description
#' `country_overrides()` is the current name, as of the package's rename to
#' countryatlas. **`wdj_overrides()` is deprecated** and warns once per session;
#' it returns the same table and will be removed. The help page kept describing
#' it as "a backward-compatible alias" after the code had started warning.
#' @rdname wdj_overrides
#' @export
country_overrides <- function(extra = NULL) {
  build_overrides(extra)
}

# Small fallback table for ISO3c codes that `countrycode` does not classify
# (notably Kosovo's user-assigned XKX, which has no row at all in
# countrycode::codelist, so every destination derived from the code is NA).
wdj_code_fallback <- function() {
  tibble::tribble(
    ~iso3c,  ~iso2c, ~continent, ~region,                 ~country,  ~flag,
    "XKX",   "XK",   "Europe",   "Europe & Central Asia", "Kosovo",  "\U0001F1FD\U0001F1F0"
  )
}

# Columns apply_code_fallback() knows how to fill.
wdj_fallback_cols <- function() c("iso2c", "continent", "region", "country", "flag")

# Fill the fallback columns for codes countrycode leaves NA.
#
# `cols` exists because "region" means two different things. In a country frame
# it is countrycode's world region, which this table can fill; in
# map_data("world") -- which build_world_polygons() runs through here -- it is
# the basemap's *country name*, and filling that with "Europe" would be
# nonsense. Harmless so far only because map_data() never leaves it NA, which
# is not a property to rely on. Callers that hold such a frame name the columns
# they mean.
apply_code_fallback <- function(df, cols = wdj_fallback_cols()) {
  fb <- wdj_code_fallback()
  if (!"iso3c" %in% names(df)) return(df)
  cols <- intersect(cols, wdj_fallback_cols())
  for (i in seq_len(nrow(fb))) {
    hit <- !is.na(df$iso3c) & df$iso3c == fb$iso3c[i]
    if (!any(hit)) next
    for (col in cols) {
      if (col %in% names(df)) {
        miss <- hit & is.na(df[[col]])
        df[[col]][miss] <- fb[[col]][i]
      }
    }
  }
  df
}
