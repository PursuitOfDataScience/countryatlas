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
#' Two things resolve, and it is worth being blunt about how little that is.
#'
#' A `region` value that is *already* an ISO 3166-2 code (`"DE-BY"`, `"US-CA"`)
#' passes through, provided its country prefix matches the country the row
#' gives -- these codes are unique only within a country, which is why
#' `country` is required. A mismatch is reported and left as `NA`.
#'
#' A region *name* resolves only through the optional `regions` package's
#' crosswalk, and only when the installed version exposes a name-to-code pair
#' this function recognises. As of `regions` 0.1.8 none of them do:
#' `nuts_lau_2019` offers `lau_name_national` / `lau_name_latin` and
#' `all_valid_nuts_codes` has no name column, so **no region name resolves at
#' all**, anywhere -- the function says so once per session. The package
#' carries no ISO 3166-2 name table of its own, deliberately: the datasets that
#' do pair names with codes key on NUTS codes (`DE2`) rather than ISO 3166-2
#' (`DE-BY`), and filling `iso_3166_2` from those would put a different code
#' system in the column.
#'
#' So: pass codes if you have them. If you have names, expect `NA` until
#' `regions` ships a usable crosswalk. This function returns `NA` rather than a
#' plausible-looking wrong code, and [audit_coverage()] on the result is the
#' right next step.
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
      "x" = "Got {length(iso)} values for {nrow(data)}
             {cli::qty(nrow(data))}row{?s}."
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
        # Not "coverage is best in Europe": there is no ISO 3166-2 name table
        # in the package and, as of `regions` 0.1.8, no usable crosswalk
        # either -- so a region *name* resolves nowhere, Europe included.
        # Pointing at Europe sent readers looking for a coverage gap that is
        # really a "names do not resolve at all" gap.
        "i" = "Only values that are already ISO 3166-2 codes resolve; region
               names need a crosswalk the installed {.pkg regions} does not
               provide. See the section in
               {.help countryatlas::standardize_subnational}."
      ))
    }
  }
  # Through wdj_return_frame() like its fourteen sibling column-adding verbs: a
  # data.frame in gave a data.frame out and a grouped tibble stayed grouped,
  # while standardize_country() next door normalises. This verb shipped in the
  # same release as the audit that fixed the other five.
  wdj_return_frame(data)
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
  # A region name that *is already* an ISO 3166-2 code passes straight through
  # -- but only when its country prefix matches the row's own country. ISO
  # 3166-2 codes are unique only *within* a country, which is exactly why
  # `country` is a required argument, and `iso3c` was accepted here and then
  # never read: standardize_subnational(region = "US-CA", country = "Germany")
  # returned iso3c = "DEU" with iso_3166_2 = "US-CA", a self-contradictory row,
  # silently. A mismatch resolves to NA, which is this function's documented
  # contract -- "NA rather than a plausible-looking wrong code".
  looks_code <- grepl("^[A-Z]{2}-[A-Z0-9]{1,3}$", region)
  prefix <- toupper(substr(region, 1L, 2L))
  expect <- suppressWarnings(convert_country(iso3c, "iso2c", from = "iso3c",
                                             warn = FALSE))
  # A row whose country did not resolve has nothing to check against, so the
  # code is taken at face value there rather than thrown away.
  belongs <- looks_code & (is.na(expect) | prefix == toupper(expect))
  out[belongs] <- region[belongs]
  wrong <- looks_code & !belongs
  if (any(wrong)) {
    wdj_warn(c(
      "{sum(wrong)} {.field region} value{?s} {?is/are} an ISO 3166-2 code for
       a different country than {.arg country} gives:",
      "*" = "{.val {utils::head(paste0(region[wrong], ' (country resolves to ',
             expect[wrong], ')'), 6)}}",
      "i" = "ISO 3166-2 codes are unique only within a country, so these are
             left as {.val {NA}}."
    ), class = "countryatlas_region_country_mismatch")
  }

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
      # `countries` is read as iso3c, so a country *name* resolves to nothing
      # and the coverage note was the only explanation offered -- sending the
      # reader off to check whether Germany is in the EU. Name the real
      # problem when another origin explains the input, the way
      # neighbors() and locate_country() do.
      hint <- wdj_origin_hint(countries, "iso3c")
      wdj_abort(c(
        "No NUTS regions for {.val {countries}}.",
        hint,
        "i" = if (is.null(hint)) {
          "NUTS covers the EU, EFTA and candidate countries only."
        } else {
          "NUTS also covers only the EU, EFTA and candidate countries."
        }
      ))
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
  # See abort_bare_column(): `by` takes a column name as a string.
  by_expr <- substitute(by)
  by <- tryCatch(force(by), error = function(e) {
    abort_bare_column(by_expr, "by", e)
  })
  check_string(by, "by")
  check_cols(data, c(by, fill_name))

  geom <- nuts_geometry(level = level, year = year, countries = countries,
                        resolution = resolution, projection = NULL)
  # Join on nuts_id whatever the caller's column is called -- unconditionally,
  # because the guard here used to be `if (!by %in% names(geom))`, which is
  # false exactly when the caller's column name collides with one of the
  # geometry's own (`name`, `iso3c`, `level`). `by = "name"` then joined the
  # caller's NUTS codes against the geometry's region *names* and matched
  # nothing, and `by = "iso3c"` silently joined at country granularity. `by` is
  # documented as "the code column in `data`", so the geometry side is always
  # nuts_id.
  geom[[by]] <- geom$nuts_id
  lost <- unmatched_keys(data[[by]], geom$nuts_id)
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
  # Joined on a reserved internal key rather than on `by` itself. The geometry
  # side had `geom[[by]] <- geom$nuts_id` assigned unconditionally, so
  # by = "iso3c", "name" or "level" -- all real NUTS-geometry columns --
  # overwrote that column with NUTS codes and carried it into the returned
  # plot's data. The assignment has to be unconditional (see above); doing it
  # under a name of our own is what keeps it from costing a column.
  geom[[".wdj_nuts_key"]] <- geom$nuts_id
  dat <- tibble::as_tibble(sf_drop(data))
  dat[[".wdj_nuts_key"]] <- as.character(dat[[by]])
  drop <- setdiff(intersect(names(geom), names(dat)), ".wdj_nuts_key")
  geom <- geom[, setdiff(names(geom), drop), drop = FALSE]
  joined <- dplyr::left_join(geom, dat, by = ".wdj_nuts_key",
                             na_matches = "never")
  joined[[".wdj_nuts_key"]] <- NULL
  # Counted on the join KEY, not on the fill value: sum(!is.na(fill)) called a
  # panel whose indicator is entirely NA -- a real thing to map, and one this
  # package draws with an na.value and says so in the caption -- "no rows
  # matched the geometry", sending the reader off to check NUTS vintages for a
  # mismatch that never happened.
  matched <- sum(!is.na(dat[[".wdj_nuts_key"]]) &
                   dat[[".wdj_nuts_key"]] %in% geom[[".wdj_nuts_key"]])
  if (!matched) {
    wdj_abort(c(
      "No rows of {.arg data} matched the geometry on {.val {by}}.",
      "i" = "Check the NUTS vintage: codes are revised between years, so 2013
             codes do not all exist in the 2021 geometry."
    ))
  }
  # coord_sf() over NUTS needs a European extent, not a world one, so let the
  # data set it rather than forcing a global projection.
  #
  # Which is exactly why `projection` cannot be honoured here: the coord below
  # replaces whatever world_map() built, and suppressMessages() swallowed
  # ggplot2's note about the replacement, so the argument looked accepted and
  # changed nothing. warn_projection_ignored() exists for this.
  dots <- rlang::list2(...)
  if (!is.null(dots$projection)) {
    warn_projection_ignored(dots$projection, where = "{.fn subnational_map}")
    dots$projection <- NULL
  }
  suppressMessages(
    rlang::inject(world_map(joined, !!fill_q, !!!dots)) +
      ggplot2::coord_sf(datum = NA)
  )
}
