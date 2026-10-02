# Distribution dynamics -------------------------------------------------------------
#
# beta and sigma convergence summarise a distribution in one number each; these
# describe how countries move within it: who stays poor, who moves up, and
# whether a country's neighbours change its odds (Quah 1993, 1996; Rey 2001).

# Classes per year for a panel: "quantile" cuts each year's cross-section at
# its own quantiles; "relative" divides by the year's cross-country mean and
# cuts at the pooled quantiles of those ratios, so a class means the same
# relative income in every year.
dynamics_classes <- function(df, val_name, n_classes, classes) {
  v <- df[[val_name]]
  yr <- df$year
  cls <- rep(NA_integer_, length(v))
  if (identical(classes, "quantile")) {
    for (y in unique(yr)) {
      k <- which(yr == y & is.finite(v))
      if (length(k) < n_classes) next
      br <- unique(stats::quantile(v[k], seq(0, 1, length.out = n_classes + 1),
                                   names = FALSE))
      cls[k] <- as.integer(cut(v[k], br, include.lowest = TRUE))
    }
    return(list(class = cls, breaks = NULL))
  }
  rel <- v / stats::ave(v, yr, FUN = function(z) mean(z[is.finite(z)]))
  ok <- is.finite(rel)
  br <- unique(stats::quantile(rel[ok], seq(0, 1, length.out = n_classes + 1),
                               names = FALSE))
  cls[ok] <- as.integer(cut(rel[ok], br, include.lowest = TRUE))
  list(class = cls, breaks = br)
}

# The panel the dynamics verbs read: one row per country and year, finite
# values, numeric years.
dynamics_panel <- function(data, val_name, call = rlang::caller_env()) {
  check_cols(data, c("iso3c", "year", val_name), call = call)
  check_numeric_col(data, val_name, call = call)
  df <- tibble::as_tibble(sf_drop(data))[, c("iso3c", "year", val_name)]
  df$year <- year_number(df$year, call = call)
  df <- df[!is.na(df$iso3c) & !is.na(df$year), , drop = FALSE]
  if (anyDuplicated(df[, c("iso3c", "year")])) {
    wdj_abort(c("{.arg data} has more than one row for some country and year.",
                "i" = "Transitions are read country by country, year by year."),
              call = call)
  }
  df
}

# Transition counts and probabilities from class pairs.
transition_table <- function(from, to, n_classes) {
  ok <- !is.na(from) & !is.na(to)
  tab <- table(factor(from[ok], levels = seq_len(n_classes)),
               factor(to[ok], levels = seq_len(n_classes)))
  n <- matrix(as.integer(tab), n_classes)
  rs <- rowSums(n)
  p <- n / ifelse(rs > 0, rs, NA_real_)
  list(n = n, p = p)
}

# The stationary distribution of a transition matrix: the left eigenvector for
# the eigenvalue 1, normalised to sum to one.
ergodic_distribution <- function(p) {
  p[is.na(p)] <- 0
  e <- eigen(t(p))
  v <- Re(e$vectors[, which.min(abs(e$values - 1))])
  v / sum(v)
}

# Mean first-passage times (Kemeny & Snell 1960): steps from class i to first
# reach class j, with the mean recurrence time 1 / pi_j on the diagonal.
first_passage <- function(p, pi) {
  k <- nrow(p)
  w <- matrix(pi, k, k, byrow = TRUE)
  z <- tryCatch(solve(diag(k) - p + w), error = function(e) NULL)
  if (is.null(z)) return(matrix(NA_real_, k, k))
  m <- (matrix(diag(z), k, k, byrow = TRUE) - z) / matrix(pi, k, k, byrow = TRUE)
  diag(m) <- 1 / pi
  m
}

as_transition_tibble <- function(tt) {
  k <- nrow(tt$n)
  tibble::tibble(from = rep(seq_len(k), times = k), to = rep(seq_len(k), each = k),
                 n = as.integer(tt$n), p = as.numeric(tt$p))
}

#' Markov transitions between income classes
#'
#' How countries move between classes of a variable from one year to the next:
#' the discrete Markov chain of Quah's distribution dynamics. Class 1 is the
#' lowest.
#'
#' @param data A panel with `iso3c`, `year` and the value column.
#' @param value The column to classify (unquoted), such as GDP per capita.
#' @param n_classes Number of classes (default `5`).
#' @param classes `"quantile"` (default) cuts each year at its own quantiles,
#'   so a class is a rank band; `"relative"` divides each value by its year's
#'   cross-country mean and cuts at the pooled quantiles of those ratios, so a
#'   class is a band of relative income that can fill or empty over time.
#' @param step Years between the two observations of a transition (default
#'   `1`); keyed on the year, so a gap in a country's series gives no
#'   transition rather than a longer one.
#'
#' @return A tibble of `from`, `to`, `n` (transitions observed) and `p` (the
#'   probability of moving from `from` to `to`, `NA` for a class nothing left),
#'   with attributes `ergodic` (the steady-state share of countries in each
#'   class, if the chain ran on) and `first_passage` (the matrix of mean
#'   first-passage times, in steps).
#' @references
#' Quah, D. (1993). Empirical cross-section dynamics in economic growth.
#' *European Economic Review* 37(2-3), 426-434.
#' \doi{10.1016/0014-2921(93)90031-5}
#'
#' Quah, D. T. (1996). Twin peaks: growth and convergence in models of
#' distribution dynamics. *The Economic Journal* 106(437), 1045-1055.
#' \doi{10.2307/2235377}
#' @seealso [spatial_markov()], [rank_mobility()], [beta_convergence()],
#'   [sigma_convergence()], [convergence_club()]
#' @export
#' @examples
#' set.seed(1)
#' pan <- expand.grid(iso3c = c("FRA", "DEU", "BRA", "IND", "CHN", "NGA"),
#'                    year = 2000:2010, stringsAsFactors = FALSE)
#' pan$gdp <- exp(stats::rnorm(nrow(pan), 9, 1))
#' transition_matrix(pan, gdp, n_classes = 3)
transition_matrix <- function(data, value, n_classes = 5,
                              classes = c("quantile", "relative"), step = 1) {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  classes <- rlang::arg_match(classes)
  check_number(n_classes, "n_classes", lo = 2, hi = 50)
  check_number(step, "step", lo = 1, hi = 1000)
  n_classes <- as.integer(n_classes)
  df <- dynamics_panel(data, val_name)
  cl <- dynamics_classes(df, val_name, n_classes, classes)
  df$.wdj_class <- cl$class
  key <- paste(df$iso3c, df$year)
  nxt <- match(paste(df$iso3c, df$year + step), key)
  tt <- transition_table(df$.wdj_class, df$.wdj_class[nxt], n_classes)
  out <- as_transition_tibble(tt)
  # An empty frame has nothing to report: its empty table says so.
  if (!sum(out$n) && nrow(df)) {
    wdj_warn("No country has two observations {step} year{?s} apart, so there
              are no transitions.", class = "countryatlas_no_transitions")
  }
  pi <- if (sum(out$n)) ergodic_distribution(tt$p) else rep(NA_real_, n_classes)
  attr(out, "ergodic") <- pi
  attr(out, "first_passage") <- if (sum(out$n)) first_passage(replace(tt$p, is.na(tt$p), 0), pi) else
    matrix(NA_real_, n_classes, n_classes)
  attr(out, "classes") <- classes
  attr(out, "breaks") <- cl$breaks
  out
}

#' Markov transitions conditioned on the neighbours
#'
#' Rey's (2001) spatial Markov chain: one transition matrix for each class of
#' a country's spatial lag -- the average class of its neighbours -- so you can
#' ask whether a poor country among poor neighbours is less likely to move up
#' than one among rich neighbours. A homogeneity test says whether the
#' conditional matrices differ from the pooled one.
#'
#' @inheritParams transition_matrix
#' @param weights A [country_weights()] object; `NULL` (default) is k-nearest
#'   neighbours (k = 5), so islands take part.
#'
#' @return A tibble of `lag_class`, `from`, `to`, `n` and `p`, with the
#'   attribute `test`: a tibble of the likelihood-ratio and chi-square
#'   homogeneity statistics, their degrees of freedom and p-values
#'   (Bickenbach & Bode 2003), where cells with no transitions do not count
#'   toward the degrees of freedom (Kang & Rey 2018).
#' @references
#' Rey, S. J. (2001). Spatial empirics for economic growth and convergence.
#' *Geographical Analysis* 33(3), 195-214.
#' \doi{10.1111/j.1538-4632.2001.tb00444.x}
#'
#' Bickenbach, F. & Bode, E. (2003). Evaluating the Markov property in studies
#' of economic convergence. *International Regional Science Review* 26(3),
#' 363-392. \doi{10.1177/0160017603253789}
#'
#' Kang, W. & Rey, S. J. (2018). Conditional and joint tests for spatial
#' effects in discrete Markov chain models of regional income distribution
#' dynamics. *The Annals of Regional Science* 61(1), 73-93.
#' \doi{10.1007/s00168-017-0859-9}
#' @seealso [transition_matrix()], [spatial_lag()]
#' @export
#' @examples
#' \donttest{
#' set.seed(1)
#' iso <- countryatlas::world_snapshot$countries$iso3c
#' pan <- expand.grid(iso3c = iso, year = 2010:2015, stringsAsFactors = FALSE)
#' pan$v <- exp(stats::rnorm(nrow(pan)))
#' spatial_markov(pan, v, n_classes = 3)
#' }
spatial_markov <- function(data, value, weights = NULL, n_classes = 5,
                           classes = c("quantile", "relative"), step = 1) {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  classes <- rlang::arg_match(classes)
  check_number(n_classes, "n_classes", lo = 2, hi = 50)
  check_number(step, "step", lo = 1, hi = 1000)
  n_classes <- as.integer(n_classes)
  df <- dynamics_panel(data, val_name)
  # The neighbours' average value each year, then classified like the values.
  df$.wdj_lag <- NA_real_
  for (y in unique(df$year)) {
    k <- which(df$year == y & is.finite(df[[val_name]]))
    if (length(k) < 3L) next
    al <- tryCatch(suppressWarnings(align_weights(df[k, , drop = FALSE], val_name,
                                                  weights)),
                   error = function(e) NULL)
    if (is.null(al)) next
    lag <- as.numeric(al$m %*% al$x)
    df$.wdj_lag[k] <- lag[match(df$iso3c[k], al$iso3c)]
  }
  cl <- dynamics_classes(df, val_name, n_classes, classes)
  lc <- dynamics_classes(stats::setNames(df[, c("iso3c", "year", ".wdj_lag")],
                                         c("iso3c", "year", "v")),
                         "v", n_classes, classes)
  key <- paste(df$iso3c, df$year)
  nxt <- match(paste(df$iso3c, df$year + step), key)
  from <- cl$class
  to <- cl$class[nxt]
  # Only the transitions whose neighbourhood has a class, so the pooled matrix
  # and the conditional ones describe the same transitions.
  has_lag <- !is.na(lc$class)
  pooled <- transition_table(from[has_lag], to[has_lag], n_classes)
  parts <- lapply(seq_len(n_classes), function(l) {
    tt <- transition_table(from[lc$class %in% l], to[lc$class %in% l], n_classes)
    out <- as_transition_tibble(tt)
    out$lag_class <- l
    list(tbl = out, n = tt$n)
  })
  out <- dplyr::bind_rows(lapply(parts, `[[`, "tbl"))
  out <- out[, c("lag_class", "from", "to", "n", "p")]
  # Homogeneity (Bickenbach & Bode 2003): the conditional transition
  # probabilities against the pooled ones. For each starting class i, b_i
  # destinations have a positive pooled probability and a_i neighbourhood
  # classes left i at all; the statistic has sum (a_i - 1)(b_i - 1) degrees of
  # freedom, so empty cells do not count (Kang & Rey 2018).
  lr <- 0
  q <- 0
  df_test <- 0
  pp <- pooled$p
  for (i in seq_len(n_classes)) {
    pos <- which(pp[i, ] > 0)
    if (!length(pos)) next
    a_i <- 0
    for (l in seq_len(n_classes)) {
      nl <- parts[[l]]$n
      ni <- sum(nl[i, ])
      if (ni == 0) next
      a_i <- a_i + 1
      pl <- nl[i, ] / ni
      nz <- pos[nl[i, pos] > 0]
      lr <- lr + 2 * sum(nl[i, nz] * log(pl[nz] / pp[i, nz]))
      q <- q + sum(ni * (pl[pos] - pp[i, pos])^2 / pp[i, pos])
    }
    df_test <- df_test + max(a_i - 1, 0) * (length(pos) - 1)
  }
  attr(out, "test") <- tibble::tibble(
    statistic = c("LR", "Q"), value = c(lr, q), df = df_test,
    p_value = if (df_test > 0) stats::pchisq(c(lr, q), df_test, lower.tail = FALSE)
              else NA_real_)
  attr(out, "pooled") <- as_transition_tibble(pooled)
  out
}

#' How much did the ranking change?
#'
#' Kendall's tau between the ranks of two cross-sections, and the share of
#' countries that moved at least `k` places: a summary of mobility that
#' complements [transition_matrix()].
#'
#' @param data A panel with `iso3c`, `year` and the value column.
#' @param value The column to rank (unquoted).
#' @param from,to The two years to compare.
#' @param k The number of places that counts as moving (default `5`).
#'
#' @return A one-row tibble: `n` (countries with a value in both years),
#'   `tau` (Kendall's tau-b of the two rankings: 1 for an unchanged order),
#'   `p_value` (for tau = 0), and `share_moved` (the share of countries whose
#'   rank changed by `k` places or more), with the per-country ranks as the
#'   `"ranks"` attribute.
#' @seealso [transition_matrix()], [rank_countries()]
#' @export
#' @examples
#' set.seed(1)
#' pan <- expand.grid(iso3c = c("FRA", "DEU", "BRA", "IND", "CHN", "NGA"),
#'                    year = c(2000, 2010), stringsAsFactors = FALSE)
#' pan$gdp <- exp(stats::rnorm(nrow(pan), 9, 1))
#' rank_mobility(pan, gdp, from = 2000, to = 2010, k = 1)
rank_mobility <- function(data, value, from, to, k = 5) {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  check_number(from, "from")
  check_number(to, "to")
  check_number(k, "k", lo = 1)
  df <- dynamics_panel(data, val_name)
  a <- df[df$year == from & is.finite(df[[val_name]]), c("iso3c", val_name)]
  b <- df[df$year == to & is.finite(df[[val_name]]), c("iso3c", val_name)]
  both <- merge(a, b, by = "iso3c", suffixes = c("_from", "_to"))
  n <- nrow(both)
  if (n < 3L) {
    wdj_abort(c("Too few countries have {.field {val_name}} in both years.",
                "i" = "Got {n}; a rank comparison needs at least 3."))
  }
  r1 <- rank(-both[[paste0(val_name, "_from")]], ties.method = "average")
  r2 <- rank(-both[[paste0(val_name, "_to")]], ties.method = "average")
  ct <- suppressWarnings(stats::cor.test(r1, r2, method = "kendall", exact = FALSE))
  out <- tibble::tibble(n = n, tau = unname(ct$estimate),
                        p_value = ct$p.value,
                        share_moved = mean(abs(r2 - r1) >= k))
  attr(out, "ranks") <- tibble::tibble(iso3c = both$iso3c, rank_from = r1,
                                       rank_to = r2, change = r1 - r2)
  out
}
