# Source metadata that travels with the data -----------------------------------------
#
# A fetched column used to arrive as a bare number. Nothing in the frame said
# which provider it came from, in what unit, from which release or when it was
# fetched, so a map drawn from it could say none of that either, and two
# series in different units could be "compared" without a word. Every fetch
# now attaches a table describing its value columns, the verbs that reshape a
# frame carry it along, and the map verbs copy it into their provenance.

SOURCE_INFO_COLS <- c("column", "source", "indicator", "label", "unit",
                      "provider_updated", "fetched_at", "vintage", "licence",
                      "citation")

# One row per value column. Every field is character, NA where unknown.
source_info_rows <- function(column, source = NA, indicator = NA, label = NA,
                             unit = NA, provider_updated = NA, fetched_at = NA,
                             vintage = NA, licence = NA, citation = NA) {
  n <- length(column)
  f <- function(x) {
    x <- as.character(x)
    if (!length(x)) x <- NA_character_
    rep_len(x, n)
  }
  tibble::tibble(column = as.character(column), source = f(source),
                 indicator = f(indicator), label = f(label), unit = f(unit),
                 provider_updated = f(provider_updated),
                 fetched_at = f(fetched_at), vintage = f(vintage),
                 licence = f(licence), citation = f(citation))
}

empty_source_info <- function() source_info_rows(character())

# Attach `info` to `x`, keeping only the rows that describe a column `x` has
# and the last row for any column described twice.
set_source_info <- function(x, info) {
  if (is.null(info) || !nrow(info)) {
    attr(x, "countryatlas_sources") <- NULL
    return(x)
  }
  info <- info[info$column %in% names(x), , drop = FALSE]
  info <- info[!duplicated(info$column, fromLast = TRUE), , drop = FALSE]
  attr(x, "countryatlas_sources") <- if (nrow(info)) info else NULL
  x
}

# Combine the descriptions carried by several frames onto `x`.
carry_source_info <- function(x, ...) {
  infos <- lapply(list(...), function(f) attr(f, "countryatlas_sources"))
  infos <- Filter(Negate(is.null), infos)
  if (!length(infos)) return(x)
  set_source_info(x, dplyr::bind_rows(infos))
}

#' Where the numbers came from
#'
#' Every fetch -- [fetch_indicator()], [country_data()], [world_data()],
#' [add_indicator()], and the population, deflator and PPP series that
#' [per_capita()], [deflate()] and [to_ppp()] fetch for themselves -- records
#' which provider each value column came from, in what unit, from which
#' release and when. `source_info()` reads that record; `source_info<-` writes
#' one for your own data, so a map of it can say where it came from too.
#'
#' @param x A data frame.
#' @param value A data frame with a `column` column naming columns of `x`, and
#'   any of `source`, `indicator`, `label`, `unit`, `provider_updated`,
#'   `fetched_at`, `vintage`, `licence` and `citation`; or `NULL` to remove the
#'   record.
#'
#' @return `source_info()`: a tibble, one row per described column, with the
#'   ten fields above (no rows when nothing is recorded). `source_info<-`: `x`
#'   with the record attached.
#'
#' @section Which verbs keep it:
#' The record is an attribute. dplyr's `filter()`, `mutate()`, `arrange()`,
#' `select()` and `left_join()` (on the left-hand side) keep a data frame's
#' attributes, and `summarise()` drops them; the package's own verbs carry the
#' record explicitly, including [attach_geometry()], which builds its result
#' from the geometry. The map verbs copy it into [map_provenance()], whose
#' print method names the source of the fill, and `footnote = "auto"` adds a
#' one-line source note to the caption.
#'
#' @seealso [map_provenance()], [compare_sources()], [compare_vintages()]
#' @export
#' @examples
#' d <- data.frame(iso3c = c("FRA", "DEU"), rate = c(7.3, 3.1))
#' source_info(d) <- data.frame(column = "rate", source = "My survey",
#'                              unit = "%", fetched_at = "2026-10-01")
#' source_info(d)
source_info <- function(x) {
  info <- attr(x, "countryatlas_sources")
  if (is.null(info)) return(empty_source_info())
  info
}

#' @rdname source_info
#' @export
`source_info<-` <- function(x, value) {
  if (!is.data.frame(x)) {
    wdj_abort(c("{.arg x} must be a data frame.",
                "x" = "Got {.obj_type_friendly {x}}."))
  }
  if (is.null(value)) {
    attr(x, "countryatlas_sources") <- NULL
    return(x)
  }
  if (!is.data.frame(value) || !"column" %in% names(value)) {
    wdj_abort(c(
      "{.arg value} must be a data frame with a {.field column} column.",
      "i" = "One row per described column; see {.help countryatlas::source_info}."
    ))
  }
  extra <- setdiff(names(value), SOURCE_INFO_COLS)
  if (length(extra)) {
    wdj_abort(c(
      "{.arg value} has {cli::qty(length(extra))}{?a field/fields} the record
       does not hold: {.field {extra}}.",
      "i" = "The fields are {.field {SOURCE_INFO_COLS}}."
    ))
  }
  miss <- setdiff(as.character(value$column), names(x))
  if (length(miss)) {
    wdj_abort(c(
      "{.arg value} describes {cli::qty(length(miss))}{?a column/columns}
       {.arg x} does not have: {.field {miss}}."
    ))
  }
  args <- lapply(as.list(value), as.character)
  info <- do.call(source_info_rows, args)
  set_source_info(x, carry_existing(x, info))
}

# Keep what was already recorded for the columns `info` does not describe.
carry_existing <- function(x, info) {
  old <- attr(x, "countryatlas_sources")
  if (is.null(old)) return(info)
  dplyr::bind_rows(old[!old$column %in% info$column, , drop = FALSE], info)
}

# How a source is named in a caption and a provenance print.
source_display <- function(source) {
  known <- c(wdi = "World Bank WDI", owid = "Our World in Data", oecd = "OECD",
             imf = "IMF", ilo = "ILO", eurostat = "Eurostat",
             comtrade = "UN Comtrade")
  out <- unname(known[source])
  out[is.na(out)] <- source[is.na(out)]
  out
}

# "World Bank WDI NY.GDP.PCAP.KD (constant 2015 US$), release 2026-07,
# fetched 2026-10-01": one line per described column, for map_provenance().
source_line <- function(row) {
  bits <- paste(stats::na.omit(c(source_display(row$source), row$indicator)),
                collapse = " ")
  if (!is.na(row$unit)) bits <- paste0(bits, " (", row$unit, ")")
  extra <- c(if (!is.na(row$vintage)) paste("release", row$vintage),
             if (!is.na(row$fetched_at)) paste("fetched", row$fetched_at))
  paste(c(bits, extra), collapse = ", ")
}

# The caption's short form: "Source: World Bank WDI, release 2026-07."
source_caption <- function(info) {
  if (is.null(info) || !nrow(info)) return(NULL)
  who <- unique(vapply(seq_len(nrow(info)), function(i) {
    r <- info[i, ]
    paste(c(source_display(r$source),
            if (!is.na(r$vintage)) paste("release", r$vintage)), collapse = ", ")
  }, character(1)))
  who <- who[!is.na(who) & nzchar(who)]
  if (!length(who)) return(NULL)
  paste0("Source: ", paste(who, collapse = "; "), ".")
}

# A legend title from the fill's source record: its label, with the unit when
# the label does not already carry it, wrapped to fit a legend; the column
# name when there is no record. "GDP per capita (constant 2015 US$)" says what
# the colours measure where "gdp_per_capita" only names a column.
legend_title <- function(data, fill_name) {
  info <- fill_source_info(data, fill_name)
  if (is.null(info) || !nrow(info)) return(fill_name)
  lab <- info$label[1]
  unit <- info$unit[1]
  if (is.na(lab) || !nzchar(trimws(lab))) return(fill_name)
  if (!is.na(unit) && nzchar(trimws(unit)) && !grepl(unit, lab, fixed = TRUE)) {
    lab <- sprintf("%s (%s)", lab, unit)
  }
  paste(strwrap(lab, width = 24), collapse = "\n")
}
