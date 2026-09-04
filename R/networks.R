# Flows, networks and relational data ---------------------------------------------
#
# flow_map() draws origin-destination arcs, which is the picture. What was
# missing is everything you do with an OD table *before* you draw it: put it in
# matrix form, describe it as a network, or show it as a grid of small maps
# instead of a plate of spaghetti. Bilateral data is the natural next thing to
# hang off the ISO spine, because reconciling two country columns instead of one
# is exactly twice the problem the package already solves.

#' An origin-destination table as a matrix
#'
#' Reshape a long bilateral table (trade, migration, flights, remittances) into
#' a square origin x destination matrix on the ISO spine, with both country
#' columns standardised. The natural input to a network analysis, and to
#' [country_weights()]`(type = "custom")` -- which is how "countries near each
#' other in trade space" becomes a spatial weights object.
#'
#' @param data An OD table.
#' @param from,to The origin and destination country columns (unquoted).
#' @param weight The flow column (unquoted). If omitted, every pair counts as 1.
#' @param origin How to read `from`/`to` (default `"country.name"`).
#' @param symmetric If `TRUE`, add the transpose so the matrix is undirected
#'   (default `FALSE`).
#' @param fill Value for pairs with no flow (default `0`).
#'
#' @return A square numeric matrix with `iso3c` row and column names. Rows are
#'   origins, columns destinations.
#'
#' @seealso [country_network()], [flow_map()], [country_weights()]
#' @export
#' @examples
#' od <- data.frame(
#'   from = c("China", "China", "Germany", "USA"),
#'   to   = c("USA", "Germany", "France", "Mexico"),
#'   value = c(500, 100, 80, 300)
#' )
#' flow_matrix(od, from, to, value)
flow_matrix <- function(data, from, to, weight = NULL,
                        origin = "country.name", symmetric = FALSE,
                        fill = 0) {
  from_name <- quo_arg_name(rlang::enquo(from), "from")
  to_name <- quo_arg_name(rlang::enquo(to), "to")
  weight_q <- rlang::enquo(weight)
  check_bool(symmetric, "symmetric")
  check_number(fill, "fill")
  check_cols(data, c(from_name, to_name))

  a <- wdj_to_iso3c(data[[from_name]], origin = origin)
  b <- wdj_to_iso3c(data[[to_name]], origin = origin)
  w <- if (rlang::quo_is_null(weight_q)) {
    rep(1, nrow(data))
  } else {
    wn <- quo_arg_name(weight_q, "weight")
    check_cols(data, wn)
    check_numeric_col(data, wn)
    data[[wn]]
  }
  # Two different reasons a row drops out, and they need different advice:
  # an endpoint that did not resolve is a country-matching problem, a
  # non-finite weight is a data problem. Reporting both as "an endpoint did not
  # resolve" sent the reader to check `origin` when the countries were fine --
  # and printed an empty bullet list, because there were no unresolved names to
  # name.
  bad_end <- is.na(a) | is.na(b)
  bad_w <- !bad_end & !is.finite(w)
  keep <- !bad_end & !bad_w
  if (any(bad_end)) {
    miss <- unique(c(as.character(data[[from_name]])[is.na(a)],
                     as.character(data[[to_name]])[is.na(b)]))
    miss <- miss[!is.na(miss)]
    wdj_warn(c(
      "{sum(bad_end)} flow{?s} dropped: an endpoint did not resolve to a country.",
      "*" = "{.val {utils::head(miss, 8)}}",
      "i" = "Check {.arg origin}; iso3c codes need {.code origin = 'iso3c'}."
    ))
  }
  if (any(bad_w)) {
    wdj_warn(c(
      "{sum(bad_w)} flow{?s} dropped: the weight is missing or infinite.",
      "i" = "Both endpoints resolved; it is {.field {rlang::as_name(weight_q)}}
             that is unusable."
    ))
  }
  a <- a[keep]; b <- b[keep]; w <- w[keep]
  if (!length(a)) {
    wdj_abort(c(
      "No usable flows left.",
      "x" = if (any(bad_w) && !any(bad_end))
        "Every row had a missing or infinite weight."
      else if (any(bad_end) && !any(bad_w))
        "No row had both endpoints resolve to a country."
      else "Every row was dropped for an unresolved endpoint or an unusable weight."
    ))
  }

  iso <- sort(unique(c(a, b)))
  m <- matrix(0, length(iso), length(iso), dimnames = list(iso, iso))
  seen <- matrix(FALSE, length(iso), length(iso), dimnames = list(iso, iso))
  # Accumulate rather than assign: a real OD table repeats a pair across
  # commodities, months or modes, and overwriting would silently keep only the
  # last row of each pair. Accumulate into zero, not into `fill`: `fill` is
  # documented as the value for pairs with *no* flow, but starting the matrix
  # at it added it to every observed pair too, so fill = -1 turned a flow of 10
  # into 9. Track which cells a flow actually reached and fill only the rest.
  for (i in seq_along(a)) {
    m[a[i], b[i]] <- m[a[i], b[i]] + w[i]
    seen[a[i], b[i]] <- TRUE
  }
  if (symmetric) {
    m <- m + t(m)
    diag(m) <- diag(m) / 2
    seen <- seen | t(seen)
  }
  if (!isTRUE(all.equal(fill, 0))) m[!seen] <- fill
  m
}

#' Describe an origin-destination table as a network
#'
#' Node- and edge-level summaries of a bilateral flow table: who sends, who
#' receives, who is central. No `igraph` required -- at country scale the dense
#' arithmetic is trivial.
#'
#' @inheritParams flow_matrix
#' @param top_n How many edges to return in the `edges` element (default `20`,
#'   largest first). `Inf` for all.
#'
#' @return A list of two tibbles:
#'   * `nodes` -- `iso3c`, `country`, `out_flow`, `in_flow`, `net_flow`,
#'     `out_degree`, `in_degree` and `strength_share` (the country's share of
#'     all flow, in or out).
#'   * `edges` -- `from`, `to`, `weight`, `share` and `reciprocity` (the
#'     opposite flow as a proportion of this one; `NA` where there is none).
#'
#' @seealso [flow_matrix()], [od_map()], [flow_map()]
#' @export
#' @examples
#' od <- data.frame(
#'   from = c("China", "China", "Germany", "USA", "Mexico"),
#'   to   = c("USA", "Germany", "France", "Mexico", "USA"),
#'   value = c(500, 100, 80, 300, 320)
#' )
#' country_network(od, from, to, value)
country_network <- function(data, from, to, weight = NULL,
                            origin = "country.name", top_n = 20) {
  # Checked before the matrix is built, not after the edge list is sorted: this
  # was the one verb here that did its whole job and *then* rejected an
  # argument it could have rejected immediately. `top_n` only trims the result,
  # so nothing about the check needs the computation.
  check_top_n(top_n)
  m <- flow_matrix(data, {{ from }}, {{ to }}, {{ weight }}, origin = origin)
  iso <- rownames(m)
  total <- sum(m)

  nodes <- tibble::tibble(
    iso3c = iso,
    country = suppressWarnings(convert_country(iso, from = "iso3c",
                                               to = "country", warn = FALSE)),
    # unname(): rowSums() on a named matrix carries the dimnames into the
    # column, so every value came back as a named length-1 vector.
    out_flow = unname(rowSums(m)), in_flow = unname(colSums(m)),
    net_flow = unname(rowSums(m) - colSums(m)),
    out_degree = unname(rowSums(m > 0)), in_degree = unname(colSums(m > 0)),
    strength_share = if (total > 0) unname((rowSums(m) + colSums(m)) / (2 * total)) else NA_real_
  )
  nodes <- dplyr::arrange(nodes, dplyr::desc(.data$strength_share))

  idx <- which(m > 0, arr.ind = TRUE)
  edges <- tibble::tibble(
    from = iso[idx[, 1]], to = iso[idx[, 2]],
    weight = m[idx],
    share = if (total > 0) m[idx] / total else NA_real_
  )
  back <- m[cbind(edges$to, edges$from)]
  edges$reciprocity <- ifelse(edges$weight > 0 & back > 0,
                              back / edges$weight, NA_real_)
  edges <- dplyr::arrange(edges, dplyr::desc(.data$weight))
  if (is.finite(top_n)) edges <- utils::head(edges, as.integer(top_n))
  list(nodes = nodes, edges = edges)
}

#' Origin-destination small multiples
#'
#' One small map per origin, each showing where that origin's flow goes. The
#' answer to the arc map's central problem: past a few dozen flows,
#' [flow_map()] is a plate of spaghetti and an OD map is legible.
#'
#' @inheritParams flow_matrix
#' @param origins Which origins to draw. A character vector of names or codes,
#'   or an integer giving how many of the largest to take (default `6`).
#' @param direction `"out"` (default; one panel per origin, showing
#'   destinations) or `"in"` (one panel per destination, showing origins).
#' @param ... Passed to [world_map()].
#'
#' @return A faceted `ggplot` object.
#' @seealso [flow_map()], [country_network()], [facet_map()]
#' @export
#' @examples
#' \donttest{
#' od <- data.frame(
#'   from = rep(c("China", "Germany", "USA"), each = 3),
#'   to   = c("USA", "Japan", "Brazil", "France", "Italy", "Poland",
#'            "Mexico", "Canada", "Japan"),
#'   value = c(500, 200, 90, 80, 70, 60, 300, 280, 120)
#' )
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   od_map(od, from, to, value, origins = 3)
#' }
#' }
od_map <- function(data, from, to, weight = NULL, origin = "country.name",
                   origins = 6, direction = c("out", "in"), ...) {
  direction <- rlang::arg_match(direction)
  m <- flow_matrix(data, {{ from }}, {{ to }}, {{ weight }}, origin = origin)
  if (identical(direction, "in")) m <- t(m)

  strength <- rowSums(m)
  named <- is.character(origins)
  panels <- if (named) {
    iso <- wdj_to_iso3c(origins, origin = origin)
    bad <- origins[is.na(iso)]
    if (length(bad)) {
      wdj_abort(c("{.arg origins} did not resolve: {.val {bad}}.",
                  "i" = "Check {.arg origin}."))
    }
    missing_iso <- setdiff(iso, rownames(m))
    if (length(missing_iso)) {
      wdj_abort("No flows for {.val {missing_iso}} in {.arg data}.")
    }
    iso
  } else {
    # hi: as.integer() below returns NA past 2^31-1, and min(NA, nrow(m))
    # then propagates it into seq_len().
    check_number(origins, "origins", lo = 1, hi = .Machine$integer.max)
    names(sort(strength, decreasing = TRUE))[seq_len(min(as.integer(origins),
                                                         nrow(m)))]
  }
  # A country can be in the matrix as a destination only, giving it zero
  # outflow and nothing to draw. Filtering the top-N list is just what "top N"
  # means, but dropping an origin the caller named by hand without saying so
  # left them counting panels to notice.
  dropped <- panels[strength[panels] <= 0]
  panels <- panels[strength[panels] > 0]
  if (named && length(dropped)) {
    wdj_warn(c(
      "Dropped {length(dropped)} named origin{?s} that send{?s/} no flow:
       {.val {dropped}}.",
      "i" = "They appear in {.arg data} only as destinations.
             {.code direction = \"in\"} maps what they receive instead."
    ))
  }
  if (!length(panels)) wdj_abort("None of the chosen origins send any flow.")

  lab <- suppressWarnings(convert_country(panels, from = "iso3c",
                                          to = "country", warn = FALSE))
  lab[is.na(lab)] <- panels[is.na(lab)]
  # Each panel carries every country the basemap knows, not only the ones in
  # the OD table. Without this, attach_geometry() left every unmatched country
  # with an NA panel and ggplot2 drew an extra, empty facet for them.
  world_iso <- unique(stats::na.omit(
    world_geometry("countries", geometry = "polygon")$iso3c))
  long <- dplyr::bind_rows(lapply(seq_along(panels), function(i) {
    row <- m[panels[i], ]
    flow <- unname(row[match(world_iso, names(row))])
    flow[!is.na(flow) & flow == 0] <- NA_real_
    tibble::tibble(iso3c = world_iso, .wdj_flow = flow,
                   .wdj_panel = factor(lab[i], levels = lab))
  }))

  mapped <- attach_geometry(long, geometry = "polygon")
  flow_sym <- rlang::sym(".wdj_flow")
  world_map(mapped, !!flow_sym,
            legend = if (identical(direction, "out")) "flow out" else "flow in",
            ...) +
    ggplot2::facet_wrap(ggplot2::vars(.data$.wdj_panel))
}
