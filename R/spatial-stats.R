# Spatial weights and the statistics built on them --------------------------------
#
# morans_i() shipped in 2.0.0 with one hard-wired weight scheme: land-border
# contiguity, row-standardised. That is a defensible scheme and a consequential
# default -- an island has no land border, so Japan, the UK, Australia,
# Indonesia, Madagascar, New Zealand, the Philippines, Iceland and every small
# island state carried no weight and left the analysis. 2.1.0 made that visible
# (n_excluded), 3.0.0 made it fixable with country_weights("knn"), and 4.0.0
# makes knn (k = 5) the default, so a "global" statistic covers the globe. The
# same object drives local statistics, Geary's C, Getis-Ord and the spatial
# lag.
#
# The distinctive one is type = "custom": adjacency does not have to be
# geographic. "Countries near each other in *trade* space" is often the relevant
# neighbourhood for an economic question, and it goes through the same API.

# `k`, `cutoff_km`, `w` and `scale` each belong to exactly one scheme, and the
# other three ignored them without a word. The costly one is
# country_weights("knn", w = my_matrix): the caller's own adjacency was
# discarded and nearest-neighbour weights returned instead, so the result looks
# entirely reasonable and is not what was asked for. Same treatment the
# projection/recenter/scale notices give an inert argument elsewhere. Each
# argument is compared against its default rather than using missing(), so
# passing a default explicitly stays quiet.
warn_weights_args_ignored <- function(type, k, cutoff_km, w, scale) {
  used <- switch(type, knn = "k", distance = "cutoff_km",
                 contiguity = "scale", custom = "w")
  given <- c(
    if (!identical(as.numeric(k), 5)) "k",
    if (!is.null(cutoff_km)) "cutoff_km",
    if (!is.null(w)) "w",
    if (!identical(scale, "small")) "scale"
  )
  ignored <- setdiff(given, used)
  if (!length(ignored)) return(invisible(NULL))
  wdj_warn(c(
    "{.code type = \"{type}\"} ignores {cli::qty(length(ignored))}{?this
     argument/these arguments}: {.arg {ignored}}.",
    "i" = "This scheme is built from {.arg {used}}."
  ), class = "countryatlas_weights_args_ignored")
  invisible(NULL)
}

#' Spatial weights on the country spine
#'
#' Build a reusable neighbour-weights object for [morans_i()], [local_morans()],
#' [gearys_c()], [getis_ord()] and [spatial_lag()]. Four schemes, three of which
#' give every country at least one neighbour -- which land-border contiguity,
#' the default before 4.0.0, cannot do for an island.
#'
#' @param type
#'   * `"knn"` (default) -- the `k` nearest countries by great-circle centroid
#'     distance. Every country gets exactly `k` neighbours, islands included.
#'     Needs nothing but the bundled [country_meta]. It is also what every
#'     statistic here uses when `weights` is `NULL`.
#'   * `"contiguity"` -- shared land border, from [country_borders()]. Needs
#'     `sf`. Islands get no neighbours; see [morans_i()]'s note.
#'   * `"distance"` -- every country within `cutoff_km`. Needs nothing.
#'   * `"custom"` -- your own adjacency (see `w`), which is how non-geographic
#'     neighbourhoods -- trade volume, migration flows, colonial or language
#'     ties -- go through the same API.
#' @param countries Optional `iso3c` vector to restrict the weights to. Defaults
#'   to every country the chosen backend knows about.
#' @param k Neighbours per country for `type = "knn"` (default `5`).
#' @param cutoff_km Distance band for `type = "distance"`, in kilometres.
#' @param w For `type = "custom"`: either a square named matrix, or a long data
#'   frame with columns `iso3c`, `neighbor` and optionally `weight`.
#' @param style `"W"` (default) row-standardises so each row sums to 1, the
#'   usual choice for Moran's I; `"B"` leaves the weights binary/raw.
#' @param scale Natural Earth resolution for `type = "contiguity"`.
#'
#' @return A `countryatlas_weights` object: the weights matrix plus the scheme
#'   that built it. Inspect it by printing; `as.matrix()` gives the matrix.
#'
#' @section Choosing a scheme:
#' Contiguity encodes "shares a border", which is the right relation for
#' spillovers that cross borders by land. It is the wrong relation for a global
#' question, because it silently deletes the islands. `"knn"` is the safe
#' default for world-scale work: every country participates, and `k` controls how
#' local the neighbourhood is. `"distance"` is right when the process has a real
#' length scale. `"custom"` is right when geography is not the relevant space at
#' all.
#'
#' @seealso [morans_i()], [local_morans()], [lisa_map()], [spatial_lag()]
#' @export
#' @examples
#' # k-nearest neighbours: no sf needed, and islands are included
#' w <- country_weights("knn", k = 4)
#' w
#'
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' morans_i(snap, gdp_per_capita, weights = country_weights("knn", k = 5),
#'          n_perm = 99)
#' }
country_weights <- function(type = c("knn", "contiguity", "distance", "custom"),
                            countries = NULL, k = 5, cutoff_km = NULL,
                            w = NULL, style = c("W", "B"), scale = "small") {
  type <- rlang::arg_match(type)
  style <- rlang::arg_match(style)
  warn_weights_args_ignored(type, k, cutoff_km, w, scale)
  if (!is.null(countries)) {
    # wdj_to_iso3c() rather than as.character(): case and padding were taken
    # verbatim, so country_weights("knn", countries = c("usa","fra")) warned
    # that two countries "have no bundled centroid" and then refused for want
    # of centroids -- blaming the centroid table for a key that never matched.
    raw_countries <- unique(stats::na.omit(as.character(countries)))
    countries <- unique(stats::na.omit(
      suppressWarnings(wdj_to_iso3c(raw_countries, origin = "iso3c"))))
    if (!length(countries)) {
      wdj_abort(c(
        "{.arg countries} has no usable codes.",
        "i" = if (length(raw_countries))
          "None of {.val {utils::head(raw_countries, 4)}} resolved to an ISO
           3166-1 alpha-3 code; {.fn standardize_country} normalises names."
      ))
    }
  }

  built <- switch(
    type,
    contiguity = weights_contiguity(countries, scale),
    knn        = weights_knn(countries, k),
    distance   = weights_distance(countries, cutoff_km),
    custom     = weights_custom(w, countries)
  )
  m <- built$m
  if (identical(style, "W")) {
    rs <- rowSums(m)
    # A row of zeros is a country with no neighbours under this scheme; leave it
    # at zero rather than dividing by it, and let the consumers report it.
    rs[rs == 0] <- 1
    m <- m / rs
  }
  # A graph with no edges builds happily and then fails wherever it is used, as
  # "Not enough connected countries with data" -- an error about the *data*,
  # raised far from the cutoff or matrix that actually caused it. Say it here,
  # where the argument that produced it is still in view. `distance` with a
  # small cutoff_km and an all-zero custom matrix are the two ways in.
  if (isTRUE(built$n_links == 0)) {
    why <- switch(
      type,
      distance = cli::format_inline(
        "no two centroids are within {.val {cutoff_km}} km of each other"),
      custom = "the supplied matrix has no non-zero entries",
      knn = "no country has a usable centroid",
      "the scheme found no adjacent pairs")
    wdj_warn(c(
      "These weights link no countries at all: {why}.",
      "i" = "Every statistic built on them will refuse to run. Widen
             {.arg cutoff_km}, or use {.code country_weights(\"knn\", k = 5)}."
    ), class = "countryatlas_empty_weights")
  }
  structure(
    list(m = m, iso3c = rownames(m), type = type, style = style,
         k = if (type == "knn") as.integer(k) else NA_integer_,
         cutoff_km = if (type == "distance") cutoff_km else NA_real_,
         scale = if (type == "contiguity") scale else NA_character_,
         n_links = built$n_links,
         isolated = rownames(m)[built$degree == 0]),
    class = "countryatlas_weights"
  )
}

#' @export
print.countryatlas_weights <- function(x, ...) {
  cli::cli_h3("countryatlas spatial weights")
  detail <- switch(
    x$type,
    contiguity = sprintf("shared land border (Natural Earth %s)", x$scale),
    knn = sprintf("%d nearest centroids", x$k),
    distance = sprintf("centroids within %s km", fmt_num(x$cutoff_km)),
    custom = "user-supplied adjacency"
  )
  cli::cli_dl(c(
    "scheme"    = "{x$type} -- {detail}",
    "style"     = "{if (identical(x$style, 'W')) 'row-standardised (W)' else 'binary (B)'}",
    "countries" = "{length(x$iso3c)}",
    "links"     = "{x$n_links}",
    "isolated"  = "{length(x$isolated)}{if (length(x$isolated)) paste0(' (', paste(utils::head(x$isolated, 6), collapse = ', '), if (length(x$isolated) > 6) ', ...' else '', ')') else ''}"
  ))
  invisible(x)
}

#' @export
as.matrix.countryatlas_weights <- function(x, ...) x$m

# --- builders -------------------------------------------------------------------

weights_contiguity <- function(countries, scale) {
  need_pkg("sf", 'for country_weights(type = "contiguity")')
  b <- country_borders(scale = scale)
  iso <- countries %||% sort(unique(c(b$iso3c_a, b$iso3c_b)))
  b <- b[b$iso3c_a %in% iso & b$iso3c_b %in% iso, ]
  m <- matrix(0, length(iso), length(iso), dimnames = list(iso, iso))
  if (nrow(b)) {
    m[cbind(b$iso3c_a, b$iso3c_b)] <- 1
    m[cbind(b$iso3c_b, b$iso3c_a)] <- 1
  }
  list(m = m, n_links = nrow(b), degree = rowSums(m))
}

# Centroid table for the distance-based schemes. country_meta carries no
# centroid for a handful of small territories (see ?distance_between), so say
# which countries dropped out rather than returning a quietly smaller matrix.
weights_centroids <- function(countries, call = rlang::caller_env()) {
  meta <- countryatlas::country_meta[, c("iso3c", "centroid_lon", "centroid_lat")]
  meta <- meta[!is.na(meta$centroid_lon) & !is.na(meta$centroid_lat), ]
  if (!is.null(countries)) {
    dropped <- setdiff(countries, meta$iso3c)
    if (length(dropped)) {
      wdj_warn(c(
        "{length(dropped)} countr{?y/ies} ha{?s/ve} no bundled centroid and
         cannot be weighted by distance.",
        "*" = "{.val {dropped}}",
        "i" = "See {.help countryatlas::distance_between} for which territories
               the bundled metadata omits."
      ))
    }
    meta <- meta[meta$iso3c %in% countries, ]
  }
  meta <- meta[order(meta$iso3c), ]
  if (nrow(meta) < 2L) {
    wdj_abort("Need at least 2 countries with centroids to build weights.",
              call = call)
  }
  meta
}

# Pairwise great-circle distance (km) between every centroid pair.
weights_distance_matrix <- function(meta) {
  n <- nrow(meta)
  i <- rep(seq_len(n), each = n)
  j <- rep(seq_len(n), times = n)
  d <- haversine_km(meta$centroid_lon[i], meta$centroid_lat[i],
                    meta$centroid_lon[j], meta$centroid_lat[j])
  matrix(d, n, n, dimnames = list(meta$iso3c, meta$iso3c))
}

weights_knn <- function(countries, k, call = rlang::caller_env()) {
  check_number(k, "k", lo = 1, hi = .Machine$integer.max, call = call)
  k <- as.integer(k)
  meta <- weights_centroids(countries, call = call)
  n <- nrow(meta)
  if (k >= n) {
    wdj_abort(c(
      "{.arg k} must be smaller than the number of countries.",
      "x" = "Got k = {k} with {n} {cli::qty(n)}countr{?y/ies}."
    ), call = call)
  }
  d <- weights_distance_matrix(meta)
  diag(d) <- Inf                       # a country is not its own neighbour
  m <- matrix(0, n, n, dimnames = dimnames(d))
  for (i in seq_len(n)) m[i, order(d[i, ])[seq_len(k)]] <- 1
  # k-nearest is asymmetric by construction (A may be in B's top k without B
  # being in A's); that is standard and intended, so do not symmetrise.
  list(m = m, n_links = sum(m > 0), degree = rowSums(m))
}

weights_distance <- function(countries, cutoff_km, call = rlang::caller_env()) {
  if (is.null(cutoff_km)) {
    wdj_abort('{.arg cutoff_km} is required for {.code type = "distance"}.',
              call = call)
  }
  check_number(cutoff_km, "cutoff_km", lo = 0, call = call)
  meta <- weights_centroids(countries, call = call)
  d <- weights_distance_matrix(meta)
  m <- (d <= cutoff_km) * 1
  diag(m) <- 0
  list(m = m, n_links = sum(m > 0) / 2, degree = rowSums(m))
}

weights_custom <- function(w, countries, call = rlang::caller_env()) {
  if (is.null(w)) {
    wdj_abort('{.arg w} is required for {.code type = "custom"}.', call = call)
  }
  if (is.matrix(w)) {
    if (is.null(rownames(w)) || is.null(colnames(w))) {
      wdj_abort("A custom weights matrix must have {.field iso3c} row and column names.",
                call = call)
    }
    if (!identical(rownames(w), colnames(w))) {
      wdj_abort("A custom weights matrix must have identical row and column names.",
                call = call)
    }
    # Neither of these was checked, and each leaked a bare base-R error from
    # somewhere downstream: a character matrix reached rowSums() as "'x' must be
    # numeric", and an NA entry was accepted here only to die later as
    # "subscript out of bounds" -- naming neither the argument nor the cause.
    if (!is.numeric(w) && !is.logical(w)) {
      wdj_abort(c(
        "A custom weights matrix must be numeric, not {.cls {class(w[1])}}.",
        "i" = "Weights are link strengths: {.val {0}}/{.val {1}} for a plain
               adjacency, or any non-negative number."
      ), call = call)
    }
    if (anyNA(w)) {
      wdj_abort(c(
        "A custom weights matrix must not contain {.val NA}.",
        "x" = "{sum(is.na(w))} entr{?y/ies} {?is/are} missing.",
        "i" = "Use {.val {0}} for {.emph not a neighbour}."
      ), call = call)
    }
    # The type message just above promises "any non-negative number", and
    # nothing enforced it. Row standardisation divides by the row sum, so a
    # single negative weight silently moved Moran's I from 0.714 to 0.497 --
    # and an all-negative matrix cancelled to exactly the all-positive answer,
    # discarding the caller's signs without a word. gini(), theil() and the
    # global G all refuse a negative input for the same reason; a negative
    # link strength is not a weaker link, it is not a link at all.
    #
    # Infinity was worse than silent: it normalised to NaN and the verb then
    # reported "not enough connected countries with data", diagnosing
    # connectivity when the cause was the weight.
    if (any(!is.finite(w))) {
      wdj_abort(c(
        "A custom weights matrix must be finite.",
        "x" = "{sum(!is.finite(w))} entr{?y/ies} {?is/are} infinite.",
        "i" = "Use a large finite number if one link really should dominate."
      ), call = call)
    }
    if (any(w < 0)) {
      wdj_abort(c(
        "A custom weights matrix must be non-negative.",
        "x" = "{sum(w < 0)} entr{?y/ies} {?is/are} negative.",
        "i" = "Use {.val {0}} for {.emph not a neighbour}."
      ), call = call)
    }
    m <- w
    storage.mode(m) <- "double"
    # Case and padding normalised, as country_weights(countries = ) is: codes
    # were taken verbatim, so a matrix named in lowercase matched no country
    # in any data frame and every statistic built on it refused with "Not
    # enough connected countries ... Try a scheme that connects islands":
    # a key problem diagnosed as a connectivity one. Unknown codes are kept:
    # a user-assigned code (see country_overrides()) is legitimate here.
    rn <- norm_weight_code(rownames(w))
    if (anyDuplicated(rn)) {
      wdj_abort(c(
        "A custom weights matrix names the same country twice.",
        "x" = "{.val {unique(rn[duplicated(rn)])}} after ignoring case and
               surrounding spaces.",
        "i" = "Give each country one row and one column."
      ), call = call)
    }
    dimnames(m) <- list(rn, rn)
  } else if (is.data.frame(w)) {
    check_cols(w, c("iso3c", "neighbor"), arg = "w", call = call)
    val <- if ("weight" %in% names(w)) w$weight else rep(1, nrow(w))
    if (!is.numeric(val)) {
      wdj_abort("{.field weight} must be numeric.", call = call)
    }
    # An NA endpoint reached the matrix assignment below as base R's "NAs are
    # not allowed in subscripted assignments"; an NA weight was accepted and
    # turned every statistic built on it into a silent NA.
    if (anyNA(w$iso3c) || anyNA(w$neighbor)) {
      bad <- sum(is.na(w$iso3c) | is.na(w$neighbor))
      wdj_abort(c(
        "{.field iso3c} and {.field neighbor} must not contain {.val NA}.",
        "x" = "{bad} row{?s} {?is/are} missing an endpoint.",
        "i" = "A link needs both ends; drop those rows."
      ), call = call)
    }
    if (anyNA(val)) {
      wdj_abort(c(
        "{.field weight} must not contain {.val NA}.",
        "x" = "{sum(is.na(val))} weight{?s} {?is/are} missing.",
        "i" = "Use {.val {0}} for {.emph not a neighbour}, or drop the row."
      ), call = call)
    }
    # The same two checks as the matrix branch above, for the same reasons.
    if (any(!is.finite(val))) {
      wdj_abort(c(
        "{.field weight} must be finite.",
        "x" = "{sum(!is.finite(val))} weight{?s} {?is/are} infinite.",
        "i" = "Use a large finite number if one link really should dominate."
      ), call = call)
    }
    if (any(val < 0)) {
      wdj_abort(c(
        "{.field weight} must be non-negative.",
        "x" = "{sum(val < 0)} weight{?s} {?is/are} negative.",
        "i" = "Use {.val {0}} for {.emph not a neighbour}, or drop the row."
      ), call = call)
    }
    # Normalised like the matrix branch above, for the same reason.
    from <- norm_weight_code(w$iso3c)
    to <- norm_weight_code(w$neighbor)
    # The matrix assignment below keeps the *last* weight for a repeated
    # link, so two rows for FRA -> DEU (weights 1 and 5) came out as 5 with
    # the 1 discarded unannounced. The matrix branch refuses a country named
    # twice; a link named twice is the same ambiguity -- summed trade flows
    # and a stray duplicate need different answers, and only the caller
    # knows which this is.
    dup <- duplicated(data.frame(from, to))
    if (any(dup)) {
      pairs <- unique(paste(from[dup], "->", to[dup]))
      wdj_abort(c(
        "{.arg w} lists {length(pairs)} link{?s} more than once:",
        "*" = "{.val {utils::head(pairs, 6)}}",
        "i" = "Give each link one row: sum repeated flows first, e.g. with
               {.code dplyr::summarise(w, weight = sum(weight),
               .by = c(iso3c, neighbor))}."
      ), class = "countryatlas_duplicate_links", call = call)
    }
    iso <- sort(unique(c(from, to)))
    m <- matrix(0, length(iso), length(iso), dimnames = list(iso, iso))
    m[cbind(from, to)] <- val
  } else {
    wdj_abort(c(
      "{.arg w} must be a named square matrix or a long data frame.",
      "x" = "Got {.cls {class(w)[1]}}.",
      "i" = "A long frame needs {.field iso3c}, {.field neighbor} and optionally
             {.field weight}."
    ), call = call)
  }
  if (!is.null(countries)) {
    keep <- intersect(rownames(m), countries)
    if (length(keep) < 2L) {
      wdj_abort("Fewer than 2 of {.arg countries} appear in {.arg w}.",
                call = call)
    }
    m <- m[keep, keep, drop = FALSE]
  }
  diag(m) <- 0
  list(m = m, n_links = sum(m > 0), degree = rowSums(m))
}

# A custom weights code, the way wdj_to_iso3c(origin = "iso3c") reads one
# (ASCII upper case, Unicode padding trimmed) but without its whitelist, so a
# user-assigned code survives.
norm_weight_code <- function(x) {
  ascii_upper(trimws(as.character(x), whitespace = "[\\h\\v]"))
}

# --- align a weights object to a data frame -------------------------------------
#
# Moran's I, Geary's C and the Getis-Ord/local variants all divide by the
# cross-sectional variance, so a constant column makes them 0/0. They returned
# NaN -- and getis_ord's z-score Inf -- with nothing said, which for a
# statistic is worse than an error: it reads like a computed result. Say why,
# and hand back NA rather than NaN so downstream code sees "missing".
zero_variance <- function(x, val_name, call = rlang::caller_env()) {
  if (length(x) < 2L) return(FALSE)
  if (!isTRUE(stats::sd(x) == 0)) return(FALSE)
  wdj_warn(c(
    "{.field {val_name}} is the same in all {length(x)} countries used, so the
     statistic is undefined.",
    "i" = "These measures compare how a value varies between neighbours; with
           no variation there is nothing to compare. Returning {.val NA}."
  ), class = "countryatlas_zero_variance", call = call)
  TRUE
}

# Every statistic below needs the same thing: one value per country, the weights
# subset to the countries that have both a value and a row in the matrix, and a
# report of who fell out. Doing it once keeps morans_i()'s exclusion accounting
# consistent across all of them.
align_weights <- function(data, val_name, weights, scale = NULL,
                          call = rlang::caller_env()) {
  if (!"iso3c" %in% names(data)) {
    wdj_abort("{.arg data} must contain an {.field iso3c} column.", call = call)
  }
  check_cols(data, val_name, call = call)
  check_numeric_col(data, val_name, call = call)
  # distinct_countries(), not a bare distinct(): these statistics are a
  # cross-section, and a panel arriving here was silently reduced to whichever
  # row came first in the frame. Moran's I on the same panel came back 0.47 or
  # 0.29 depending only on row order, with nothing said. The shared helper
  # takes the earliest year deterministically and warns that it had to choose.
  df <- distinct_countries(tibble::as_tibble(sf_drop(data)))
  # blank_key(), not is.na(): a blank code identifies no country either, and
  # it reached the weights lookup as the "country" "" -- which no weights
  # matrix names, so it was reported in `excluded` and counted in
  # `n_excluded` as though an island had been dropped.
  df <- df[!blank_key(df$iso3c) & is.finite(df[[val_name]]), ]

  # knn (k = 5) by default: contiguity silently deletes every island from a
  # "global" statistic. `scale` survives only for morans_i()'s deprecated
  # argument, which asked for the old contiguity default at a resolution.
  if (is.null(weights)) {
    weights <- if (is.null(scale)) country_weights("knn", k = 5) else
      country_weights("contiguity", scale = scale)
  }
  if (!inherits(weights, "countryatlas_weights")) {
    wdj_abort(c(
      "{.arg weights} must come from {.fn country_weights}.",
      "x" = "Got {.cls {class(weights)[1]}}."
    ), call = call)
  }
  m <- weights$m
  # Keep only countries that have a value *and* at least one neighbour among the
  # countries that also have a value -- a neighbourless row contributes nothing
  # and would divide by zero on re-standardisation.
  keep <- intersect(rownames(m), df$iso3c)
  # Nothing in common *as written*, while the same codes would match once case
  # and padding are normalised, is a key problem rather than a connectivity
  # one: lowercase codes in `data` matched nothing, and the abort below then
  # advised "a scheme that connects islands". Only that case is claimed here;
  # an island absent from the contiguity weights is exactly what the advice
  # below is for.
  if (!length(keep) && nrow(df) &&
      length(intersect(rownames(m), norm_weight_code(df$iso3c)))) {
    wdj_abort(c(
      "No country in {.arg data} matches {.arg weights} as written.",
      "x" = "{.arg data} has {.val {utils::head(unique(df$iso3c), 3)}};
             {.arg weights} has {.val {utils::head(rownames(m), 3)}}.",
      "i" = "They differ in case or surrounding spaces;
             {.fn standardize_country} normalises both."
    ), call = call, class = "countryatlas_weights_no_overlap")
  }
  # Iterated to a fixed point, not pruned once. Dropping a neighbourless
  # country can leave one of *its* neighbours with no neighbours either, and a
  # single pass left that country in: its weight row was all zeros, the
  # `rs[rs == 0] <- 1` below spared it the division, and it stayed in `n` with a
  # neighbour average of exactly 0 -- treated as a real observation, and absent
  # from `excluded` too. Symmetric schemes ("contiguity", "distance") cannot
  # reach this, but an asymmetric one can: B loses all k of its neighbours and
  # is dropped, A's only surviving neighbour was B, so A is now isolated.
  repeat {
    sub <- m[keep, keep, drop = FALSE]
    still <- keep[rowSums(sub > 0) > 0]
    if (length(still) == length(keep)) break
    keep <- still
    if (!length(keep)) break
  }
  m <- m[keep, keep, drop = FALSE]
  if (length(keep) < 3L) {
    wdj_abort(c(
      "Not enough connected countries with data to compute a spatial statistic.",
      "i" = "Got {length(keep)}; need at least 3.",
      "*" = 'Try a scheme that connects islands, e.g.
             {.code country_weights("knn", k = 5)}.'
    ), call = call, class = "countryatlas_too_few_connected")
  }
  if (identical(weights$style, "W")) {
    rs <- rowSums(m); rs[rs == 0] <- 1
    m <- m / rs
  }
  # Count *pairs* when the scheme is symmetric (contiguity: A borders B is one
  # border, not two) and directed edges when it is not (k-nearest is genuinely
  # asymmetric). Counting non-zero cells regardless doubled the contiguity link
  # count, which the package's own numeric anchor caught.
  nz <- sum(m > 0)
  # Symmetry is a property of the *scheme*, so read it off the full matrix. Off
  # the subset, a k-nearest graph that happens to come out symmetric once the
  # unusable countries are dropped had its link count halved.
  full <- weights$m > 0
  symmetric <- isTRUE(all.equal(unname(full * 1), unname(t(full) * 1)))
  list(
    m = m, iso3c = keep,
    x = df[[val_name]][match(keep, df$iso3c)],
    excluded = sort(setdiff(df$iso3c, keep)),
    n_links = if (symmetric) as.integer(nz / 2) else as.integer(nz),
    weights = weights
  )
}

#' Local Moran's I (LISA)
#'
#' Local Indicators of Spatial Association (Anselin 1995): one Moran statistic
#' per country, plus the cluster type it belongs to. Where [morans_i()] answers
#' "is there clustering anywhere", this answers "where, and of what kind".
#'
#' @param data A country-level frame with `iso3c` and the value column.
#' @param value The value column (unquoted).
#' @param weights A [country_weights()] object. `NULL` (default) uses
#'   `country_weights("knn", k = 5)`: every country's five nearest neighbours,
#'   islands included. `country_weights("contiguity")` gives the land-border
#'   default of earlier versions, which leaves every island out.
#' @param n_perm Permutations for the pseudo-p-value (default `9999`; use `0`
#'   to skip the test, which leaves `p_value` as `NA`). The smallest p-value a
#'   permutation test can give is \eqn{1/(n_{perm}+1)}, and false-discovery
#'   control across about 190 countries needs a finer floor than 999
#'   permutations give; see the section below.
#' @param alpha Significance threshold for the `cluster` label (default `0.05`).
#' @param p_adjust How to adjust the per-country p-values for testing about
#'   190 countries at once: `"fdr"` (default; Benjamini-Hochberg false
#'   discovery rate), `"bonferroni"`, `"holm"` or `"none"`. See the section
#'   below.
#'
#' @return A tibble, one row per country: `iso3c`, `value`, `lag` (the
#'   neighbour average), `ii` (the local statistic), `p_value`, `p_adjusted`
#'   and `cluster` (`"High-High"`, `"Low-Low"`, `"High-Low"`, `"Low-High"` or
#'   `"Not significant"`, judged on `p_adjusted`). The method is recorded as
#'   the `"countryatlas_p_adjust"` attribute.
#'
#' @section One test per country:
#' A local statistic runs one test per country, about 190 of them, so at
#' `alpha = 0.05` roughly ten countries are expected to look significant when
#' nothing is going on at all. `p_adjust = "fdr"` controls the false discovery
#' rate instead -- the share of flagged countries that are false alarms --
#' which is the standard remedy for exactly this setting (Caldas de Castro &
#' Singer 2006) and what GeoDa offers. `"bonferroni"` and `"holm"` control the
#' chance of any false alarm, which is stricter; `"none"` reproduces the
#' unadjusted labels of earlier versions. `p_value` itself is never adjusted,
#' so it still matches `spdep`.
#'
#' Adjustment needs resolution. A permutation p-value cannot go below
#' \eqn{1/(n_{perm}+1)}, and Benjamini-Hochberg flags the most significant of
#' 190 tests only when its p-value is below \eqn{0.05/190 \approx 0.00026}.
#' With 999 permutations the floor, 0.001, is above that, so nothing short of
#' several countries all reaching the floor can be flagged, and an empty map
#' would say "no clusters" when it means "not enough permutations". Hence the
#' default of 9,999, which takes about a second for the whole world.
#'
#'   `p_value` is a **two-sided** pseudo-p from conditional permutation:
#'   \eqn{(1 + \#\{|I_i^{*}| \ge |I_i|\}) / (n_{perm} + 1)}, so it is never
#'   exactly zero and its floor is \eqn{1/(n_{perm}+1)} -- with the default 999
#'   permutations, 0.001. Two-sided because a local statistic is interesting at
#'   both ends: a country surrounded by unlike neighbours is as much a finding
#'   as one surrounded by like ones. `cluster` is `"Not significant"` wherever
#'   `p_value > alpha`, and everywhere when `n_perm = 0` leaves it `NA`. Set a
#'   seed beforehand for a reproducible `p_value`.
#'
#' @references
#' Anselin, L. (1995). Local Indicators of Spatial Association -- LISA.
#' *Geographical Analysis* 27(2), 93-115.
#' \doi{10.1111/j.1538-4632.1995.tb00338.x}
#'
#' Caldas de Castro, M. & Singer, B. H. (2006). Controlling the false discovery
#' rate: a new application to account for multiple and dependent tests in local
#' statistics of spatial association. *Geographical Analysis* 38(2), 180-208.
#' \doi{10.1111/j.0016-7363.2006.00682.x}
#'
#' @seealso [lisa_map()], [morans_i()], [country_weights()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' set.seed(1)
#' local_morans(snap, gdp_per_capita, weights = country_weights("knn", k = 5),
#'              n_perm = 99)
#' }
local_morans <- function(data, value, weights = NULL, n_perm = 9999,
                         alpha = 0.05,
                         p_adjust = c("fdr", "bonferroni", "holm", "none")) {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  check_number(n_perm, "n_perm", lo = 0, hi = .Machine$integer.max)
  check_number(alpha, "alpha", lo = 0, hi = 1)
  p_adjust <- rlang::arg_match(p_adjust)
  al <- align_weights(data, val_name, weights)
  m <- al$m; x <- al$x; n <- length(x)

  flat <- zero_variance(x, val_name)
  z <- x - mean(x)
  m2 <- sum(z^2) / n
  # The statistic and the quadrants need the lag of the *centred* value: "high
  # neighbourhood" means neighbours above the mean, which is what Anselin
  # (1995) defines the four quadrants on. The reported column is the plain
  # neighbour average, because that is what it is documented as and what
  # spatial_lag() returns under the same name. Reporting the centred lag beside
  # a raw `value` broke the Moran scatterplot these two columns exist for: the
  # quadrant boundaries landed at x = mean(value) and y = 0, so the usual
  # reference lines disagreed with the `cluster` column.
  lag_z <- as.numeric(m %*% z)
  lag_raw <- as.numeric(m %*% x)
  ii <- if (flat) rep(NA_real_, n) else (z / m2) * lag_z

  p <- rep(NA_real_, n)
  n_perm <- as.integer(n_perm)
  if (n_perm > 0L && !flat) {
    # Conditional permutation (Anselin 1995): hold each country's own value
    # fixed and draw its neighbours' values from the *other* n - 1. This used
    # to shuffle all n values with one permutation shared by every country,
    # which lets a country's own value land among its neighbours, and for
    # the extreme values a hot-spot map is about, that inflates |I_i*| and so
    # the p-value. Monaco's GDP per capita, the most extreme in the snapshot,
    # came out at p = 0.028 under five nearest neighbours where the
    # conditional reference distribution (and spdep's localmoran_perm()) gives
    # 0.0035.
    ge <- integer(n)
    for (i in seq_len(n)) {
      nb <- which(m[i, ] != 0)
      others <- z[-i]
      # One draw of length(nb) values, without replacement, per permutation;
      # vapply() keeps a single neighbour as a row vector, which matrix()
      # shapes into the same k-by-n_perm layout as several.
      draws <- matrix(others[perm_draws(n - 1L, length(nb), n_perm)],
                      nrow = length(nb))
      iip <- (z[i] / m2) * colSums(draws * m[i, nb])
      ge[i] <- sum(abs(iip) >= abs(ii[i]))
    }
    p <- (1 + ge) / (n_perm + 1)
  }

  hi <- z > 0
  hi_lag <- lag_z > 0
  cluster <- ifelse(hi & hi_lag, "High-High",
             ifelse(!hi & !hi_lag, "Low-Low",
             ifelse(hi & !hi_lag, "High-Low", "Low-High")))
  # About 190 tests at once: unadjusted, roughly ten countries are expected to
  # come out "significant" under the null, and the map gave no hint which.
  p_adj <- adjust_p(p, p_adjust)
  cluster[is.na(p_adj) | p_adj > alpha] <- "Not significant"
  out <- tibble::tibble(
    iso3c = al$iso3c, value = x, lag = lag_raw, ii = as.numeric(ii),
    p_value = p, p_adjusted = p_adj,
    cluster = factor(cluster, levels = c("High-High", "Low-Low", "High-Low",
                                         "Low-High", "Not significant"))
  )
  attr(out, "countryatlas_p_adjust") <- p_adjust
  out
}

# `B` draws of `k` distinct indices from 1..N, as a k-by-B matrix: the
# conditional permutation's neighbour sets. One sample.int() call per draw cost
# 1.2 s for 999 permutations over 189 countries and 12 s for 9,999, which is
# the resolution false-discovery control needs (with 999 the smallest p-value,
# 0.001, is above the first Benjamini-Hochberg cutoff for 190 tests). When a
# draw with replacement is likely to come out distinct anyway -- k small
# against N, as for knn -- draw every tuple at once and redraw only the ones
# with a repeat: rejection sampling, so each surviving tuple is uniform over
# ordered sets of k distinct indices, exactly what sample.int() gives. A large
# neighbourhood, where repeats are the rule, keeps the one-call-per-draw form.
perm_draws <- function(N, k, B) {
  if (k == 0L || B == 0L) return(matrix(integer(), k, B))
  accept <- prod(1 - (seq_len(k) - 1L) / N)
  if (accept < 0.5) {
    return(matrix(vapply(seq_len(B), function(b) sample.int(N, k), integer(k)),
                  nrow = k))
  }
  M <- matrix(sample.int(N, k * B, replace = TRUE), nrow = k)
  if (k == 1L) return(M)
  pairs <- utils::combn(k, 2L)
  todo <- seq_len(B)
  repeat {
    sub <- M[, todo, drop = FALSE]
    dup <- logical(length(todo))
    for (j in seq_len(ncol(pairs))) {
      dup <- dup | sub[pairs[1L, j], ] == sub[pairs[2L, j], ]
    }
    todo <- todo[dup]
    if (!length(todo)) break
    M[, todo] <- sample.int(N, k * length(todo), replace = TRUE)
  }
  M
}

# p.adjust() over the non-missing p-values: "fdr" is Benjamini-Hochberg. NA
# stays NA and does not count towards the number of tests, which is what
# p.adjust() itself does with n = length(p) on the finite ones.
adjust_p <- function(p, method) {
  if (identical(method, "none")) return(p)
  out <- p
  ok <- !is.na(p)
  out[ok] <- stats::p.adjust(p[ok], method = switch(method, fdr = "BH", method))
  out
}

# The words a caption uses for a p_adjust method.
p_adjust_label <- function(method) {
  switch(method,
         fdr = "false discovery rate (Benjamini-Hochberg)",
         bonferroni = "Bonferroni", holm = "Holm", none = "no adjustment")
}

#' Map LISA clusters
#'
#' The map of [local_morans()]: countries coloured by cluster type, with
#' non-significant ones left neutral. Hot spots (High-High) and cold spots
#' (Low-Low) read immediately; the off-diagonal categories are the spatial
#' outliers.
#'
#' @param data A map-ready frame (polygon or `sf`) with `iso3c`.
#' @param value The value column (unquoted).
#' @param weights A [country_weights()] object; `NULL` (default) is
#'   `country_weights("knn", k = 5)`, as in [local_morans()].
#' @param n_perm,alpha,p_adjust Passed to [local_morans()]. The significance
#'   mask uses the adjusted p-values, and the caption names the method.
#' @param ... Passed to [world_map()].
#'
#' @section Backend:
#' Either backend, as [world_map()]: the frame decides, and both draw in Equal
#' Earth unless `projection` is passed on through `...`.
#'
#' @return A `ggplot` object, with the [local_morans()] table attached as the
#'   `"countryatlas_lisa"` attribute.
#' @seealso [local_morans()], [morans_i()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' set.seed(1)
#' attach_geometry(snap, geometry = "polygon") |>
#'   lisa_map(gdp_per_capita, weights = country_weights("knn", k = 5),
#'            n_perm = 99)
#' }
lisa_map <- function(data, value, weights = NULL, n_perm = 9999, alpha = 0.05,
                     p_adjust = c("fdr", "bonferroni", "holm", "none"), ...) {
  refuse_reserved_dots(rlang::list2(...), c("style", "legend"), "lisa_map")
  p_adjust <- rlang::arg_match(p_adjust)
  value_q <- rlang::enquo(value)
  val_name <- quo_arg_name(value_q, "value")
  check_map_geometry(data)
  lisa <- local_morans(data, !!value_q, weights = weights, n_perm = n_perm,
                       alpha = alpha, p_adjust = p_adjust)
  data[[".wdj_cluster"]] <- lisa$cluster[match(data$iso3c, lisa$iso3c)]
  cl_sym <- rlang::sym(".wdj_cluster")
  p <- suppressMessages(
    world_map(data, !!cl_sym, style = "categorical",
              legend = paste0(val_name, "\ncluster"), ...) +
      ggplot2::scale_fill_manual(
        name = paste0(val_name, "\ncluster"),
        values = c("High-High" = "#B2182B", "Low-Low" = "#2166AC",
                   "High-Low" = "#EF8A62", "Low-High" = "#67A9CF",
                   "Not significant" = "grey88"),
        na.value = "grey96", drop = FALSE
      )
  )
  attr(p, "countryatlas_lisa") <- lisa
  # The mask is a multiple-testing decision, so the map says which one.
  sig <- sprintf("Clusters significant at %s after %s.", fmt_num(alpha),
                 p_adjust_label(p_adjust))
  if (identical(p_adjust, "none")) {
    sig <- sprintf("Clusters significant at %s, unadjusted for %d tests.",
                   fmt_num(alpha), sum(!is.na(lisa$p_value)))
  }
  cap <- gg_caption(p)
  p <- p + ggplot2::labs(caption = paste(stats::na.omit(c(cap, sig)),
                                         collapse = " "))
  # Shown means "has a cluster", not "has a value": a country the weights
  # cannot connect keeps its value and is drawn as no-data.
  p <- restate_provenance(p, data, val_name,
                          shown = !is.na(data[[".wdj_cluster"]]))
  prov <- attr(p, "countryatlas_provenance")
  if (!is.null(prov)) {
    prov$p_adjust <- p_adjust
    prov$alpha <- alpha
    attr(p, "countryatlas_provenance") <- prov
  }
  p
}

#' Geary's C (spatial autocorrelation)
#'
#' The other classical global autocorrelation statistic. Where Moran's I is a
#' correlation-like measure centred on \eqn{-1/(n-1)}, Geary's C is a
#' distance-like one centred on 1: **below 1** means positive autocorrelation
#' (neighbours are similar), above 1 means negative. It is more sensitive than
#' Moran's I to local differences.
#'
#' @inheritParams local_morans
#' @param n_perm Permutations for the pseudo-p-value (default `999`; use `0` to
#'   skip the test, which leaves `p_value` as `NA`).
#'
#' @return A one-row tibble: `c` (observed), `expected` (always 1), `n`
#'   (countries used), `n_excluded` (countries with data that the weights could
#'   not reach), `n_links` (non-zero weights), `p_value` and an `excluded`
#'   list-column of the excluded `iso3c` codes. `n` and `n_excluded` sum to the
#'   countries supplied with a value, and mean the same here as in
#'   [morans_i()].
#'
#'   `p_value` is **one-sided on the lower tail**:
#'   \eqn{(1 + \#\{C^{*} \le C_{obs}\}) / (n_{perm} + 1)}. The lower tail is
#'   the clustered one, which is the opposite way round from Moran's *I*:
#'   Geary's *C* runs from 0 (neighbours identical) through 1 (no
#'   autocorrelation) upwards, so a *small* `c` is the evidence of positive
#'   spatial association. Never exactly zero; the floor is
#'   \eqn{1/(n_{perm}+1)}. Set a seed beforehand for a reproducible `p_value`.
#' @references
#' Geary, R. C. (1954). The contiguity ratio and statistical mapping.
#' *The Incorporated Statistician* 5(3), 115-146. \doi{10.2307/2986645}
#' @seealso [morans_i()], [country_weights()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' gearys_c(snap, gdp_per_capita, weights = country_weights("knn", k = 5),
#'          n_perm = 99)
#' }
gearys_c <- function(data, value, weights = NULL, n_perm = 999) {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  check_number(n_perm, "n_perm", lo = 0, hi = .Machine$integer.max)
  al <- align_weights(data, val_name, weights)
  m <- al$m; x <- al$x; n <- length(x)
  stat <- function(v) {
    d2 <- outer(v, v, function(a, b) (a - b)^2)
    ((n - 1) * sum(m * d2)) / (2 * sum(m) * sum((v - mean(v))^2))
  }
  flat <- zero_variance(x, val_name)
  c_obs <- if (flat) NA_real_ else stat(x)
  p <- NA_real_
  n_perm <- as.integer(n_perm)
  if (n_perm > 0L && !flat) {
    perm <- vapply(seq_len(n_perm), function(i) stat(sample(x)), numeric(1))
    # One-sided toward *positive* autocorrelation, which for Geary's C is the
    # low tail -- the opposite direction from Moran's I.
    p <- (1 + sum(perm <= c_obs)) / (n_perm + 1)
  }
  out <- tibble::tibble(c = c_obs, expected = 1, n = n,
                        n_excluded = length(al$excluded), n_links = al$n_links,
                        p_value = p)
  out$excluded <- list(al$excluded)
  out
}

#' Getis-Ord G statistics (hot spots)
#'
#' Global \eqn{G} and local \eqn{G_i^*}: unlike Moran's I, these distinguish
#' clusters of **high** values from clusters of **low** ones, which is what
#' "hot spot" analysis usually wants.
#'
#' @inheritParams local_morans
#' @param local If `TRUE` (default) return the per-country \eqn{G_i^*} with
#'   z-scores; if `FALSE` return the single global \eqn{G}.
#'
#'   The global \eqn{G} needs a variable with a natural origin and no negative
#'   values: it compares cross-products, so negating the variable leaves it
#'   unchanged. Given a negative value it warns and returns `NA` rather than a
#'   number computed outside its domain. \eqn{G_i^*} standardises and is
#'   defined for signed data.
#'
#' @param p_adjust For `local = TRUE`, how to adjust the per-country p-values
#'   for multiple testing: `"fdr"` (default), `"bonferroni"`, `"holm"` or
#'   `"none"`, as in [local_morans()]. The global form makes one test and
#'   takes no adjustment.
#'
#' @return With `local = TRUE`, a tibble of `iso3c`, `gi_star`, `z_score`,
#'   `p_value` (two-sided, from the normal approximation) and `p_adjusted`,
#'   one row per country used. With `local = FALSE`, a one-row tibble of `g`, `expected`, `n`
#'   (countries used -- the same count, so the local form returns `n` rows) and
#'   `n_links` (non-zero weights).
#' @references
#' Getis, A. & Ord, J. K. (1992). The analysis of spatial association by use of
#' distance statistics. *Geographical Analysis* 24(3), 189-206.
#' \doi{10.1111/j.1538-4632.1992.tb00261.x}
#' @seealso [local_morans()], [country_weights()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' getis_ord(snap, gdp_per_capita, weights = country_weights("knn", k = 5))
#' }
getis_ord <- function(data, value, weights = NULL, local = TRUE,
                      p_adjust = c("fdr", "bonferroni", "holm", "none")) {
  check_bool(local, "local")
  p_given <- !missing(p_adjust)
  p_adjust <- rlang::arg_match(p_adjust)
  if (!local && p_given) {
    wdj_warn(c(
      "{.arg p_adjust} applies only to the local statistics and is ignored.",
      "i" = "The global G is a single test."
    ), class = "countryatlas_p_adjust_ignored")
  }
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  al <- align_weights(data, val_name, weights)
  m <- al$m; x <- al$x; n <- length(x)
  if (!local) {
    # The general G is a ratio of weighted to total cross-products, so every
    # x_i * x_j term is unchanged when the whole variable is negated: g(x) and
    # g(-x) came back as bit-for-bit the same double, and the statistic could
    # not tell a coldspot pattern from a hotspot one. Getis & Ord (1992)
    # define it for a variable with a natural origin and positive values, and
    # gini() -- the nearest analogue here, a global index with a positivity
    # domain -- already warns and returns NA in this case. Do the same rather
    # than hand back a plausible-looking number computed outside the domain.
    # The local Gi* branch below standardises and is fine with signed data.
    neg <- sum(!is.na(x) & x < 0)
    if (neg) {
      wdj_warn(c(
        "{.field {val_name}} has {neg} negative value{?s}; the global G needs
         x >= 0.",
        "i" = "It compares cross-products, so negating the variable leaves the
               statistic unchanged. Use {.code local = TRUE}, which
               standardises and is defined for signed data. Returning
               {.code NA}."
      ), class = "countryatlas_global_g_negative")
      g <- NA_real_
    } else {
      # outer() once, not twice: it is the same n-by-n matrix both times.
      cp <- outer(x, x)
      g <- sum(m * cp) / (sum(cp) - sum(x^2))
      # Same convention the negative branch above just set, and gini()'s: an
      # answer outside the statistic's domain is NA plus a word about why, not
      # a silent NaN. Two ways to land here, and the remedies differ. Every
      # value zero makes the denominator 0, so 0/0. Extreme magnitudes make the
      # cross-products non-finite: x * 1e290 overflows outer() to Inf, so the
      # denominator is Inf - Inf, and x * 1e-290 underflows it to 0. Both came
      # back as a bare NaN in the `g` column with nothing said.
      if (!is.finite(g)) {
        zero <- all(x == 0)
        wdj_warn(c(
          "The global G is undefined for {.field {val_name}}.",
          "x" = if (zero) {
            "Every value is zero, so there are no cross-products to compare."
          } else {
            "The cross-products are not finite at this magnitude."
          },
          "i" = if (zero) "Returning {.code NA}." else
            "The statistic is unchanged by a positive scale factor, so
             rescaling the column fixes it. Returning {.code NA}."
        ), class = "countryatlas_undefined_index")
        g <- NA_real_
      }
    }
    return(tibble::tibble(g = g, expected = sum(m) / (n * (n - 1)),
                          n = n, n_links = al$n_links))
  }
  # G_i* includes the focal country (Ord & Getis 1995), so add the diagonal.
  ms <- m; diag(ms) <- 1
  xbar <- mean(x)
  # sqrt(sum(x^2)/n - xbar^2) is the same quantity algebraically and it is what
  # stood here, but it subtracts two nearly equal large numbers: for a column
  # clustered tightly around a big value the result loses every significant
  # digit. Measured on 5-country vectors -- 1e9 + 1:5 gave s = 0, so den = 0
  # and every z_score came back Inf with p_value 0, i.e. "every country is a
  # significant hotspot"; 1e10 + 1:5 gave s 90x too large, so nothing was ever
  # significant; and 1e12 + (10:50) went negative under the sqrt, returning NaN
  # z-scores and leaking base R's "NaNs produced" warning. zero_variance()
  # above catches none of it, because the column is not constant -- only
  # nearly so. Centring first is unconditionally stable and agrees with the
  # old form to floating-point noise on well-conditioned data. local_morans()
  # already computes its second moment this way.
  s <- sqrt(sum((x - xbar)^2) / n)
  wsum <- rowSums(ms)
  wsq <- rowSums(ms^2)
  num <- as.numeric(ms %*% x) - xbar * wsum
  den <- s * sqrt((n * wsq - wsum^2) / (n - 1))
  # s is 0 for a constant column, so z was num/0 -- Inf, or NaN where num is
  # also 0. gi_star stays computable unless the values sum to zero as well.
  flat <- zero_variance(x, val_name)
  z <- if (flat) rep(NA_real_, n) else num / den
  gi <- as.numeric(ms %*% x)
  p <- 2 * stats::pnorm(-abs(z))
  out <- tibble::tibble(iso3c = al$iso3c,
                        gi_star = if (sum(x) == 0) rep(NA_real_, n) else gi / sum(x),
                        z_score = z, p_value = p,
                        p_adjusted = adjust_p(p, p_adjust))
  attr(out, "countryatlas_p_adjust") <- p_adjust
  out
}

#' The neighbour average, as a column
#'
#' The spatially lagged value: for each country, the (weighted) mean of its
#' neighbours. The building block behind every statistic here, and useful on its
#' own -- "what is happening around this country" as a regressor, a map layer or
#' a scatter-plot axis against the country's own value (the Moran scatterplot).
#'
#' @inheritParams local_morans
#' @param suffix Suffix for the new column (default `"_lag"`).
#'
#' @return `data` with the lagged column added. Countries the weights cannot
#'   reach get `NA` -- and since that `NA` is indistinguishable from one caused
#'   by a missing input value, the codes themselves are attached as the
#'   `"countryatlas_excluded"` attribute, the frame-shaped counterpart to the
#'   `excluded` column [morans_i()] returns.
#' @seealso [country_weights()], [local_morans()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' spatial_lag(snap, gdp_per_capita, weights = country_weights("knn", k = 5))
#' }
spatial_lag <- function(data, value, weights = NULL, suffix = "_lag") {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  check_string(suffix, "suffix")
  new <- paste0(val_name, suffix)
  warn_overwrite(data, new)

  # Unlike the other statistics here, this one hands back a column aligned to
  # the caller's own rows -- so on a panel the mismatch is invisible. Matching
  # on iso3c alone gave every year the *earliest* year's neighbour average:
  # France's value ran 39,683 -> 158,734 -> 277,784 while its lag sat at
  # 63,409 for all three, and dividing one by the other silently compared 2002
  # with 2000. A lag per year is both the correct answer and the one the
  # column's placement already implies.
  # Countries the weights exclude -- no neighbour at this scale -- come back
  # NA, and that NA was indistinguishable from a country whose own value was
  # missing: nothing in the result said which countries the weights had
  # dropped. morans_i() and gearys_c() answer this by *returning* `excluded`,
  # and that is the right vehicle here too rather than a warning: on real
  # geography some country always lacks a land neighbour, so a warning would
  # fire on every ordinary call -- noise instead of signal, and a test pins
  # the silence. An attribute is what this package already uses for a
  # diagnostic side-channel (see "countryatlas_cartogram" and
  # "countryatlas_clubs").
  tag_excluded <- function(out, excluded) {
    attr(out, "countryatlas_excluded") <- sort(as.character(excluded))
    out
  }
  yrs <- if ("year" %in% names(data)) unique(stats::na.omit(data$year)) else NULL
  if (length(yrs) > 1L) {
    # Resolve the weights once: they describe geography, not time, and
    # rebuilding them per year would redo the same work each pass.
    if (is.null(weights)) weights <- country_weights("knn", k = 5)
    out <- rep(NA_real_, nrow(data))
    exc <- character(0)
    # One sparse year is that year's problem. A year with too few connected
    # countries used to abort the whole call (every other year's lags lost,
    # under advice about islands) when the rows it could not place are
    # exactly what the documented NA is for.
    thin <- list()
    for (y in yrs) {
      idx <- which(!is.na(data$year) & data$year == y)
      skip_year <- function(e) {
        thin[[length(thin) + 1L]] <<- list(year = y, cnd = e)
        NULL
      }
      al_y <- tryCatch(
        align_weights(data[idx, , drop = FALSE], val_name, weights),
        countryatlas_too_few_connected = skip_year,
        countryatlas_weights_no_overlap = skip_year)
      if (is.null(al_y)) next
      out[idx] <- as.numeric(al_y$m %*% al_y$x)[
        match(data$iso3c[idx], al_y$iso3c)]
      exc <- union(exc, al_y$excluded)
    }
    # Nothing computed at all is the single-year failure, and says so the
    # same way.
    if (length(thin) == length(yrs)) rlang::cnd_signal(thin[[1]]$cnd)
    if (length(thin)) {
      thin_yrs <- vapply(thin, function(t) format(t$year), character(1))
      wdj_warn(c(
        "{length(thin_yrs)} year{?s} ha{?s/ve} too few connected countries for
         a spatial lag; {.field {new}} is {.val {NA}} there:",
        "*" = "{.val {thin_yrs}}",
        "i" = "A lag needs at least three countries the weights connect."
      ), class = "countryatlas_thin_year")
    }
    data[[new]] <- out
    # The union across years: the weights are geography, so a country excluded
    # in one year is excluded in all of them.
    return(tag_excluded(wdj_return_frame(data), exc))
  }

  al <- align_weights(data, val_name, weights)
  lagged <- as.numeric(al$m %*% al$x)
  data[[new]] <- lagged[match(data$iso3c, al$iso3c)]
  data <- tag_excluded(data, al$excluded)
  # Both exits were a bare `data`, so this verb leaked an incoming grouping on
  # either branch and never normalised a data.frame to a tibble.
  wdj_return_frame(data)
}

#' Global Moran's I (spatial autocorrelation)
#'
#' Do neighbouring countries have similar values? Global Moran's I on the country
#' spine, with a permutation pseudo-p-value. No `spdep` required: at ~200
#' countries the dense arithmetic is trivial.
#'
#' @param data A country-level data frame with `iso3c` (map-ready frames are
#'   reduced to one row per country first).
#' @param value The value column (unquoted).
#' @param scale `r lifecycle::badge("deprecated")` The Natural Earth resolution
#'   of the contiguity weights that were the default before 4.0.0. Supplying it
#'   still builds them, with a warning; write
#'   `weights = country_weights("contiguity", scale = )` instead.
#' @param n_perm Number of permutations for the pseudo-p-value (default `999`;
#'   use `0` to skip the test, which leaves `p_value` as `NA`).
#' @param weights A [country_weights()] object. `NULL` (default) uses
#'   `country_weights("knn", k = 5)`, row-standardised, so every country with
#'   data and a centroid takes part. See below.
#'
#' @return A one-row tibble: `i` (observed Moran's I), `expected`
#'   (\eqn{-1/(n-1)} under no autocorrelation), `n` (countries used),
#'   `n_excluded` (countries with data that the weights could not reach),
#'   `n_links`, `p_value` (one-sided, \eqn{P(I_{perm} \ge I_{obs})}, computed as
#'   \eqn{(1 + \#\{I^{*} \ge I_{obs}\}) / (n_{perm} + 1)}, so never exactly
#'   zero -- the floor is \eqn{1/(n_{perm}+1)}) and an `excluded` list-column of
#'   the excluded `iso3c` codes. Set a seed beforehand for a reproducible
#'   `p_value`.
#'
#' @section Which countries are left out:
#' The default weights are the five nearest neighbours, so every country with
#' data and a bundled centroid takes part. Land-border contiguity, the default
#' before 4.0.0, is still available and still systematic in what it drops: an
#' island has no land border, so any country with no land neighbour *present
#' in `data`* leaves the statistic -- Japan, the United Kingdom, Australia,
#' Indonesia, Madagascar, New Zealand, the Philippines, Iceland, Cuba, Sri Lanka
#' and every small island state. On the bundled [world_snapshot]'s GDP per
#' capita that changes the answer, not only the sample: see the numbers in the
#' example below. `n_excluded` and `excluded` report who is left out under
#' either scheme:
#' ```r
#' morans_i(snap, gdp_per_capita, weights = country_weights("contiguity"))
#' ```
#'
#' @references
#' Moran, P. A. P. (1950). Notes on continuous stochastic phenomena.
#' *Biometrika* 37(1/2), 17-23. \doi{10.2307/2332142}
#'
#' @seealso [country_weights()], [local_morans()], [gearys_c()], [spatial_lag()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' set.seed(42)
#' # every country included, no sf required
#' morans_i(snap, gdp_per_capita, n_perm = 99,
#'          weights = country_weights("knn", k = 5))
#' }
morans_i <- function(data, value, scale = deprecated(), n_perm = 999,
                     weights = NULL) {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  check_number(n_perm, "n_perm", lo = 0, hi = .Machine$integer.max)
  # `scale` set the resolution of the old contiguity default. Honour it the
  # old way, so a 3.0.0 call keeps its meaning, and say how to write it now.
  if (lifecycle::is_present(scale)) {
    lifecycle::deprecate_warn(
      "4.0.0", "morans_i(scale)",
      details = c(
        "i" = "The default weights are now k-nearest neighbours (k = 5).",
        "i" = paste0("Write `weights = country_weights(\"contiguity\", ",
                     "scale = \"", scale, "\")` for the land-border weights ",
                     "it used to build.")))
    if (!is.null(weights)) scale <- NULL
  } else {
    scale <- NULL
  }
  al <- align_weights(data, val_name, weights, scale = scale)
  m <- al$m; x <- al$x; n <- length(x)

  moran_stat <- function(v) {
    z <- v - mean(v)
    (n / sum(m)) * sum(m * outer(z, z)) / sum(z^2)
  }
  flat <- zero_variance(x, val_name)
  i_obs <- if (flat) NA_real_ else moran_stat(x)

  p_value <- NA_real_
  n_perm <- as.integer(n_perm)
  if (n_perm > 0L && !flat) {
    i_perm <- vapply(seq_len(n_perm), function(k) moran_stat(sample(x)),
                     numeric(1))
    p_value <- (1 + sum(i_perm >= i_obs)) / (n_perm + 1)
  }
  out <- tibble::tibble(
    i = i_obs, expected = -1 / (n - 1), n = n,
    n_excluded = length(al$excluded), n_links = al$n_links, p_value = p_value
  )
  out$excluded <- list(al$excluded)
  out
}

# --- Rates, two variables, and categories -----------------------------------------

#' Moran's I for rates, not fooled by small denominators
#'
#' Moran's I on raw rates mistakes the noise of small denominators for
#' clustering: a few small states with extreme rates beside one another look
#' like a hot spot. The empirical-Bayes index (Assuncao & Reis 1999)
#' standardises each rate by how much variation its denominator alone would
#' produce before testing for autocorrelation.
#'
#' @param data A country-level frame with `iso3c`.
#' @param numerator,denominator The counts and their population at risk
#'   (unquoted).
#' @param weights A [country_weights()] object; `NULL` (default) is k-nearest
#'   neighbours (k = 5), as for [morans_i()].
#' @param n_perm Permutations for the pseudo p-value (default `999`; `0` skips
#'   it).
#'
#' @return A one-row tibble like [morans_i()]'s: `i`, `expected`, `n`,
#'   `n_excluded`, `n_links`, `p_value` (one-sided, for positive
#'   autocorrelation) and the list-column `excluded`.
#'
#' @section The statistic:
#' With rates \eqn{p_i = y_i / x_i}, the global rate \eqn{b = \sum y / \sum x}
#' and the method-of-moments between-country variance \eqn{a} (as in
#' [smooth_rates()]), each rate is standardised as
#' \eqn{z_i = (p_i - b) / \sqrt{a + b / x_i}} and Moran's I is computed on
#' \eqn{z}. It agrees with `spdep::EBImoran.mc()` on the same weights.
#'
#' @references
#' Assuncao, R. M. & Reis, E. A. (1999). A new proposal to adjust Moran's I
#' for population density. *Statistics in Medicine* 18(16), 2147-2162.
#' \doi{10.1002/(SICI)1097-0258(19990830)18:16<2147::AID-SIM179>3.0.CO;2-I}
#' @seealso [morans_i()], [smooth_rates()], [rate_funnel()]
#' @export
#' @examples
#' snap <- countryatlas::world_snapshot$countries
#' snap$births <- snap$population * 0.02
#' eb_morans_i(snap, births, population, n_perm = 0)
eb_morans_i <- function(data, numerator, denominator, weights = NULL,
                        n_perm = 999) {
  num_name <- quo_arg_name(rlang::enquo(numerator), "numerator")
  den_name <- quo_arg_name(rlang::enquo(denominator), "denominator")
  check_number(n_perm, "n_perm", lo = 0, hi = .Machine$integer.max)
  check_cols(data, c("iso3c", num_name, den_name))
  check_numeric_col(data, num_name)
  check_numeric_col(data, den_name)
  df <- distinct_countries(tibble::as_tibble(sf_drop(data)))
  y <- df[[num_name]]
  x <- df[[den_name]]
  # Built typed rather than with ifelse(), which returns logical(0) on an
  # empty frame and so failed a numeric check on a column the caller never
  # named.
  ok <- is.finite(y) & y >= 0 & is.finite(x) & x > 0
  df$.wdj_rate <- rep(NA_real_, nrow(df))
  df$.wdj_rate[ok] <- y[ok] / x[ok]
  al <- align_weights(df, ".wdj_rate", weights)
  m <- al$m
  at <- match(al$iso3c, df$iso3c)
  y <- y[at]
  x <- x[at]
  n <- length(y)
  b <- sum(y) / sum(x)
  p <- y / x
  s2 <- sum(x * (p - b)^2) / sum(x)
  a <- max(s2 - b / (sum(x) / n), 0)
  z <- (p - b) / sqrt(a + b / x)
  stat <- function(v) {
    vc <- v - mean(v)
    (n / sum(m)) * sum(vc * as.numeric(m %*% vc)) / sum(vc^2)
  }
  flat <- zero_variance(z, "the standardised rate")
  i_obs <- if (flat) NA_real_ else stat(z)
  p_value <- NA_real_
  n_perm <- as.integer(n_perm)
  if (n_perm > 0L && !flat) {
    perm <- vapply(seq_len(n_perm), function(k) stat(sample(z)), numeric(1))
    p_value <- (1 + sum(perm >= i_obs)) / (n_perm + 1)
  }
  out <- tibble::tibble(i = i_obs, expected = -1 / (n - 1), n = n,
                        n_excluded = length(al$excluded),
                        n_links = al$n_links, p_value = p_value)
  out$excluded <- list(al$excluded)
  out
}

#' Bivariate local Moran: high X among high Y
#'
#' The local Moran statistic for two variables (Anselin, Syabri & Smirnov
#' 2002): each country's standardised `x` against the average standardised
#' `y` of its neighbours, so "rich countries surrounded by long-lived
#' neighbours" is a cluster, and a rich country among short-lived neighbours
#' an outlier.
#'
#' @param data A country-level frame with `iso3c`.
#' @param x,y The two value columns (unquoted).
#' @param weights,n_perm,alpha,p_adjust As in [local_morans()].
#'
#' @return A tibble with one row per country used: `iso3c`, `x`, `lag_y` (the
#'   neighbours' average `y`), `ii`, `p_value`, `p_adjusted` and `cluster`
#'   (`"High-High"`, `"Low-Low"`, `"High-Low"`, `"Low-High"` or
#'   `"Not significant"`), where the first word is the country's `x` and the
#'   second its neighbours' `y`. A country needs both values to take part.
#'
#' @references
#' Anselin, L., Syabri, I. & Smirnov, O. (2002). Visualizing multivariate
#' spatial correlation with dynamically linked windows. *Proceedings, CSISS
#' Workshop on New Tools for Spatial Data Analysis*.
#' @seealso [local_morans()], [lisa_map()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' bivariate_lisa(snap, gdp_per_capita, life_expectancy, n_perm = 499)
#' }
bivariate_lisa <- function(data, x, y, weights = NULL, n_perm = 9999,
                           alpha = 0.05,
                           p_adjust = c("fdr", "bonferroni", "holm", "none")) {
  x_name <- quo_arg_name(rlang::enquo(x), "x")
  y_name <- quo_arg_name(rlang::enquo(y), "y")
  check_number(n_perm, "n_perm", lo = 0, hi = .Machine$integer.max)
  check_number(alpha, "alpha", lo = 0, hi = 1)
  p_adjust <- rlang::arg_match(p_adjust)
  check_cols(data, c("iso3c", x_name, y_name))
  check_numeric_col(data, x_name)
  check_numeric_col(data, y_name)
  df <- distinct_countries(tibble::as_tibble(sf_drop(data)))
  # Typed, not ifelse(): see eb_morans_i().
  ok <- is.finite(df[[x_name]]) & is.finite(df[[y_name]])
  df$.wdj_both <- rep(NA_real_, nrow(df))
  df$.wdj_both[ok] <- df[[x_name]][ok]
  al <- align_weights(df, ".wdj_both", weights)
  m <- al$m
  at <- match(al$iso3c, df$iso3c)
  xv <- df[[x_name]][at]
  yv <- df[[y_name]][at]
  n <- length(xv)
  flat <- zero_variance(xv, x_name) || zero_variance(yv, y_name)
  sdp <- function(v) sqrt(sum((v - mean(v))^2) / length(v))
  zx <- (xv - mean(xv)) / sdp(xv)
  zy <- (yv - mean(yv)) / sdp(yv)
  lag_zy <- as.numeric(m %*% zy)
  ii <- if (flat) rep(NA_real_, n) else zx * lag_zy
  p <- rep(NA_real_, n)
  n_perm <- as.integer(n_perm)
  if (n_perm > 0L && !flat) {
    ge <- integer(n)
    for (i in seq_len(n)) {
      nb <- which(m[i, ] != 0)
      others <- zy[-i]
      draws <- matrix(others[perm_draws(n - 1L, length(nb), n_perm)],
                      nrow = length(nb))
      iip <- zx[i] * colSums(draws * m[i, nb])
      ge[i] <- sum(abs(iip) >= abs(ii[i]))
    }
    p <- (1 + ge) / (n_perm + 1)
  }
  cluster <- ifelse(zx > 0 & lag_zy > 0, "High-High",
             ifelse(zx <= 0 & lag_zy <= 0, "Low-Low",
             ifelse(zx > 0, "High-Low", "Low-High")))
  p_adj <- adjust_p(p, p_adjust)
  cluster[is.na(p_adj) | p_adj > alpha] <- "Not significant"
  out <- tibble::tibble(
    iso3c = al$iso3c, x = xv, lag_y = as.numeric(m %*% yv), ii = ii,
    p_value = p, p_adjusted = p_adj,
    cluster = factor(cluster, levels = c("High-High", "Low-Low", "High-Low",
                                         "Low-High", "Not significant")))
  attr(out, "countryatlas_p_adjust") <- p_adjust
  out
}

#' Join counts: do neighbours share a category?
#'
#' For a categorical variable -- income group, region, a yes/no -- count the
#' neighbouring pairs whose two countries fall in the same category, and
#' compare each count with what random labelling would give. Many more
#' same-category joins than chance is clustering; fewer is a checkerboard.
#'
#' @param data A country-level frame with `iso3c`.
#' @param value The categorical column (unquoted): a factor, character or
#'   logical.
#' @param weights A [country_weights()] object; `NULL` (default) is k-nearest
#'   neighbours (k = 5). A pair is joined when either country lists the other
#'   as a neighbour.
#' @param n_perm Permutations of the labels for the p-values (default `999`).
#'
#' @return A tibble with one row per category: `category`, `n` (countries in
#'   it), `joins` (pairs within it), `expected` and `sd` (under permutation),
#'   `z`, and `p_value` (two-sided). Its `"n_joins"` attribute is the number
#'   of joined pairs.
#' @references
#' Cliff, A. D. & Ord, J. K. (1981). *Spatial Processes: Models and
#' Applications*. Pion.
#' @seealso [morans_i()] for a numeric variable
#' @export
#' @examples
#' snap <- countryatlas::world_snapshot$countries
#' join_counts(snap, income, n_perm = 199)
join_counts <- function(data, value, weights = NULL, n_perm = 999) {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  check_number(n_perm, "n_perm", lo = 1, hi = .Machine$integer.max)
  check_cols(data, c("iso3c", val_name))
  v <- data[[val_name]]
  if (is.numeric(v)) {
    wdj_abort(c(
      "{.arg value} must be categorical: a factor, character or logical.",
      "i" = "For a numeric column, use {.fn morans_i}."
    ))
  }
  df <- distinct_countries(tibble::as_tibble(sf_drop(data)))
  lab <- as.character(df[[val_name]])
  # Typed, not ifelse(): see eb_morans_i().
  df$.wdj_code <- rep(NA_real_, nrow(df))
  df$.wdj_code[!is.na(lab)] <- 1
  al <- align_weights(df, ".wdj_code", weights)
  lab <- lab[match(al$iso3c, df$iso3c)]
  adj <- (al$m > 0) | t(al$m > 0)
  pairs <- which(upper.tri(adj) & adj, arr.ind = TRUE)
  cats <- sort(unique(lab), method = "radix")
  count <- function(l) {
    same <- l[pairs[, 1]] == l[pairs[, 2]]
    vapply(cats, function(cc) sum(same & l[pairs[, 1]] == cc), numeric(1))
  }
  obs <- count(lab)
  sims <- vapply(seq_len(as.integer(n_perm)), function(k) count(sample(lab)),
                 numeric(length(cats)))
  sims <- matrix(sims, nrow = length(cats))
  expd <- rowMeans(sims)
  sdv <- apply(sims, 1, stats::sd)
  p <- vapply(seq_along(cats), function(k) {
    dev <- abs(sims[k, ] - expd[k])
    (1 + sum(dev >= abs(obs[k] - expd[k]))) / (n_perm + 1)
  }, numeric(1))
  out <- tibble::tibble(
    category = cats, n = as.integer(table(factor(lab, levels = cats))),
    joins = as.integer(obs), expected = expd, sd = sdv,
    z = ifelse(sdv > 0, (obs - expd) / sdv, NA_real_), p_value = p)
  attr(out, "n_joins") <- nrow(pairs)
  out
}
