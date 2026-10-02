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
#' @param x A plot returned by any of the package's map verbs -- [world_map()]
#'   (either engine), [bubble_map()], [spike_map()], [tile_map()],
#'   [flow_map()], [od_map()], [globe_map()], [bivariate_map()],
#'   [cartogram_map()], [dorling_map()], [gridded_cartogram()],
#'   [value_by_alpha_map()], [coverage_map()], [classify_compare()],
#'   [facet_map()], [lisa_map()], [subnational_map()] or
#'   [projection_compare()] -- or a map-ready data frame, for which the
#'   data-side facts are reported and the drawing-side ones are `NA`.
#'
#'   [tissot_map()] is the one map verb that carries no provenance: it draws
#'   distortion ellipses for a projection and takes no data of yours.
#' @param value For a data frame, the column whose coverage to report
#'   (unquoted). Ignored for a plot, which already knows its own fill.
#'
#' @return A one-row tibble of provenance fields, invisibly printed in a
#'   human-readable block. Fields: `countryatlas`, `fill`, `backend`,
#'   `projection`, `style`, `modified`, `n_bins`, `na_style`, `n_countries`,
#'   `n_missing`, `n_total`, `uncertainty`, `disputes`, `dispute_policy`,
#'   `worldview`, `n_imputed`, `breaks`, `missing_iso3c`, `snapshot_year`, and
#'   `sources`, the
#'   [source_info()] record of the fill column when the data carried one --
#'   which the print names: "World Bank WDI NY.GDP.PCAP.KD (constant 2015
#'   US$), release 2026-07, fetched 2026-10-01".
#'
#'   `projection` and `style` describe the plot as it is now, read from its
#'   coordinate system and fill scale: a map given `+ coord_sf(crs = 3035)`
#'   after the verb drew it reports `"custom"`, and `modified = TRUE` says the
#'   plot no longer matches what the verb recorded.
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
#' p <- attach_geometry(snap, geometry = "polygon") |>
#'   world_map(gdp_per_capita, style = "quantile")
#' map_provenance(p)
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
    check_cols(x, value_name, arg = "x")
    # n_imputed belongs here, not to the `%||% 0L` fallback below. The other
    # unset fields are drawing-side and default to NA, which claims nothing;
    # n_imputed defaults to 0, which claims that nothing was imputed -- so a
    # map-ready frame carrying two interpolated values reported zero of them,
    # in a function whose whole job is reporting provenance. It is a data-side
    # fact, and the frame is right here.
    prov <- list(fill = value_name, style = NA_character_,
                 projection = NA_character_,
                 backend = if (is_sf(x)) "sf" else if (has_map_geometry(x)) "polygon" else NA_character_,
                 n_bins = NA_integer_, na_style = NA_character_,
                 coverage = na_coverage(x, value_name), breaks = NULL,
                 n_imputed = imputed_count(x),
                 sources = fill_source_info(x, value_name))
  }

  # What the plot shows now, not only what the verb recorded: a coord or a
  # fill scale added afterwards changes the map, and the record used to say
  # otherwise (`+ coord_sf(crs = 3035)` still reported Equal Earth).
  modified <- FALSE
  if (inherits(x, "ggplot")) {
    now <- current_projection(x, prov$projection %||% NA_character_)
    if (!identical(now, prov$projection %||% NA_character_) &&
        !is.na(prov$projection %||% NA_character_)) {
      prov$projection <- now
      modified <- TRUE
    }
    kind_now <- current_scale_kind(x)
    kind_then <- style_scale_kind(prov$style %||% NA_character_)
    if (!is.na(kind_now) && !is.na(kind_then) && kind_now != kind_then) {
      prov$style <- paste0("modified (", kind_now, " scale)")
      prov$breaks <- NULL
      prov$n_bins <- NA_integer_
      modified <- TRUE
    }
  }
  out <- tibble::tibble(
    countryatlas = as.character(utils::packageVersion("countryatlas")),
    fill         = prov$fill %||% NA_character_,
    backend      = prov$backend %||% NA_character_,
    projection   = prov$projection %||% NA_character_,
    style        = prov$style %||% NA_character_,
    modified     = modified,
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
    worldview    = prov$worldview %||% NA_character_,
    n_imputed    = prov$n_imputed %||% 0L,
    snapshot_year = countryatlas::world_snapshot$year
  )
  out$breaks <- list(prov$breaks)
  out$missing_iso3c <- list(prov$coverage$missing_iso3c %||% character(0))
  out$sources <- list(prov$sources %||% empty_source_info())
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
  src <- get1("sources")
  if (is.data.frame(src) && nrow(src)) {
    for (i in seq_len(nrow(src))) {
      line <- source_line(src[i, ])
      cli::cli_text("{.strong data}: {line}")
    }
  }
  for (e in notes) cli::cli_text("{.strong note}: {e}")
  invisible(x)
}

# The source_info() rows that describe the fill column, or NULL.
fill_source_info <- function(data, fill) {
  info <- attr(data, "countryatlas_sources")
  if (is.null(info) || is.null(fill)) return(NULL)
  info <- info[info$column %in% fill, , drop = FALSE]
  if (nrow(info)) info else NULL
}


# Restate a derived map's provenance in the caller's terms.
#
# coverage_map(), classify_compare(), lisa_map() and od_map() all draw through
# world_map() with an *internal* column as the fill -- `.wdj_available`,
# `.wdj_class`, `.wdj_cluster`, `.wdj_flow` -- so the provenance world_map()
# writes describes that column and not the one the caller named.
# `.wdj_available` is the sharp case: it is an ifelse() over a logical test with
# both outcomes declared as factor levels, so it is *never* NA, and
# na_coverage() therefore recorded `n_missing = 0` and `n_shown = n_total` for
# every input -- flatly contradicting coverage_map()'s own caption, which is
# computed honestly from the caller's column. Two coverage claims on one object,
# in the verb whose whole purpose is honest missingness. Restate the fill name
# and recompute the coverage against the column the caller actually asked about.
#
# `shown` is for the verb whose drawn column is sparser than the caller's:
# lisa_map() colours only the countries the weights connect, so an island with
# a value is drawn as no-data. Recounting on the value alone put 189 countries
# in map_provenance() under a caption, computed from what was drawn, that said
# 142 -- the same two-claims contradiction, the other way round.
restate_provenance <- function(p, data, value_name, shown = NULL) {
  prov <- attr(p, "countryatlas_provenance")
  if (is.null(prov)) return(p)
  prov$fill <- value_name
  if (!is.null(value_name) && value_name %in% names(data)) {
    prov$coverage <- na_coverage(data, value_name, shown = shown)
  }
  prov$sources <- fill_source_info(data, value_name)
  prov$values <- alt_values(data, value_name)
  # An automatic caption was written from the internal column the verb drew;
  # rewrite it from the recount, or the caption and the provenance disagree.
  # Only the part the verb wrote: a caller-facing verb may have added its own
  # sentence (lisa_map() names its multiple-testing method), or replaced the
  # caption outright (coverage_map()).
  if (identical(prov$footnote, "auto") && !is.null(prov$caption)) {
    cap <- map_caption("auto", prov$coverage, prov$caption_notes, prov$sources,
                       lead = prov$caption_lead)
    cur <- gg_caption(p)
    if (!is.null(cap) && !is.null(cur) && grepl(prov$caption, cur, fixed = TRUE)) {
      p <- p + ggplot2::labs(caption = sub(prov$caption, cap, cur, fixed = TRUE))
      prov$caption <- cap
    }
  }
  attr(p, "countryatlas_provenance") <- prov
  p
}

# The caption a map verb adds. `footnote = "auto"` states the coverage, then
# the verb's own notes (small states drawn as points, a dispute convention,
# imputed values), then the source; a string is used as given, followed by
# the notes; `FALSE` or `NULL` adds nothing.
map_caption <- function(footnote, coverage, notes = NULL, sources = NULL,
                        lead = NULL, call = rlang::caller_env()) {
  if (is.null(footnote) || isFALSE(footnote)) return(NULL)
  auto <- identical(footnote, "auto") || isTRUE(footnote)
  line <- if (is.null(coverage) || is.na(coverage$n_total %||% NA)) {
    if (auto) NULL else resolve_footnote(footnote, coverage, call)
  } else {
    resolve_footnote(footnote, coverage, call)
  }
  src <- if (auto) source_caption(sources)
  out <- paste(stats::na.omit(c(lead, line, notes, src)), collapse = " ")
  if (nzchar(out)) out
}

# Attach provenance to a plot built outside world_map().
#
# world_map() records this inline, but ten other map verbs assemble their own
# ggplot and so carried nothing -- while map_provenance() documented itself as
# reading "any plot the package's map verbs produced". A partial implementation
# of a provenance feature is worse than none, because the gap is invisible until
# someone relies on it.
#
# `footnote` is the verb's own argument (see map_caption()); a caption the
# verb already set, such as gridded_cartogram()'s "1 cell = ...", leads it.
wdj_provenance <- function(p, data, fill, backend, projection = NA_character_,
                           style = NA_character_, extra = list(),
                           footnote = NULL, notes = NULL) {
  cov <- if (!is.null(fill) && fill %in% names(data)) {
    na_coverage(data, fill)
  } else {
    list(n_total = NA_integer_, n_shown = NA_integer_, n_missing = NA_integer_,
         missing_iso3c = character(0))
  }
  prov <- utils::modifyList(list(
    fill = fill %||% NA_character_, style = style, projection = projection,
    backend = backend, n_bins = NA_integer_, na_style = NA_character_,
    coverage = cov, breaks = NULL,
    disputes = "ignore", dispute_policy = dispute_policy(),
    uncertainty = NA_character_, n_imputed = imputed_count(data),
    sources = fill_source_info(data, fill), values = alt_values(data, fill)
  ), extra)
  p <- with_alt_text(p)
  if (!is.null(footnote) && !isFALSE(footnote)) {
    own <- gg_caption(p)
    lead <- if (length(own) && !is.na(own[1]) && nzchar(own[1])) own[1]
    cap <- map_caption(footnote, prov$coverage, notes, prov$sources, lead = lead)
    if (!is.null(cap)) p <- p + ggplot2::labs(caption = cap)
    prov$footnote <- if (identical(footnote, "auto") || isTRUE(footnote)) "auto" else "custom"
    prov$caption_notes <- notes
    prov$caption_lead <- lead
    prov$caption <- cap
  } else {
    prov$footnote <- "none"
  }
  attr(p, "countryatlas_provenance") <- prov
  p
}
