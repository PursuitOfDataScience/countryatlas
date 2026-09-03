# Subnational geography ------------------------------------------------------------
#
# The package's whole design rests on one key, iso3c, and one row per country.
# Going below that is the largest scope change in the roadmap, so it is done
# narrowly and on the same principles: a documented key (ISO 3166-2, or NUTS in
# Europe), reconciliation as the value added, geometry delegated to somebody
# else's package, and nothing bundled.
#
# What this is NOT: a general GIS layer. There is no admin2, no bundled
# boundary data, and no attempt to harmonise administrative levels across
# countries -- a French departement and a US state are not the same kind of
# object and pretending otherwise would be the same category error the package
# exists to prevent at country level.

#' Standardise subnational region names to ISO 3166-2
#'
#' The subnational counterpart to [standardize_country()]: resolve messy region
#' names within a country to ISO 3166-2 codes, so subnational data can be joined
#' on a real key instead of on spelling.
#'
#' @param data A data frame with a region column.
#' @param region The region-name column (unquoted).
#' @param country The country column (unquoted), or a single country name/code
#'   applying to every row. ISO 3166-2 codes are only unique *within* a country,
#'   so this is required.
#' @param origin How to read `country` (default `"country.name"`).
#' @param warn Warn about regions that do not resolve (default `TRUE`).
#'
#' @return `data` with `iso3c` and `iso_3166_2` columns added. Unresolved
#'   regions get `NA`, never a guess.
#'
#' @section Coverage, stated plainly:
#' Resolution uses the optional `regions` package's crosswalks -- when the
#' installed version exposes a name-to-code pair this function recognises; it
#' says so once per session when it does not -- plus exact and
#' case-insensitive matching against ISO 3166-2 names. Coverage is good for
#' Europe (where NUTS and ISO 3166-2 are both well maintained) and patchy
#' elsewhere. This function will return `NA` rather than a plausible-looking
#' wrong code, and [audit_coverage()] on the result is the right next step.
#'
#' @seealso [subnational_map()], [nuts_geometry()], [standardize_country()]
#' @export
#' @examples
#' \donttest{
#' d <- data.frame(region = c("Bavaria", "Hesse", "Nowhere"), value = 1:3)
#' if (requireNamespace("regions", quietly = TRUE)) {
#'   standardize_subnational(d, region, country = "Germany")
#' }
#' }
standardize_subnational <- function(data, region, country, origin = "country.name",
                                    warn = TRUE) {
  check_bool(warn, "warn")
  reg_name <- quo_arg_name(rlang::enquo(region), "region")
  check_cols(data, reg_name)
  country_q <- rlang::enquo(country)

  # `country` may be a column or a single literal country, because subnational
  # data arrives both ways: one file per country, or one file with a country
  # column.
  iso <- if (rlang::quo_is_symbol(country_q) &&
             rlang::as_name(country_q) %in% names(data)) {
    wdj_to_iso3c(data[[rlang::as_name(country_q)]], origin = origin)
  } else {
    val <- rlang::eval_tidy(country_q, data)
    if (length(val) == 1L) rep(wdj_to_iso3c(val, origin = origin), nrow(data))
    else wdj_to_iso3c(val, origin = origin)
  }
  if (length(iso) != nrow(data)) {
    wdj_abort(c(
      "{.arg country} must be a column of {.arg data} or a single country.",
      "x" = "Got {length(iso)} values for {nrow(data)} rows."
    ))
  }
  warn_overwrite(data, c("iso3c", "iso_3166_2"))
  data$iso3c <- iso
  data$iso_3166_2 <- subnational_lookup(as.character(data[[reg_name]]), iso)

  if (isTRUE(warn)) {
    miss <- unique(as.character(data[[reg_name]])[is.na(data$iso_3166_2)])
    miss <- miss[!is.na(miss)]
    if (length(miss)) {
      wdj_warn(c(
        "{length(miss)} region{?s} did not resolve to an ISO 3166-2 code:",
        "*" = "{.val {utils::head(miss, 8)}}",
        "i" = "Coverage is best in Europe; see the section in
               {.help countryatlas::standardize_subnational}."
      ))
    }
  }
  data
}

# Resolve region names within a country to ISO 3166-2. Exact, then
# case/punctuation-insensitive, then the `regions` crosswalk where available.
subnational_lookup <- function(region, iso3c) {
  out <- rep(NA_character_, length(region))
  key <- function(z) ascii_lower(gsub("[^[:alnum:]]+", "", z))
  if (!has_pkg("regions")) {
    wdj_inform(
      c("i" = "Package {.pkg regions} not installed; only exact ISO 3166-2
              name matches will resolve."),
      .frequency = "once", .frequency_id = "subnational-no-regions"
    )
  }
  # A region name that *is already* an ISO 3166-2 code passes straight through.
  looks_code <- grepl("^[A-Z]{2}-[A-Z0-9]{1,3}$", region)
  out[looks_code] <- region[looks_code]

  if (has_pkg("regions")) {
    cw <- tryCatch(regions::nuts_lau_2019, error = function(e) NULL)
    if (is.null(cw)) cw <- tryCatch(regions::all_valid_nuts_codes,
                                    error = function(e) NULL)
    if (!is.null(cw) && is.data.frame(cw)) {
      nm_col <- intersect(c("geo_name", "name", "region_name"), names(cw))
      code_col <- intersect(c("code_2016", "geo", "code"), names(cw))
      if (length(nm_col) && length(code_col)) {
        lut <- stats::setNames(as.character(cw[[code_col[1]]]),
                               key(as.character(cw[[nm_col[1]]])))
        hit <- is.na(out)
        out[hit] <- unname(lut[key(region[hit])])
      } else {
        # regions 0.1.8 ships nuts_lau_2019 with lau_name_national /
        # lau_name_latin and all_valid_nuts_codes with no name column at all,
        # so neither exposes any of the names looked for above and the
        # crosswalk is skipped entirely. Silently: the caller was then told
        # only that their regions "did not resolve", with a hint about European
        # coverage -- which misdirects, because coverage was never consulted.
        # Say what actually happened. (The datasets that do pair names with
        # codes, nuts_changes and google_nuts_matchtable, key NUTS codes such
        # as DE2 rather than ISO 3166-2 codes such as DE-BY, so wiring them in
        # here would fill an iso_3166_2 column with a different code system --
        # against this function's promise of "never a guess".)
        wdj_inform(c(
          "!" = "The installed {.pkg regions} ({utils::packageVersion('regions')})
                 exposes no name-to-code crosswalk this function can use.",
          "i" = "Only exact and case-insensitive ISO 3166-2 name and code
                 matches will resolve; region names will not."
        ), .frequency = "once", .frequency_id = "subnational-no-crosswalk")
      }
    }
  }
  out
}

#' NUTS geometry for Europe
#'
#' European subnational boundaries from Eurostat's GISCO service via the
#' optional `giscoR` package. Nothing is bundled -- the geometry is downloaded
#' and cached by `giscoR` itself.
#'
#' @param level NUTS level: `0` (country), `1`, `2` or `3` (most detailed).
#' @param year NUTS vintage: `2003`, `2006`, `2010`, `2013`, `2016` or `2021`.
#'   Boundaries and codes are revised between vintages, which is why this is
#'   explicit -- joining 2013 data to 2021 geometry silently loses regions.
#' @param countries Optional `iso3c` vector to subset to.
#' @param resolution GISCO resolution: `"60"` (1:60 million, default), `"20"`,
#'   `"10"`, `"03"` or `"01"`.
#' @param projection Projection for the result (see [world_map()]), or `NULL`
#'   for unprojected.
#'
#' @return An `sf` frame with `nuts_id`, `iso3c`, `name`, `level` and geometry.
#' @seealso [standardize_subnational()], [subnational_map()]
#' @export
#' @examples
#' \dontrun{
#' nuts_geometry(level = 2, countries = c("DEU", "FRA"))
#' }
nuts_geometry <- function(level = 2, year = 2021, countries = NULL,
                          resolution = "60", projection = "equal_earth") {
  need_pkg(c("giscoR", "sf"), "for nuts_geometry()")
  check_number(level, "level", lo = 0, hi = 3)
  level <- as.integer(level)
  valid_years <- c(2003, 2006, 2010, 2013, 2016, 2021)
  if (!is.numeric(year) || length(year) != 1L || !year %in% valid_years) {
    wdj_abort(c(
      "{.arg year} must be a NUTS vintage.",
      "i" = "One of {.val {valid_years}}."
    ))
  }
  resolution <- rlang::arg_match0(as.character(resolution),
                                  c("60", "20", "10", "03", "01"), "resolution")
  g <- giscoR::gisco_get_nuts(nuts_level = level, year = as.character(year),
                              resolution = resolution)
  # giscoR answers a failed download with NULL rather than an error -- the same
  # shape as owidR's blank result, which fetch_owid() names explicitly and for
  # the same reason. Left alone this reached sf as "no applicable method for
  # 'st_as_sf' applied to an object of class NULL", which says nothing about
  # GISCO being unreachable and sends the reader looking at their arguments.
  if (is.null(g) || NROW(g) == 0L) {
    wdj_abort(c(
      "GISCO returned no NUTS geometry for level {level}, vintage {year}.",
      "i" = "{.pkg giscoR} reports a failed download as an empty result rather
             than an error, so this is usually connectivity or a resolution
             that vintage does not publish -- not a problem with the arguments."
    ), class = "countryatlas_no_nuts")
  }
  g <- sf::st_as_sf(g)
  names(g)[names(g) == "NUTS_ID"] <- "nuts_id"
  names(g)[names(g) == "NAME_LATN"] <- "name"
  names(g)[names(g) == "LEVL_CODE"] <- "level"
  # Without nuts_id, substr() below returns character(0), countrycode() passes
  # that through, and assigning a zero-length column to a populated frame fails
  # with base R's "replacement has 0 rows, data has 2" -- the same shape as a
  # World Bank response with no country key, and just as silent about the
  # actual cause.
  if (!"nuts_id" %in% names(g)) {
    got <- setdiff(names(g), attr(g, "sf_column"))
    wdj_abort(c(
      "The GISCO response carries no {.field NUTS_ID} column.",
      "x" = "Columns were {.val {got}}.",
      "i" = "That is a change in the provider's response shape, not a problem
             with the arguments."
    ), class = "countryatlas_bad_response")
  }
  g$iso3c <- suppressWarnings(
    countrycode::countrycode(substr(g$nuts_id, 1, 2), "eurostat", "iso3c",
                             warn = FALSE))
  if (!is.null(countries)) {
    iso <- wdj_to_iso3c(countries, origin = "iso3c")
    g <- g[!is.na(g$iso3c) & g$iso3c %in% iso, ]
    if (!nrow(g)) {
      wdj_abort(c("No NUTS regions for {.val {countries}}.",
                  "i" = "NUTS covers the EU, EFTA and candidate countries only."))
    }
  }
  keep <- intersect(c("nuts_id", "iso3c", "name", "level"), names(g))
  g <- g[, c(keep, attr(g, "sf_column"))]
  if (!is.null(projection)) g <- quietly_sf(sf::st_transform(g, wdj_crs(projection)))
  g
}

# Which values of `by` in the caller's data match no geometry row? The join in
# subnational_map() keeps the geometry and discards unmatched data, so a caller
# whose codes come from a different NUTS vintage loses those rows silently --
# and only a *total* wipe-out was reported, even though that error names the
# vintage problem exactly. Split out from the verb so it can be tested without
# a GISCO round-trip.
unmatched_keys <- function(data_keys, geom_keys) {
  k <- unique(as.character(data_keys))
  setdiff(k[!is.na(k)], as.character(geom_keys))
}
#' Map subnational data
#'
#' A choropleth below the country level, joining your data to NUTS geometry on
#' the region code. The subnational counterpart to [world_map()], scoped to
#' where a maintained code system and free geometry actually exist.
#'
#' @param data A frame with a NUTS/ISO 3166-2 code column.
#' @param fill The fill column (unquoted).
#' @param by The code column in `data` (default `"nuts_id"`; use
#'   `"iso_3166_2"` if you came through [standardize_subnational()]).
#' @param level,year,countries,resolution Passed to [nuts_geometry()].
#' @param ... Passed to [world_map()].
#'
#' @return A `ggplot` object.
#' @seealso [nuts_geometry()], [standardize_subnational()], [world_map()]
#' @export
#' @examples
#' \dontrun{
#' d <- data.frame(nuts_id = c("DE21", "DE22"), value = c(1, 2))
#' subnational_map(d, value, level = 2, countries = "DEU")
#' }
subnational_map <- function(data, fill, by = "nuts_id", level = 2, year = 2021,
                            countries = NULL, resolution = "60", ...) {
  fill_q <- rlang::enquo(fill)
  fill_name <- quo_arg_name(fill_q, "fill")
  check_string(by, "by")
  check_cols(data, c(by, fill_name))

  geom <- nuts_geometry(level = level, year = year, countries = countries,
                        resolution = resolution, projection = NULL)
  if (!by %in% names(geom)) {
    # Join on nuts_id whatever the caller's column is called.
    geom[[by]] <- geom$nuts_id
  }
  lost <- unmatched_keys(data[[by]], geom[[by]])
  if (length(lost)) {
    wdj_warn(c(
      # Count, noun and both verb agreements adjacent: cli keys {?...} to the
      # most recent numeric interpolation, and {.field {by}} carries one, so
      # sitting after it would re-key every agreement to 1. `{.arg data}` is
      # literal markup and interpolates nothing, so it is safe in between.
      "{length(lost)} value{?s} in {.arg data} {?matches/match} no geometry and
       {?is/are} dropped.",
      "*" = "{.field {by}}: {.val {utils::head(lost, 8)}}",
      "i" = "NUTS codes are revised between vintages, so codes from one
             {.arg year} do not all exist in another."
    ))
  }
  drop <- setdiff(intersect(names(geom), names(data)), by)
  geom <- geom[, setdiff(names(geom), drop), drop = FALSE]
  joined <- dplyr::left_join(geom, tibble::as_tibble(sf_drop(data)), by = by,
                             na_matches = "never")
  matched <- sum(!is.na(joined[[fill_name]]))
  if (!matched) {
    wdj_abort(c(
      "No rows of {.arg data} matched the geometry on {.val {by}}.",
      "i" = "Check the NUTS vintage: codes are revised between years, so 2013
             codes do not all exist in the 2021 geometry."
    ))
  }
  # coord_sf() over NUTS needs a European extent, not a world one, so let the
  # data set it rather than forcing a global projection.
  suppressMessages(
    world_map(joined, !!fill_q, ...) + ggplot2::coord_sf(datum = NA)
  )
}
