# Historical / dissolved entities ------------------------------------------------

# Alias -> canonical historical-entity name, shared by dissolve_country() and
# check_country_match(). Lowercased, whitespace-squished exact matches; kept
# deliberately small and unambiguous ("Sudan" alone is NOT here -- it is a
# current country -- only the explicitly historical spellings are).
historical_aliases <- function() {
  c(
    "ussr"                                    = "Soviet Union",
    "u.s.s.r."                                = "Soviet Union",
    "soviet union"                            = "Soviet Union",
    "the soviet union"                        = "Soviet Union",
    "union of soviet socialist republics"     = "Soviet Union",
    "yugoslavia"                              = "Yugoslavia",
    "sfr yugoslavia"                          = "Yugoslavia",
    "sfry"                                    = "Yugoslavia",
    "socialist federal republic of yugoslavia" = "Yugoslavia",
    "serbia and montenegro"                   = "Serbia and Montenegro",
    "fr yugoslavia"                           = "Serbia and Montenegro",
    "federal republic of yugoslavia"          = "Serbia and Montenegro",
    "czechoslovakia"                          = "Czechoslovakia",
    "czecho-slovakia"                         = "Czechoslovakia",
    "east germany"                            = "East Germany",
    "german democratic republic"              = "East Germany",
    "gdr"                                     = "East Germany",
    "netherlands antilles"                    = "Netherlands Antilles",
    "north yemen"                             = "North Yemen",
    "yemen arab republic"                     = "North Yemen",
    "south yemen"                             = "South Yemen",
    "people's democratic republic of yemen"   = "South Yemen",
    "democratic yemen"                        = "South Yemen",
    "sudan (former)"                          = "Sudan (former)",
    "sudan (pre-2011)"                        = "Sudan (former)",
    "former sudan"                            = "Sudan (former)",
    "united arab republic"                    = "United Arab Republic",
    "tanganyika"                              = "Tanganyika",
    "zanzibar"                                = "Zanzibar",
    "north vietnam"                           = "North Vietnam",
    "democratic republic of vietnam"          = "North Vietnam",
    "south vietnam"                           = "South Vietnam",
    "republic of vietnam"                     = "South Vietnam"
  )
}

# Normalise free-text names for alias lookup.
normalize_historical <- function(x) {
  tolower(gsub("\\s+", " ", trimws(as.character(x))))
}

#' Resolve dissolved entities to their successor states
#'
#' Historical data is full of countries that no longer exist -- the USSR,
#' Yugoslavia, Czechoslovakia -- and they poison naive joins twice over: most
#' are silently unmatched, and some are silently *mis*matched
#' (`countrycode` resolves `"USSR"` to Russia alone, so Soviet-era totals
#' quietly become Russian totals). `dissolve_country()` resolves a mixed
#' vector of historical and modern names against the curated
#' [historical_codes] crosswalk: dissolved entities expand to one row per
#' successor state (one-to-many, dated), while modern names pass through as
#' single rows -- so a whole messy column can be piped in unchanged.
#'
#' @param x A character vector of country names (historical and/or modern).
#' @param warn Whether to warn about names that match neither a historical
#'   entity nor a modern country (default `TRUE`).
#'
#' @return A tibble with one row per (input, successor) pair: `input` (as
#'   given), `historical` (canonical dissolved-entity name, `NA` for modern
#'   countries), `dissolved` (year the entity ceased to exist, `NA` for
#'   modern), `iso3c` and `country` (the successor state). Unmatched inputs
#'   yield one row with `iso3c = NA`.
#' @export
#' @seealso [historical_codes] for the crosswalk itself and the successor
#'   policy (e.g. Kosovo's inclusion in the Yugoslavia list);
#'   [check_country_match()], whose `historical` column flags these entities.
#' @examples
#' dissolve_country(c("USSR", "Czechoslovakia", "France"))
#' # One-to-many: Yugoslavia expands to its successor territories
#' dissolve_country("Yugoslavia")
dissolve_country <- function(x, warn = TRUE) {
  x <- as.character(x)
  empty <- tibble::tibble(input = character(), historical = character(),
                          dissolved = integer(), iso3c = character(),
                          country = character())
  if (!length(x)) return(empty)
  aliases <- historical_aliases()
  canon <- unname(aliases[normalize_historical(x)])

  out <- lapply(seq_along(x), function(i) {
    if (!is.na(canon[i])) {
      rows <- historical_codes[historical_codes$historical == canon[i], ]
      return(tibble::tibble(
        input = x[i],
        historical = rows$historical,
        dissolved = rows$dissolved,
        iso3c = rows$iso3c,
        country = rows$country
      ))
    }
    iso <- wdj_to_iso3c(x[i])
    tibble::tibble(
      input = x[i],
      historical = NA_character_,
      dissolved = NA_integer_,
      iso3c = iso,
      country = convert_country(iso, to = "country", from = "iso3c", warn = FALSE)
    )
  })
  out <- dplyr::bind_rows(out)

  if (isTRUE(warn)) {
    miss <- unique(out$input[is.na(out$iso3c)])
    if (length(miss)) {
      wdj_warn(c(
        "{length(miss)} name{?s} matched neither a historical entity nor a modern country:",
        "*" = "{.val {miss}}",
        "i" = "See {.fn check_country_match} for close-name suggestions."
      ))
    }
  }
  out
}
