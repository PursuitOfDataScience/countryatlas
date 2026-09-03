# Provenance ---------------------------------------------------------------------
# A countryatlas map is the end of an analysis and the start of a question:
# which vintage, which geometry, which projection, which classification, how
# many countries? Every one of those is known at plot time and none of it used
# to travel with the output. world_map() now records them on the object; this is
# the reader.

#' What went into this map
#'
#' Report the provenance of a [world_map()] (or any plot the package's map verbs
#' produced): the package version, the geometry backend and projection, the
#' classification method and its breaks, the fill column, and how many countries
#' are shown versus missing. These are the questions a reviewer asks first, and
#' the answers are already known at plot time -- this just makes them readable.
#'
#' @param x A plot returned by any of the package's map verbs -- [world_map()],
#'   [bubble_map()], [spike_map()], [tile_map()], [flow_map()], [globe_map()],
#'   [bivariate_map()], [cartogram_map()], [dorling_map()],
#'   [gridded_cartogram()], [value_by_alpha_map()], [coverage_map()],
#'   [classify_compare()], [facet_map()] or [lisa_map()] -- or a map-ready data
#'   frame, for which the data-side facts are reported and the drawing-side ones
#'   are `NA`.
#' @param value For a data frame, the column whose coverage to report
#'   (unquoted). Ignored for a plot, which already knows its own fill.
#'
#' @return A one-row tibble of provenance fields, invisibly printed in a
#'   human-readable block. Fields: `countryatlas`, `fill`, `backend`,
#'   `projection`, `style`, `n_bins`, `na_style`, `n_countries`, `n_missing`,
#'   `n_total`, `uncertainty`, `disputes`, `dispute_policy`, `n_imputed`,
#'   `breaks`, `missing_iso3c` and `snapshot_year`.
#'
#'   The three counts are: `n_countries`, the countries actually drawn with a
#'   value; `n_missing`, those drawn without one; and `n_total`, the two added
#'   together -- every country the map covers. `n_countries` is the numerator,
#'   not the denominator, which its name does not say on its own.
#'
#' @section Putting it on the plot:
#' [world_map()]`(footnote = "auto")` prints the coverage line as a caption, and
#' `classification_report = TRUE` attaches the per-class counts. Together they
#' cover what a methods note needs:
#' ```r
#' p <- world_map(mapdf, gdp_per_capita, style = "quantile",
#'                footnote = "auto", classification_report = TRUE)
#' map_provenance(p)
#' attr(p, "countryatlas_classification")
#' ```
#'
#' @seealso [world_map()], [audit_coverage()], [coverage_map()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   p <- attach_geometry(snap, geometry = "polygon") |>
#'     world_map(gdp_per_capita, style = "quantile")
#'   map_provenance(p)
#' }
#' }
map_provenance <- function(x, value = NULL) {
  prov <- attr(x, "countryatlas_provenance")
  if (is.null(prov)) {
    if (!is.data.frame(x)) {
      wdj_abort(c(
        "{.arg x} carries no countryatlas provenance.",
        "i" = "Pass a plot from {.fn world_map} (or one of the other map verbs),
               or a map-ready data frame."
      ))
    }
    value_q <- rlang::enquo(value)
    if (rlang::quo_is_null(value_q)) {
      wdj_abort(c(
        "{.arg value} is required when {.arg x} is a data frame.",
        "i" = "Name the column whose coverage to report."
      ))
    }
    value_name <- quo_arg_name(value_q, "value")
    check_cols(x, value_name)
    prov <- list(fill = value_name, style = NA_character_,
                 projection = NA_character_,
                 backend = if (is_sf(x)) "sf" else if (has_map_geometry(x)) "polygon" else NA_character_,
                 n_bins = NA_integer_, na_style = NA_character_,
                 coverage = na_coverage(x, value_name), breaks = NULL)
  }

  out <- tibble::tibble(
    countryatlas = as.character(utils::packageVersion("countryatlas")),
    fill         = prov$fill %||% NA_character_,
    backend      = prov$backend %||% NA_character_,
    projection   = prov$projection %||% NA_character_,
    style        = prov$style %||% NA_character_,
    n_bins       = if (is.null(prov$n_bins)) NA_integer_ else as.integer(prov$n_bins),
    na_style     = prov$na_style %||% NA_character_,
    # `n_countries` is the *numerator* -- countries drawn with a value -- which
    # the name alone does not say, and a reader adding it to n_missing to get a
    # denominator has to work that out. Carry the denominator explicitly.
    n_countries  = prov$coverage$n_shown %||% NA_integer_,
    n_missing    = prov$coverage$n_missing %||% NA_integer_,
    n_total      = prov$coverage$n_total %||% NA_integer_,
    # These were recorded by the map verbs but never surfaced here, so the
    # fields existed and were unreadable -- which is the same as not having them.
    uncertainty  = prov$uncertainty %||% NA_character_,
    disputes     = prov$disputes %||% NA_character_,
    dispute_policy = prov$dispute_policy %||% NA_character_,
    n_imputed    = prov$n_imputed %||% 0L,
    snapshot_year = countryatlas::world_snapshot$year
  )
  out$breaks <- list(prov$breaks)
  out$missing_iso3c <- list(prov$coverage$missing_iso3c %||% character(0))
  structure(out, class = c("countryatlas_provenance", class(out)))
}

#' @export
print.countryatlas_provenance <- function(x, ...) {
  # Subsetting a tibble keeps its class, so `prov[, c("fill", "style")]` still
  # dispatches here with most columns gone. Reading them positionally then blew
  # up on `if (!is.na(NULL))` -- "argument is of length zero". Every field is
  # fetched through get1(), which tolerates absent as well as missing.
  get1 <- function(nm) {
    if (!nm %in% names(x)) return(NULL)
    v <- x[[nm]]
    if (length(v) < 1L) return(NULL)
    if (is.list(v)) return(v[[1]])
    if (is.na(v[1])) return(NULL)
    v[1]
  }
  fmt <- function(v) if (is.null(v)) "--" else as.character(v)

  cli::cli_h3("countryatlas map provenance")
  items <- c(
    "package"        = sprintf("countryatlas %s (snapshot %s)",
                               fmt(get1("countryatlas")), fmt(get1("snapshot_year"))),
    "fill"           = fmt(get1("fill")),
    "geometry"       = sprintf("%s backend, %s", fmt(get1("backend")),
                               fmt(get1("projection"))),
    "classification" = paste0(fmt(get1("style")),
                              if (!is.null(get1("n_bins")))
                                paste0(", ", get1("n_bins"), " bins") else ""),
    "missing data"   = fmt(get1("na_style")),
    "coverage"       = sprintf("%s %s shown, %s missing",
                               fmt(get1("n_countries")),
                               countries_noun(get1("n_countries")),
                               fmt(get1("n_missing")))
  )
  # Only show the rows this object actually carries, so a subset prints a
  # smaller block rather than a wall of "--".
  present <- c(
    "package" = !is.null(get1("countryatlas")),
    "fill" = !is.null(get1("fill")),
    "geometry" = !is.null(get1("backend")) || !is.null(get1("projection")),
    "classification" = !is.null(get1("style")),
    "missing data" = !is.null(get1("na_style")),
    "coverage" = !is.null(get1("n_countries"))
  )
  if (any(present)) cli::cli_dl(items[present])

  br <- get1("breaks")
  if (!is.null(br)) {
    cli::cli_text("{.strong breaks}: {paste(fmt_num(signif(br, 4)), collapse = ' | ')}")
  }
  unc <- get1("uncertainty"); disp <- get1("disputes"); nimp <- get1("n_imputed")
  notes <- c(
    if (!is.null(unc)) sprintf("uncertainty: %s (VSUP)", unc),
    if (!is.null(disp) && !identical(disp, "ignore"))
      sprintf("disputes: %s, convention %s", disp, fmt(get1("dispute_policy"))),
    if (!is.null(nimp) && isTRUE(as.numeric(nimp) > 0))
      sprintf("%s interpolated value(s)", nimp)
  )
  for (e in notes) cli::cli_text("{.strong note}: {e}")
  invisible(x)
}


# Attach provenance to a plot built outside world_map().
#
# world_map() records this inline, but ten other map verbs assemble their own
# ggplot and so carried nothing -- while map_provenance() documented itself as
# reading "any plot the package's map verbs produced". A partial implementation
# of a provenance feature is worse than none, because the gap is invisible until
# someone relies on it.
wdj_provenance <- function(p, data, fill, backend, projection = NA_character_,
                           style = NA_character_, extra = list()) {
  cov <- if (!is.null(fill) && fill %in% names(data)) {
    na_coverage(data, fill)
  } else {
    list(n_total = NA_integer_, n_shown = NA_integer_, n_missing = NA_integer_,
         missing_iso3c = character(0))
  }
  attr(p, "countryatlas_provenance") <- utils::modifyList(list(
    fill = fill %||% NA_character_, style = style, projection = projection,
    backend = backend, n_bins = NA_integer_, na_style = NA_character_,
    coverage = cov, breaks = NULL,
    disputes = "ignore", dispute_policy = dispute_policy(),
    uncertainty = NA_character_, n_imputed = imputed_count(data)
  ), extra)
  p
}
