# Spatial weights and the statistics built on them --------------------------------
#
# morans_i() shipped in 2.0.0 with one hard-wired weight scheme: land-border
# contiguity, row-standardised. That is a defensible default and a consequential
# one -- an island has no land border, so Japan, the UK, Australia, Indonesia,
# Madagascar, New Zealand, the Philippines, Iceland and every small island state
# carried no weight and left the analysis. 2.1.0 made that visible (n_excluded);
# this makes it fixable. country_weights("knn") gives every country neighbours,
# and the same object drives local statistics, Geary's C, Getis-Ord and the
# spatial lag.
#
# The distinctive one is type = "custom": adjacency does not have to be
# geographic. "Countries near each other in *trade* space" is often the relevant
# neighbourhood for an economic question, and it goes through the same API.

#' Spatial weights on the country spine
#'
#' Build a reusable neighbour-weights object for [morans_i()], [local_morans()],
#' [gearys_c()], [getis_ord()] and [spatial_lag()]. Four schemes, three of which
#' give every country at least one neighbour -- which land-border contiguity, the
#' historical default, cannot do for an island.
#'
#' @param type
#'   * `"contiguity"` -- shared land border, from [country_borders()]. Needs
#'     `sf`. Islands get no neighbours; see [morans_i()]'s note.
#'   * `"knn"` -- the `k` nearest countries by great-circle centroid distance.
#'     Every country gets exactly `k` neighbours, islands included. Needs
#'     nothing but the bundled [country_meta].
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
country_weights <- function(type = c("contiguity", "knn", "distance", "custom"),
                            countries = NULL, k = 5, cutoff_km = NULL,
                            w = NULL, style = c("W", "B"), scale = "small") {
  type <- rlang::arg_match(type)
  style <- rlang::arg_match(style)
  if (!is.null(countries)) {
    countries <- unique(stats::na.omit(as.character(countries)))
    if (!length(countries)) wdj_abort("{.arg countries} has no usable codes.")
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
# centroid for a handful of small territories and no row at all for Kosovo (see
# ?distance_between), so say which countries dropped out rather than returning a
# quietly smaller matrix.
weights_centroids <- function(countries) {
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
    wdj_abort("Need at least 2 countries with centroids to build weights.")
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

weights_knn <- function(countries, k) {
  check_number(k, "k", lo = 1, hi = .Machine$integer.max)
  k <- as.integer(k)
  meta <- weights_centroids(countries)
  n <- nrow(meta)
  if (k >= n) {
    wdj_abort(c(
      "{.arg k} must be smaller than the number of countries.",
      "x" = "Got k = {k} with {n} countries."
    ))
  }
  d <- weights_distance_matrix(meta)
  diag(d) <- Inf                       # a country is not its own neighbour
  m <- matrix(0, n, n, dimnames = dimnames(d))
  for (i in seq_len(n)) m[i, order(d[i, ])[seq_len(k)]] <- 1
  # k-nearest is asymmetric by construction (A may be in B's top k without B
  # being in A's); that is standard and intended, so do not symmetrise.
  list(m = m, n_links = sum(m > 0), degree = rowSums(m))
}

weights_distance <- function(countries, cutoff_km) {
  if (is.null(cutoff_km)) {
    wdj_abort('{.arg cutoff_km} is required for {.code type = "distance"}.')
  }
  check_number(cutoff_km, "cutoff_km", lo = 0)
  meta <- weights_centroids(countries)
  d <- weights_distance_matrix(meta)
  m <- (d <= cutoff_km) * 1
  diag(m) <- 0
  list(m = m, n_links = sum(m > 0) / 2, degree = rowSums(m))
}

weights_custom <- function(w, countries) {
  if (is.null(w)) {
    wdj_abort('{.arg w} is required for {.code type = "custom"}.')
  }
  if (is.matrix(w)) {
    if (is.null(rownames(w)) || is.null(colnames(w))) {
      wdj_abort("A custom weights matrix must have {.field iso3c} row and column names.")
    }
    if (!identical(rownames(w), colnames(w))) {
      wdj_abort("A custom weights matrix must have identical row and column names.")
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
      ))
    }
    if (anyNA(w)) {
      wdj_abort(c(
        "A custom weights matrix must not contain {.val NA}.",
        "x" = "{sum(is.na(w))} entr{?y/ies} {?is/are} missing.",
        "i" = "Use {.val {0}} for {.emph not a neighbour}."
      ))
    }
    m <- w
    storage.mode(m) <- "double"
  } else if (is.data.frame(w)) {
    check_cols(w, c("iso3c", "neighbor"))
    val <- if ("weight" %in% names(w)) w$weight else rep(1, nrow(w))
    if (!is.numeric(val)) wdj_abort("{.field weight} must be numeric.")
    # An NA endpoint reached the matrix assignment below as base R's "NAs are
    # not allowed in subscripted assignments"; an NA weight was accepted and
    # turned every statistic built on it into a silent NA.
    if (anyNA(w$iso3c) || anyNA(w$neighbor)) {
      bad <- sum(is.na(w$iso3c) | is.na(w$neighbor))
      wdj_abort(c(
        "{.field iso3c} and {.field neighbor} must not contain {.val NA}.",
        "x" = "{bad} row{?s} {?is/are} missing an endpoint.",
        "i" = "A link needs both ends; drop those rows."
      ))
    }
    if (anyNA(val)) {
      wdj_abort(c(
        "{.field weight} must not contain {.val NA}.",
        "x" = "{sum(is.na(val))} weight{?s} {?is/are} missing.",
        "i" = "Use {.val {0}} for {.emph not a neighbour}, or drop the row."
      ))
    }
    iso <- sort(unique(c(w$iso3c, w$neighbor)))
    m <- matrix(0, length(iso), length(iso), dimnames = list(iso, iso))
    m[cbind(as.character(w$iso3c), as.character(w$neighbor))] <- val
  } else {
    wdj_abort(c(
      "{.arg w} must be a named square matrix or a long data frame.",
      "x" = "Got {.cls {class(w)[1]}}.",
      "i" = "A long frame needs {.field iso3c}, {.field neighbor} and optionally
             {.field weight}."
    ))
  }
  if (!is.null(countries)) {
    keep <- intersect(rownames(m), countries)
    if (length(keep) < 2L) wdj_abort("Fewer than 2 of {.arg countries} appear in {.arg w}.")
    m <- m[keep, keep, drop = FALSE]
  }
  diag(m) <- 0
  list(m = m, n_links = sum(m > 0), degree = rowSums(m))
}

# --- align a weights object to a data frame -------------------------------------
#
# Every statistic below needs the same thing: one value per country, the weights
# subset to the countries that have both a value and a row in the matrix, and a
# report of who fell out. Doing it once keeps morans_i()'s exclusion accounting
# consistent across all of them.
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

align_weights <- function(data, val_name, weights, scale = "small",
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
  df <- df[!is.na(df$iso3c) & is.finite(df[[val_name]]), ]

  if (is.null(weights)) weights <- country_weights("contiguity", scale = scale)
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
  m <- m[keep, keep, drop = FALSE]
  deg <- rowSums(m > 0)
  keep <- keep[deg > 0]
  if (length(keep) < 3L) {
    wdj_abort(c(
      "Not enough connected countries with data to compute a spatial statistic.",
      "i" = "Got {length(keep)}; need at least 3.",
      "*" = 'Try a scheme that connects islands, e.g.
             {.code country_weights("knn", k = 5)}.'
    ), call = call)
  }
  m <- m[keep, keep, drop = FALSE]
  if (identical(weights$style, "W")) {
    rs <- rowSums(m); rs[rs == 0] <- 1
    m <- m / rs
  }
  # Count *pairs* when the scheme is symmetric (contiguity: A borders B is one
  # border, not two) and directed edges when it is not (k-nearest is genuinely
  # asymmetric). Counting non-zero cells regardless doubled the contiguity link
  # count, which the package's own numeric anchor caught.
  nz <- sum(m > 0)
  symmetric <- isTRUE(all.equal(unname((m > 0) * 1), unname(t(m > 0) * 1)))
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
#' @param weights A [country_weights()] object. Defaults to land-border
#'   contiguity, which excludes islands -- prefer `country_weights("knn")` for
#'   global work.
#' @param n_perm Permutations for the pseudo-p-value (default `999`; use `0` to
#'   skip the test, which leaves `p_value` as `NA`).
#' @param alpha Significance threshold for the `cluster` label (default `0.05`).
#'
#' @return A tibble, one row per country: `iso3c`, `value`, `lag` (the
#'   neighbour average), `ii` (the local statistic), `p_value` and `cluster`
#'   (`"High-High"`, `"Low-Low"`, `"High-Low"`, `"Low-High"` or `"Not
#'   significant"`).
#'
#' @references
#' Anselin, L. (1995). Local Indicators of Spatial Association -- LISA.
#' *Geographical Analysis* 27(2), 93-115.
#' \doi{10.1111/j.1538-4632.1995.tb00338.x}
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
local_morans <- function(data, value, weights = NULL, n_perm = 999,
                         alpha = 0.05) {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  check_number(n_perm, "n_perm", lo = 0, hi = .Machine$integer.max)
  check_number(alpha, "alpha", lo = 0, hi = 1)
  al <- align_weights(data, val_name, weights)
  m <- al$m; x <- al$x; n <- length(x)

  flat <- zero_variance(x, val_name)
  z <- x - mean(x)
  m2 <- sum(z^2) / n
  lag <- as.numeric(m %*% z)
  ii <- if (flat) rep(NA_real_, n) else (z / m2) * lag

  p <- rep(NA_real_, n)
  n_perm <- as.integer(n_perm)
  if (n_perm > 0L && !flat) {
    # Conditional permutation: hold each country's own value fixed and shuffle
    # the rest, which is the standard LISA reference distribution.
    ge <- integer(n)
    for (b in seq_len(n_perm)) {
      zp <- sample(z)
      iip <- (z / m2) * as.numeric(m %*% zp)
      ge <- ge + (abs(iip) >= abs(ii))
    }
    p <- (1 + ge) / (n_perm + 1)
  }

  hi <- z > 0
  hi_lag <- lag > 0
  cluster <- ifelse(hi & hi_lag, "High-High",
             ifelse(!hi & !hi_lag, "Low-Low",
             ifelse(hi & !hi_lag, "High-Low", "Low-High")))
  cluster[is.na(p) | p > alpha] <- "Not significant"
  tibble::tibble(
    iso3c = al$iso3c, value = x, lag = as.numeric(lag), ii = as.numeric(ii),
    p_value = p,
    cluster = factor(cluster, levels = c("High-High", "Low-Low", "High-Low",
                                         "Low-High", "Not significant"))
  )
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
#' @param weights A [country_weights()] object.
#' @param n_perm,alpha Passed to [local_morans()].
#' @param ... Passed to [world_map()].
#'
#' @return A `ggplot` object, with the [local_morans()] table attached as the
#'   `"countryatlas_lisa"` attribute.
#' @seealso [local_morans()], [morans_i()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' if (requireNamespace("maps", quietly = TRUE)) {
#'   set.seed(1)
#'   attach_geometry(snap, geometry = "polygon") |>
#'     lisa_map(gdp_per_capita, weights = country_weights("knn", k = 5),
#'              n_perm = 99)
#' }
#' }
lisa_map <- function(data, value, weights = NULL, n_perm = 999, alpha = 0.05,
                     ...) {
  value_q <- rlang::enquo(value)
  val_name <- quo_arg_name(value_q, "value")
  check_map_geometry(data)
  lisa <- local_morans(data, !!value_q, weights = weights, n_perm = n_perm,
                       alpha = alpha)
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
#' @return A one-row tibble: `c` (observed), `expected` (always 1), `n`,
#'   `n_excluded`, `n_links`, `p_value` and an `excluded` list-column.
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
#' @return With `local = TRUE`, a tibble of `iso3c`, `gi_star`, `z_score` and
#'   `p_value` (two-sided, from the normal approximation). With `local = FALSE`,
#'   a one-row tibble of `g`, `expected`, `n` and `n_links`.
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
getis_ord <- function(data, value, weights = NULL, local = TRUE) {
  check_bool(local, "local")
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  al <- align_weights(data, val_name, weights)
  m <- al$m; x <- al$x; n <- length(x)
  if (!local) {
    g <- sum(m * outer(x, x)) / (sum(outer(x, x)) - sum(x^2))
    return(tibble::tibble(g = g, expected = sum(m) / (n * (n - 1)),
                          n = n, n_links = al$n_links))
  }
  # G_i* includes the focal country (Ord & Getis 1995), so add the diagonal.
  ms <- m; diag(ms) <- 1
  xbar <- mean(x)
  s <- sqrt(sum(x^2) / n - xbar^2)
  wsum <- rowSums(ms)
  wsq <- rowSums(ms^2)
  num <- as.numeric(ms %*% x) - xbar * wsum
  den <- s * sqrt((n * wsq - wsum^2) / (n - 1))
  # s is 0 for a constant column, so z was num/0 -- Inf, or NaN where num is
  # also 0. gi_star stays computable unless the values sum to zero as well.
  flat <- zero_variance(x, val_name)
  z <- if (flat) rep(NA_real_, n) else num / den
  gi <- as.numeric(ms %*% x)
  tibble::tibble(iso3c = al$iso3c,
                 gi_star = if (sum(x) == 0) rep(NA_real_, n) else gi / sum(x),
                 z_score = z, p_value = 2 * stats::pnorm(-abs(z)))
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
#'   reach get `NA`.
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
  yrs <- if ("year" %in% names(data)) unique(stats::na.omit(data$year)) else NULL
  if (length(yrs) > 1L) {
    # Resolve the weights once: they describe geography, not time, and
    # rebuilding contiguity per year would re-read the basemap each pass.
    if (is.null(weights)) weights <- country_weights("contiguity")
    out <- rep(NA_real_, nrow(data))
    for (y in yrs) {
      idx <- which(!is.na(data$year) & data$year == y)
      al_y <- align_weights(data[idx, , drop = FALSE], val_name, weights)
      out[idx] <- as.numeric(al_y$m %*% al_y$x)[
        match(data$iso3c[idx], al_y$iso3c)]
    }
    data[[new]] <- out
    return(wdj_return_frame(data))
  }

  al <- align_weights(data, val_name, weights)
  lagged <- as.numeric(al$m %*% al$x)
  data[[new]] <- lagged[match(data$iso3c, al$iso3c)]
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
#' @param scale Natural Earth resolution for the default contiguity adjacency
#'   (see [country_borders()]). Ignored when `weights` is supplied.
#' @param n_perm Number of permutations for the pseudo-p-value (default `999`;
#'   use `0` to skip the test, which leaves `p_value` as `NA`).
#' @param weights A [country_weights()] object. Defaults to land-border
#'   contiguity, row-standardised -- which excludes every island. See below.
#'
#' @return A one-row tibble: `i` (observed Moran's I), `expected`
#'   (\eqn{-1/(n-1)} under no autocorrelation), `n` (countries used),
#'   `n_excluded` (countries with data that the weights could not reach),
#'   `n_links`, `p_value` (one-sided, \eqn{P(I_{perm} \ge I_{obs})}) and an
#'   `excluded` list-column of the excluded `iso3c` codes. Set a seed beforehand
#'   for a reproducible `p_value`.
#'
#' @section Which countries are left out:
#' The default weights are land-border contiguity, and an island has no land
#' border -- so any country with no land neighbour *present in `data`* drops out
#' entirely. On the bundled [world_snapshot] that is around a quarter of the
#' countries with data: Japan, the United Kingdom, Australia, Indonesia,
#' Madagascar, New Zealand, the Philippines, Iceland, Cuba, Sri Lanka and every
#' small island state. The omission is systematic rather than random.
#'
#' `n_excluded` and `excluded` report it, and [country_weights()] fixes it --
#' `"knn"` and `"distance"` give every country neighbours:
#' ```r
#' morans_i(snap, gdp_per_capita, weights = country_weights("knn", k = 5))
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
morans_i <- function(data, value, scale = "small", n_perm = 999,
                     weights = NULL) {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  check_number(n_perm, "n_perm", lo = 0, hi = .Machine$integer.max)
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
