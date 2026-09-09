# Standalone copy of the override mapping for the data-raw build, so the script
# does not depend on the package being installed. Keep in sync with
# R/overrides.R::wdj_overrides().

wdj_overrides_snapshot <- function() {
  c(
    "Ascension Island" = "SHN", "Azores" = "PRT", "Barbuda" = "ATG",
    "Bonaire" = "BES", "Canary Islands" = "ESP", "Chagos Archipelago" = "IOT",
    "Grenadines" = "VCT", "Heard Island" = "HMD", "Kosovo" = "XKX",
    "Madeira Islands" = "PRT", "Micronesia" = "FSM", "Saba" = "BES",
    "Saint Martin" = "MAF", "Siachen Glacier" = "IND", "Sint Eustatius" = "BES",
    "Virgin Islands" = "VIR", "Saint Barthelemy" = "BLM", "Curacao" = "CUW",
    "Madeira" = "PRT",
    "Federated States of Micronesia" = "FSM",
    "Micronesia, Fed. Sts." = "FSM",
    "Virgin Islands, U.S." = "VIR",
    "British Virgin Islands" = "VGB",
    "Channel Islands" = "GBR",
    "Kosovo, Republic of" = "XKX"
  )
}

# Standalone copy of the package's wdj_known_iso3c(), for the same reason: the
# data-raw scripts validated against `countryatlas:::wdj_known_iso3c()`, which
# needs the package installed and defeats this file's stated purpose. The list
# comes from countrycode, not from the package's own data, so a copy cannot go
# stale in any way that matters -- and the test in test-data-integrity.R pins
# it to the package's version anyway.
wdj_known_iso3c_snapshot <- function() {
  c(unique(stats::na.omit(countrycode::codelist$iso3c)), "XKX")
}

# Vectorised name -> iso3c using countrycode + the overrides.
#
# This deliberately mirrors wdj_to_iso3c()'s *first* pass only. The package
# adds a second pass that strips Unicode combining marks and retries, because a
# name in NFD ("Turkiye" as u + combining diaeresis) does not match
# countrycode's regexes. That does not matter here: this function is only ever
# handed ggplot2::map_data("world")$region, which is pure ASCII and in NFC by
# construction -- verified by the stopifnot() below, so the assumption cannot
# rot silently. If it is ever pointed at user data, use the package's
# wdj_to_iso3c() instead.
wdj_overrides_iso <- function(x) {
  cm <- wdj_overrides_snapshot()
  countrycode::countrycode(as.character(x), "country.name", "iso3c",
                           custom_match = cm, warn = FALSE)
}

local({
  # The basemap names this matcher is written for must stay ASCII-only, or the
  # single-pass match above starts dropping countries the package would resolve.
  if (requireNamespace("ggplot2", quietly = TRUE) &&
        requireNamespace("maps", quietly = TRUE)) {
    regions <- unique(ggplot2::map_data("world")$region)
    non_ascii <- regions[grepl("[^\001-\177]", regions, useBytes = TRUE)]
    if (length(non_ascii)) {
      stop("map_data(\"world\") now carries non-ASCII region names (",
           paste(utils::head(non_ascii, 5), collapse = ", "),
           "). wdj_overrides_iso() matches in one pass and will drop them; ",
           "use countryatlas:::wdj_to_iso3c() here instead.", call. = FALSE)
    }
  }
})
