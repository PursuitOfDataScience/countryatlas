# Reporting: the last mile for the non-map audience -------------------------------
#
# A map is not always the deliverable. country_factsheet() answers "tell me
# about this country" and world_table() turns a map-ready frame into something
# printable, so the package's curated, reconciled data is useful to people who
# wanted a table all along.

#' Everything the package knows about one country
#'
#' A single-country summary drawn from the bundled reference data and, if you
#' ask, live indicators: codes, geography, groups, neighbours and any
#' dissolution history.
#'
#' @param x One country name or code.
#' @param indicators Optional indicator codes to fetch (named, as in
#'   [world_data()]). Needs the network. `NULL` (default) uses the bundled
#'   [world_snapshot] and stays offline.
#' @param origin How to read `x` (default `"country.name"`).
#'
#' @return A `countryatlas_factsheet` object -- a list of tibbles (`identity`,
#'   `geography`, `groups`, `neighbours`, `indicators`) that prints as a
#'   formatted block.
#'
#' @seealso [country_meta], [country_groups()], [neighbors()], [world_table()]
#' @export
#' @examples
#' country_factsheet("Brazil")
country_factsheet <- function(x, indicators = NULL, origin = "country.name") {
  if (length(x) != 1L) {
    wdj_abort("{.arg x} must be a single country; got {length(x)}.")
  }
  iso <- wdj_to_iso3c(x, origin = origin)
  if (is.na(iso)) {
    wdj_abort(c(
      "{.val {x}} did not resolve to a country.",
      "i" = "Try {.fn check_country_match} for close-name suggestions."
    ))
  }
  meta <- countryatlas::country_meta
  row <- meta[meta$iso3c == iso, ]

  identity_tbl <- tibble::tibble(
    field = c("iso3c", "iso2c", "country", "continent", "region", "capital",
              "currency", "flag", "tld"),
    value = c(iso,
              first_or_na(row$iso2c), first_or_na(row$country),
              first_or_na(row$continent), first_or_na(row$region),
              first_or_na(row$capital), first_or_na(row$currency),
              first_or_na(row$flag), first_or_na(row$tld))
  )
  # Round before stringifying: area_km2 carries full double precision and
  # printed as "8499361.01962319", which is noise rather than information.
  num_or_na <- function(v, digits) {
    if (!length(v) || is.na(v[1])) return(NA_character_)
    fmt_num(round(as.numeric(v[1]), digits))
  }
  geography_tbl <- tibble::tibble(
    field = c("area_km2", "centroid_lon", "centroid_lat", "landlocked"),
    value = c(num_or_na(row$area_km2, 0), num_or_na(row$centroid_lon, 2),
              num_or_na(row$centroid_lat, 2), first_or_na(row$landlocked))
  )
  gtbl <- countryatlas::country_groups_tbl
  groups_tbl <- tibble::tibble(group = sort(gtbl$group[gtbl$iso3c == iso]))

  nb <- tryCatch(neighbors(iso, origin = "iso3c"),
                 error = function(e) NULL)
  neighbours_tbl <- if (is.null(nb)) {
    tibble::tibble(iso3c = character(0), country = character(0))
  } else {
    tibble::tibble(iso3c = nb$neighbor, country = nb$neighbor_country)
  }
  # neighbors() works off the default 110m polygons, which have none at all for
  # the European microstates: they contribute no rows to country_borders(), so
  # the five of them come back with zero neighbours and their five neighbours
  # come back short. Printing a bare "Land neighbours (8)" for France states a
  # count that is simply wrong, so say what is missing where it is missing.
  attr(neighbours_tbl, "countryatlas_microstate_note") <-
    if (iso %in% WDJ_MICROSTATES) {
      TRUE
    } else if (iso %in% names(WDJ_MICROSTATE_NEIGHBOURS)) {
      setdiff(WDJ_MICROSTATE_NEIGHBOURS[[iso]], neighbours_tbl$iso3c)
    } else NULL

  ind <- if (is.null(indicators)) {
    snap <- countryatlas::world_snapshot$countries
    r <- snap[snap$iso3c == iso, ]
    num <- names(r)[vapply(r, is.numeric, logical(1))]
    if (!nrow(r) || !length(num)) {
      tibble::tibble(indicator = character(0), value = numeric(0))
    } else {
      tibble::tibble(indicator = num,
                     value = as.numeric(unlist(r[1, num, drop = TRUE])))
    }
  } else {
    d <- country_data(as.integer(format(Sys.Date(), "%Y")) - 1L,
                      indicator = indicators, latest = TRUE)
    r <- d[d$iso3c == iso, ]
    num <- setdiff(names(r)[vapply(r, is.numeric, logical(1))], "year")
    tibble::tibble(indicator = num,
                   value = if (nrow(r)) as.numeric(unlist(r[1, num, drop = TRUE]))
                           else rep(NA_real_, length(num)))
  }

  hist <- country_timeline(iso, origin = "iso3c")
  structure(
    # %||% only replaces NULL, and first_or_na() returns NA_character_ when the
    # code has no row in country_meta -- so this fallback was written and never
    # fired. Kosovo (XKX, which countrycode has no metadata row for) printed a
    # header of literally "NA (XKX)" while carrying real neighbours and history.
    list(iso3c = iso,
         name = na_fallback(first_or_na(row$country),
                            if (is.character(x)) x else iso),
         identity = identity_tbl, geography = geography_tbl,
         groups = groups_tbl, neighbours = neighbours_tbl,
         indicators = ind, timeline = hist),
    class = "countryatlas_factsheet"
  )
}

first_or_na <- function(x) if (length(x)) as.character(x)[1] else NA_character_

# %||% is for NULL; this is the NA-and-empty-string counterpart.
na_fallback <- function(x, alt) {
  if (length(x) != 1L || is.na(x) || !nzchar(trimws(x))) alt else x
}

#' @export
print.countryatlas_factsheet <- function(x, ...) {
  cli::cli_h2("{x$name} ({x$iso3c})")
  id <- x$identity
  keep <- !is.na(id$value) & nzchar(id$value)
  cli::cli_dl(stats::setNames(id$value[keep], id$field[keep]))
  g <- x$geography
  gk <- !is.na(g$value)
  if (any(gk)) {
    cli::cli_h3("Geography")
    cli::cli_dl(stats::setNames(g$value[gk], g$field[gk]))
  }
  if (nrow(x$groups)) {
    cli::cli_h3("Groups")
    cli::cli_text("{paste(x$groups$group, collapse = ', ')}")
  }
  note <- attr(x$neighbours, "countryatlas_microstate_note")
  if (nrow(x$neighbours)) {
    cli::cli_h3("Land neighbours ({nrow(x$neighbours)})")
    cli::cli_text("{paste(x$neighbours$country, collapse = ', ')}")
  } else if (isTRUE(note)) {
    cli::cli_h3("Land neighbours")
    cli::cli_text("None found.")
  }
  if (isTRUE(note)) {
    cli::cli_text(cli::col_grey(
      "Not 0: the 110m basemap has no polygon for this microstate. ",
      "Use country_borders(scale = \"medium\")."))
  } else if (length(note)) {
    miss <- suppressWarnings(convert_country(note, from = "iso3c",
                                             to = "country", warn = FALSE))
    miss[is.na(miss)] <- note[is.na(miss)]
    cli::cli_text(cli::col_grey(
      "Excludes {paste(miss, collapse = ', ')}: the 110m basemap has no ",
      "polygon for {cli::qty(length(miss))}{?it/them}. ",
      "Use country_borders(scale = \"medium\")."))
  }
  if (nrow(x$indicators)) {
    cli::cli_h3("Indicators")
    vals <- x$indicators
    cli::cli_dl(stats::setNames(fmt_num(signif(vals$value, 5)), vals$indicator))
  }
  preds <- x$timeline$predecessors[[1]]
  if (length(preds)) {
    cli::cli_h3("History")
    cli::cli_text("Succeeded: {paste(preds, collapse = ', ')}")
  }
  invisible(x)
}

#' A publication-ready table from a map-ready frame
#'
#' The tabular counterpart to [world_map()]: take the same curated frame and
#' produce a ranked, formatted table instead of a picture. Uses `gt` when it is
#' installed and a plain tibble otherwise, so it never becomes a hard dependency.
#'
#' @param data A country-level or map-ready frame.
#' @param value The column to rank on (unquoted). `NULL` keeps every numeric
#'   column, does not sort, and omits the `rank` column -- there is nothing to
#'   rank by, and `top_n` then takes an arbitrary slice (it warns when it does).
#' @param top_n How many rows (default `20`). `Inf` for all.
#' @param desc Sort descending (default `TRUE`).
#' @param columns Extra columns to keep, beyond `iso3c`, `country` and `value`.
#' @param engine `"gt"` (default, if installed) or `"tibble"`.
#' @param title,subtitle Optional table title and subtitle (`gt` only).
#'
#' @return A `gt` table, or a tibble when `gt` is unavailable or
#'   `engine = "tibble"`.
#' @seealso [rank_countries()], [country_factsheet()], [world_map()]
#' @export
#' @examples
#' world_table(countryatlas::world_snapshot$countries, gdp_per_capita,
#'             top_n = 5, engine = "tibble")
world_table <- function(data, value = NULL, top_n = 20, desc = TRUE,
                        columns = NULL, engine = c("gt", "tibble"),
                        title = NULL, subtitle = NULL) {
  engine <- rlang::arg_match(engine)
  check_bool(desc, "desc")
  value_q <- rlang::enquo(value)
  # Before as_tibble(), which is where vctrs raises "Column name `gdp` must
  # not be duplicated. Use `.name_repair` to specify repair" -- a message about
  # tibble's internals, reached before any of our own checks could run.
  check_dup_cols(data)
  # As in aggregate_regions(): `value` is a bare column and `columns` is
  # strings, so `columns = gdp` is the easy slip and gave base R's
  # "object 'gdp' not found".
  columns_expr <- substitute(columns)
  columns <- tryCatch(force(columns), error = function(e) {
    abort_bare_column(columns_expr, "columns", e)
  })
  df <- distinct_countries(tibble::as_tibble(sf_drop(data)))
  if (!is.null(columns)) check_cols(df, columns)

  if (!rlang::quo_is_null(value_q)) {
    val_name <- quo_arg_name(value_q, "value")
    check_cols(df, val_name)
    check_numeric_col(df, val_name)
    # Rows with no value cannot be ranked, so they go -- but if that empties
    # the table the caller gets a 0-row result from a frame that had rows in
    # it, and no way to tell "the column is empty" from "there is nothing to
    # report". gridded_cartogram() aborts on the same shape ("Every country
    # rounded to zero cells"); a table is recoverable, so say it and carry on.
    # A 0-row input still returns 0 rows in silence, as every panel helper does.
    had <- nrow(df)
    df <- df[!is.na(df[[val_name]]), ]
    if (had > 0L && !nrow(df)) {
      wdj_warn(c(
        "Every row was dropped: {.field {val_name}} is {.val NA} for all
         {had} countr{?y/ies}.",
        "i" = "The table is empty because the column is, not because there
               was nothing to rank."
      ), class = "countryatlas_all_missing")
    }
    df <- df[order(df[[val_name]], decreasing = desc), ]
    keep <- unique(c(intersect(c("iso3c", "country"), names(df)), val_name,
                     columns))
  } else {
    num <- names(df)[vapply(df, is.numeric, logical(1))]
    keep <- unique(c(intersect(c("iso3c", "country"), names(df)), num, columns))
  }
  df <- df[, keep, drop = FALSE]
  check_top_n(top_n)
  # A `rank` column is only honest when something was ranked. With no `value`
  # the frame is in whatever order it arrived (iso3c, for the bundled snapshot),
  # so head() takes an arbitrary slice and numbering it 1..n told the reader
  # these were the top n by something -- `world_table(snap, top_n = 5)` labelled
  # Afghanistan "rank 1" next to an empty GDP cell.
  ranked <- !rlang::quo_is_null(value_q)
  if (is.finite(top_n)) {
    if (!ranked && nrow(df) > top_n) {
      wdj_warn(c(
        "{.arg value} is {.code NULL}, so the table is not sorted.",
        "i" = "{.code top_n = {top_n}} therefore takes the first
               {top_n} row{?s} in the order {.arg data} arrived, not the top
               {top_n} of anything. Pass {.arg value} to rank."
      ), class = "countryatlas_unranked_top_n")
    }
    df <- utils::head(df, as.integer(top_n))
  }
  if (ranked) df <- tibble::add_column(df, rank = seq_len(nrow(df)), .before = 1)

  if (identical(engine, "tibble") || !has_pkg("gt")) {
    if (identical(engine, "gt")) {
      wdj_inform(
        c("i" = "Package {.pkg gt} not installed; returning a tibble."),
        .frequency = "once", .frequency_id = "world_table-no-gt"
      )
    }
    # A tibble has no header, so neither can be drawn. The gt path below
    # already refuses to drop a subtitle in silence ("subtitle needs a
    # title") -- the same objection applies here, and this path dropped both
    # without a word, returning a table the caller believed was titled.
    warn_engine_ignored(
      c(if (!is.null(title)) "title", if (!is.null(subtitle)) "subtitle"),
      "tibble",
      if (has_pkg("gt")) 'engine = "gt"' else 'install.packages("gt")')
    return(df)
  }
  tab <- gt::gt(df)
  # gt draws the subtitle inside the header block that a title opens, so a
  # subtitle on its own has nowhere to go -- it used to be dropped in silence.
  if (!is.null(subtitle) && is.null(title)) {
    wdj_abort(c(
      "{.arg subtitle} needs a {.arg title}.",
      "i" = "gt draws the subtitle inside the header block the title opens."
    ))
  }
  if (!is.null(title)) {
    check_string(title, "title")
    tab <- gt::tab_header(tab, title = title,
                          subtitle = subtitle %||% gt::md(""))
  }
  num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
  num_cols <- setdiff(num_cols, "rank")
  if (length(num_cols)) {
    tab <- gt::fmt_number(tab, columns = dplyr::all_of(num_cols),
                          n_sigfig = 4)
  }
  tab
}
