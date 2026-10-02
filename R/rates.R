# Rates, denominators, deflation and convergence clubs ---------------------------
#
# per_capita() is where users hit the small-number problem: a rate computed over
# eleven thousand people gets exactly as much ink on a choropleth as one computed
# over a billion. value_by_alpha_map() and the cartograms are the *visual*
# answers; rate_check() and smooth_rates() are the statistical ones, and this is
# where they live alongside the deflation helpers that make a money series
# comparable across years at all.

#' Flag rates computed over tiny denominators
#'
#' The small-number problem, named: a rate over a very small population is mostly
#' noise, and on a map it shouts as loudly as a rate over a very large one. This
#' reports which countries' rates you should not trust before you plot them.
#'
#' @param data A country-level frame.
#' @param numerator,denominator The count and the population it is over
#'   (unquoted).
#' @param min_denominator Denominators below this are flagged. `NULL` (default)
#'   uses the 10th percentile of the observed denominators, which adapts to the
#'   data rather than imposing a threshold that suits one indicator.
#' @param rate An existing rate column (unquoted), if you already computed it.
#'   Otherwise the rate is `numerator / denominator`.
#'
#' @return A tibble of `iso3c`, `numerator`, `denominator`, `rate`,
#'   `expected_se` (the Poisson standard error of the rate, \eqn{\sqrt{r/d}};
#'   `NA`, with a warning, for a negative rate) and `flagged`, sorted with the
#'   least reliable first.
#'
#'   "Least reliable" is ordered on the standard error a *single* event would
#'   imply, \eqn{\sqrt{\max(y, 1)}/d}, which is identical to `expected_se` for
#'   every row with at least one event. Ordering on `expected_se` directly put
#'   zero-count rows last, at the reliable end: it is \eqn{\sqrt{y}/d}, which
#'   is exactly `0` when the count is `0`, so one country with no events out of
#'   251 people outranked another with one event out of the same 251. Observing
#'   nothing is not evidence of precision. `expected_se` itself is still the
#'   plain Poisson standard error, `0` and all.
#'
#'   `flagged` is `TRUE` for a
#'   denominator below the threshold, `FALSE` above it or missing, and `NA` for
#'   every row when no threshold could be computed at all -- which is warned
#'   about, and means `sum(flagged)` is `NA` rather than a misleading `0`.
#'
#' @section What to do about it:
#' Three answers, in rough order of preference: [smooth_rates()] shrinks the
#' unreliable rates toward the global rate; [value_by_alpha_map()] leaves them
#' alone but fades them out; or drop them and say so in the caption. Plotting
#' them raw and unremarked is the one option that misleads.
#'
#' @references
#' Roth, R. E., Woodruff, A. W. & Johnson, Z. F. (2010). Value-by-alpha maps: an
#' alternative technique to the cartogram. *The Cartographic Journal* 47(2),
#' 130-140. \doi{10.1179/000870409X12488753453372}
#'
#' @seealso [smooth_rates()], [per_capita()], [value_by_alpha_map()]
#' @export
#' @examples
#' d <- data.frame(
#'   iso3c = c("CHN", "IND", "TUV", "NRU"),
#'   cases = c(50000, 42000, 3, 1),
#'   pop   = c(1.41e9, 1.39e9, 11000, 12000)
#' )
#' rate_check(d, cases, pop)
rate_check <- function(data, numerator, denominator, min_denominator = NULL,
                       rate = NULL) {
  num_name <- quo_arg_name(rlang::enquo(numerator), "numerator")
  den_name <- quo_arg_name(rlang::enquo(denominator), "denominator")
  rate_q <- rlang::enquo(rate)
  check_cols(data, c(num_name, den_name))
  check_numeric_col(data, num_name)
  check_numeric_col(data, den_name)
  if (!is.null(min_denominator)) {
    check_number(min_denominator, "min_denominator", lo = 0)
  }
  df <- distinct_countries(tibble::as_tibble(sf_drop(data)))
  num <- df[[num_name]]
  den <- df[[den_name]]
  r <- if (rlang::quo_is_null(rate_q)) {
    num_ifelse(is.finite(den) & den > 0, num / den)
  } else {
    rate_name <- quo_arg_name(rate_q, "rate")
    check_cols(df, rate_name)
    # The numerator and denominator are both checked; the rate that replaces
    # their ratio was not, so a character column went into the table as the
    # `rate` and every expected_se came back NA without a word.
    check_numeric_col(df, rate_name)
    df[[rate_name]]
  }
  thr <- min_denominator %||% stats::quantile(den[is.finite(den) & den > 0],
                                              0.10, na.rm = TRUE, names = FALSE)
  # With no positive finite denominator anywhere, quantile() returns NA and the
  # comparison below yields an all-NA `flagged` column -- so sum(out$flagged),
  # the obvious next step, is NA rather than a count. Say why once.
  #
  # nrow() first, the same guard smooth_rates() and to_ppp() carry: quantile()
  # of an empty vector is also NA, so a zero-row frame was told it had no
  # usable denominator rather than simply having no rows. There is nothing to
  # warn about in a frame with nothing in it.
  if (nrow(df) && !is.finite(thr)) {
    wdj_warn(c(
      "No usable {.arg denominator}, so no small-denominator threshold could be
       computed.",
      "i" = "{.field flagged} is {.val {NA}} throughout, and every rate is
             {.val {NA}} for the same reason."
    ))
  }
  out <- tibble::tibble(
    iso3c = df$iso3c %||% rep(NA_character_, nrow(df)),
    numerator = num, denominator = den, rate = r,
    # Poisson SE of a rate: the count's variance is its mean, so the rate's SE
    # is sqrt(rate / denominator). It is the compact statement of why a small
    # denominator is untrustworthy.
    #
    # NA, not 0, for a negative rate. pmax(r, 0) turned one into an SE of
    # exactly 0 -- the most precise-looking value the column can hold -- for
    # a count the Poisson model has no meaning for at all.
    # pmax() still inside: ifelse() evaluates the whole `yes` vector, so a
    # bare sqrt() of the negative rows leaked base R's "NaNs produced".
    expected_se = num_ifelse(is.finite(r) & r >= 0 & is.finite(den) & den > 0,
                             sqrt(pmax(r, 0) / den)),
    # `is.finite(den) & den < thr` yields FALSE, not NA, for a non-finite
    # denominator, because R short-circuits `FALSE & NA` to FALSE. With *no*
    # computable threshold that turned the whole column into a confident
    # "nothing is flagged": an all-NA denominator gave FALSE throughout, so
    # sum(out$flagged) returned 0 rather than NA -- the exact misreading the
    # warning above exists to prevent, and it also made that warning's promise
    # ("flagged is NA throughout") untrue. An all-zero or all-negative
    # denominator did give NA, so the two cases disagreed with each other too.
    # No threshold means no row can be compared to one, so say NA for all of
    # them. The normal path -- a finite threshold -- is untouched, including
    # its FALSE for a missing denominator, which keeps sum(out$flagged)
    # working as the comment above intends.
    flagged = if (!is.finite(thr)) rep(NA, length(den)) else {
      is.finite(den) & den < thr
    }
  )
  attr(out, "min_denominator") <- thr
  n_neg <- sum(is.finite(r) & r < 0)
  if (n_neg) {
    wdj_warn(c(
      "{n_neg} rate{?s} {?is/are} negative, so {.field expected_se} is
       {.val {NA}} there.",
      "i" = "The Poisson standard error describes a count, and a count cannot
             be negative."
    ), class = "countryatlas_negative_count")
  }
  # Order on the SE a *single* event would imply, not on expected_se itself.
  # expected_se is sqrt(y)/d, which collapses to exactly 0 when the count is
  # 0 -- so in a table documented as "least reliable first", a country with 0
  # events out of 251 sorted last, presented as the most reliable row on the
  # page, while another country with 1 event out of the same 251 sorted first
  # as the least. Zero events is not evidence of precision; it is the
  # small-number problem this verb exists to name. pmax(num, 1) is identical
  # to expected_se for every row with at least one event, so nothing else in
  # the table moves, and expected_se itself stays exactly the documented
  # Poisson SE.
  ord <- num_ifelse(is.finite(num) & is.finite(den) & den > 0,
                    sqrt(pmax(num, 1)) / den)
  dplyr::arrange(out, dplyr::desc(ord))
}

#' Shrink unreliable rates toward the global rate
#'
#' Empirical-Bayes smoothing: a rate computed over a small denominator is pulled
#' toward the overall rate in proportion to how little information stands behind
#' it, while a rate over a large denominator is left essentially alone. Standard
#' practice in disease mapping, and the statistical counterpart to
#' [value_by_alpha_map()]'s visual answer.
#'
#' @param data A country-level frame.
#' @param numerator,denominator The count and its denominator (unquoted).
#' @param method `"eb"` (default) shrinks each rate toward the global rate;
#'   `"local_eb"` toward its neighbourhood's -- its own and its neighbours'
#'   pooled rate -- so a rate is compared with the places around it rather
#'   than the whole world (Marshall 1991; Anselin, Lozano & Koschinsky 2006);
#'   `"none"` computes the raw rate only.
#' @param suffix Suffix for the new columns (default `"_smoothed"`).
#' @param weights For `"local_eb"`: who a country's neighbours are, as a
#'   [country_weights()] object; `NULL` (default) is k-nearest neighbours
#'   (k = 5). A country with no usable neighbour has no neighbourhood rate,
#'   so it is `NA`, with a warning.
#'
#' @return `data` with `<numerator>_rate` and `<numerator>_smoothed` columns
#'   added, plus `<numerator>_shrinkage` -- the weight given to the country's own
#'   rate, between 0 (fully shrunk to the global rate) and 1 (untouched). A row
#'   with no finite, positive denominator or with a negative count has no rate:
#'   all three are `NA` there, with a warning.
#'
#' @section The model:
#' A Poisson-gamma model: counts \eqn{y_i \sim \mathrm{Poisson}(d_i \theta_i)}
#' with \eqn{\theta_i \sim \mathrm{Gamma}}, whose mean and variance are estimated
#' from the data by the method of moments. The posterior mean is
#' \eqn{w_i r_i + (1 - w_i)\bar{r}} with \eqn{w_i = d_i / (d_i + \alpha)}, so the
#' shrinkage weight is exactly the "how much do we believe this country"
#' quantity that `rate_check()` flags. Where the between-country variance is
#' estimated as non-positive (rates no more dispersed than Poisson noise alone),
#' every rate shrinks fully to the global mean, which is the right answer:
#' the data contain no evidence of real between-country variation.
#'
#' On a panel the prior is estimated separately for each `year`, so every
#' rate is shrunk toward its own year's global rate and every row is kept.
#'
#' `"local_eb"` estimates the same two moments in each country's neighbourhood
#' (itself and its neighbours): the local rate \eqn{m_i} and the local
#' between-country variance \eqn{a_i}, computed from the deviations of the
#' neighbourhood's rates from \eqn{m_i}. It agrees with
#' `spdep::EBlocal(geoda = TRUE)` on the same neighbours.
#'
#' @references
#' Marshall, R. J. (1991). Mapping disease and mortality rates using empirical
#' Bayes estimators. *Journal of the Royal Statistical Society, Series C*
#' 40(2), 283-294. \doi{10.2307/2347593}
#'
#' Anselin, L., Lozano, N. & Koschinsky, J. (2006). Rate transformations and
#' smoothing. Spatial Analysis Laboratory, University of Illinois.
#'
#' @seealso [rate_check()], [per_capita()], [value_by_alpha_map()]
#' @export
#' @examples
#' d <- data.frame(
#'   iso3c = c("CHN", "IND", "TUV", "NRU"),
#'   cases = c(50000, 42000, 3, 1),
#'   pop   = c(1.41e9, 1.39e9, 11000, 12000)
#' )
#' smooth_rates(d, cases, pop)
smooth_rates <- function(data, numerator, denominator,
                         method = c("eb", "local_eb", "none"),
                         suffix = "_smoothed", weights = NULL) {
  method <- rlang::arg_match(method)
  check_string(suffix, "suffix")
  num_name <- quo_arg_name(rlang::enquo(numerator), "numerator")
  den_name <- quo_arg_name(rlang::enquo(denominator), "denominator")
  check_cols(data, c(num_name, den_name))
  check_numeric_col(data, num_name)
  check_numeric_col(data, den_name)

  num <- data[[num_name]]
  den <- data[[den_name]]
  # A count cannot be negative, and the Poisson-gamma model below is defined
  # only for counts: one negative numerator drove the pooled rate and the
  # excess variance off their domain, and on a three-country frame every
  # `_shrinkage` came back 1.03 -- outside the [0, 1] the help promises -- so
  # every rate was pushed *away* from the global one. Such a row is as
  # unusable as one with no denominator, and is reported beside it.
  neg <- is.finite(num) & num < 0
  bad_den <- !(is.finite(den) & den > 0)
  ok <- is.finite(num) & !bad_den & !neg
  raw <- num_ifelse(ok, num / den)

  rate_col <- paste0(num_name, "_rate")
  sm_col <- paste0(num_name, suffix)
  sh_col <- paste0(num_name, "_shrinkage")
  warn_overwrite(data, c(rate_col, sm_col, sh_col))
  # Same silence rate_check() used to have: with no usable denominator every
  # rate is NA, so the smoothed column is NA too and the result looks like a
  # computation that ran rather than one with nothing to work with.
  # length() first: !any(logical(0)) is TRUE, so a zero-row frame was told
  # it had nothing usable rather than simply having nothing.
  #
  # Counted on the denominator alone. The count was `!ok`, which also took in
  # every row whose *numerator* was missing, so "3 rows have no finite,
  # positive pop" could describe rows whose pop was fine. A missing count is
  # missing data and gives an NA rate on its own, as NA does anywhere.
  if (length(bad_den) && all(bad_den)) {
    wdj_warn(c(
      "No usable {.arg denominator}, so there are no rates to smooth.",
      "i" = "A rate needs a finite, positive denominator; {.field {rate_col}}
             and {.field {sm_col}} are {.val {NA}} throughout."
    ), class = "countryatlas_no_rates")
  } else if (any(bad_den)) {
    wdj_warn(c(
      "{sum(bad_den)} row{?s} ha{?s/ve} no finite, positive
       {.field {den_name}}, so the rate there is {.val {NA}}.",
      "i" = "Those rows take no part in the smoothing either."
    ), class = "countryatlas_unusable_rows")
  }
  if (any(neg & !bad_den)) {
    wdj_warn(c(
      "{sum(neg & !bad_den)} row{?s} ha{?s/ve} a negative {.field {num_name}},
       so the rate there is {.val {NA}}.",
      "i" = "A rate is a count over a denominator, and a count cannot be
             negative; those rows take no part in the smoothing."
    ), class = "countryatlas_negative_count")
  }
  data[[rate_col]] <- raw

  if (identical(method, "none") || sum(ok) < 2L) {
    data[[sm_col]] <- raw
    data[[sh_col]] <- num_ifelse(ok, 1)
    # Normalised here too, not only on the smoothing path below: this early
    # return handed back whatever class arrived, so `method = "none"` leaked an
    # incoming grouping and returned a bare data.frame where every other mode
    # of the same function returns a tibble.
    return(wdj_return_frame(data))
  }

  # Method-of-moments Poisson-gamma (Marshall 1991): the global rate is the
  # pooled one, and the between-country variance is the excess over what Poisson
  # sampling alone would produce.
  #
  # One prior per year on a panel. The prior is a cross-sectional quantity
  # (this year's global rate and this year's between-country variance), and it
  # used to be estimated from the earliest year alone and then applied to every
  # row, so each later year was shrunk toward the wrong global rate, under a
  # warning that said the other years were "dropped" when every row came back.
  # This is spatial_lag()'s design for the same shape: a statistic per year,
  # every row kept, nothing to announce. A frame with one year (or none) is a
  # single period, as before.
  period <- if ("year" %in% names(data) &&
                length(unique(stats::na.omit(data$year))) > 1L) {
    ifelse(is.na(data$year), "\rNA", as.character(data$year))
  } else {
    rep("", nrow(data))
  }
  sm <- rep(NA_real_, length(raw))
  shr <- rep(NA_real_, length(raw))
  if (identical(method, "local_eb")) {
    lost <- character(0)
    for (p in unique(period[ok])) {
      rows <- which(ok & period == p)
      le <- local_eb(data[rows, , drop = FALSE], num_name, den_name, weights)
      sm[rows] <- le$smoothed
      shr[rows] <- le$shrinkage
      lost <- union(lost, le$lost)
    }
    if (length(lost)) {
      wdj_warn(c(
        "{length(lost)} countr{?y/ies} ha{?s/ve} no neighbour with a usable
         rate, so there is no neighbourhood to shrink toward:",
        "*" = "{.val {utils::head(sort(lost), 8)}}",
        "i" = "{.field {sm_col}} is {.val {NA}} there; {.code method = \"eb\"}
               shrinks toward the global rate instead."
      ), class = "countryatlas_no_neighbours")
    }
    data[[sm_col]] <- sm
    data[[sh_col]] <- shr
    return(wdj_return_frame(data))
  }
  for (p in unique(period[ok])) {
    rows <- ok & period == p
    prior <- eb_prior(data[period == p, , drop = FALSE], num_name, den_name,
                      fallback = list(y = num[rows], d = den[rows]))
    d <- den[rows]; r <- num[rows] / d
    w <- rep(0, length(r))
    if (is.finite(prior$phi) && prior$phi > 0) {
      w <- d / (d + prior$rbar / prior$phi)
    }
    sm[rows] <- w * r + (1 - w) * prior$rbar
    shr[rows] <- w
  }
  data[[sm_col]] <- sm
  data[[sh_col]] <- shr
  # Was a bare `data`, so this verb handed back whatever class arrived: a
  # grouped frame stayed grouped, and the caller's next mutate() then computed
  # per-group without asking. The eleven sibling verbs all normalise here.
  wdj_return_frame(data)
}

# Local empirical Bayes for one period's usable rows: each country's rate
# shrunk toward its neighbourhood's (itself and its neighbours), with Marshall's
# (1991) local moments -- the deviations are from the neighbourhood's own rate,
# GeoDa's form, which spdep::EBlocal(geoda = TRUE) computes. Row-aligned with
# `frame`; a country the weights give no usable neighbour is NA.
local_eb <- function(frame, num_name, den_name, weights) {
  frame$.wdj_rate <- frame[[num_name]] / frame[[den_name]]
  one <- distinct_countries(tibble::as_tibble(sf_drop(frame)))
  al <- suppressWarnings(align_weights(one, ".wdj_rate", weights))
  keep <- al$iso3c
  b <- (al$weights$m[keep, keep, drop = FALSE] > 0) * 1
  diag(b) <- 1
  at <- match(keep, one$iso3c)
  y <- one[[num_name]][at]
  x <- one[[den_name]][at]
  p <- y / x
  r_i <- as.numeric(b %*% y)
  n_i <- as.numeric(b %*% x)
  nbar <- n_i / rowSums(b)
  m_i <- r_i / n_i
  dev <- vapply(seq_along(keep), function(i) {
    j <- which(b[i, ] > 0)
    sum(x[j] * (p[j] - m_i[i])^2)
  }, numeric(1))
  a_i <- pmax(dev / n_i - m_i / nbar, 0)
  denom <- a_i + m_i / x
  w <- ifelse(denom > 0, a_i / denom, 0)
  est <- m_i + (p - m_i) * w
  idx <- match(frame$iso3c, keep)
  list(smoothed = est[idx], shrinkage = w[idx],
       lost = setdiff(unique(stats::na.omit(frame$iso3c)), keep))
}

# The empirical-Bayes hyperparameters for one period: the pooled rate `rbar`
# and the excess variance `phi`.
#
# Estimated from one row per country, the way rate_check() reads its input,
# while the shrinkage is applied to every row so the returned frame keeps its
# shape. Estimating from the raw rows weighted each country by its row count:
# on a geometry-attached frame (about 99,000 vertex rows) every country
# entered `rbar`, `dbar` and `s2` once per polygon vertex, so the prior was
# weighted by coastline complexity and every shrinkage weight was wrong.
eb_prior <- function(frame, num_name, den_name, fallback) {
  pooled <- if ("iso3c" %in% names(frame)) {
    pd <- distinct_countries(tibble::as_tibble(sf_drop(frame)))
    # The same rows smooth_rates() calls usable, negative counts out: this
    # filter was its own copy, so a negative numerator the caller had been
    # told takes "no part in the smoothing" still set the prior.
    pok <- is.finite(pd[[num_name]]) & pd[[num_name]] >= 0 &
      is.finite(pd[[den_name]]) & pd[[den_name]] > 0
    list(y = pd[[num_name]][pok], d = pd[[den_name]][pok])
  } else {
    fallback
  }
  if (!length(pooled$d)) pooled <- fallback
  py <- pooled$y; pd_ <- pooled$d; pr <- py / pd_
  rbar <- sum(py) / sum(pd_)
  s2 <- sum(pd_ * (pr - rbar)^2) / sum(pd_)
  list(rbar = rbar, phi = s2 - rbar / mean(pd_))
}

#' Convert a money series to constant prices
#'
#' A nominal series is not comparable across years. `deflate()` divides by a
#' price index rebased to `base_year`, turning current-price values into constant
#' `base_year` prices.
#'
#' @param data A panel with `iso3c`, `year` and the value column.
#' @param value The nominal value column (unquoted).
#' @param base_year The year whose prices to express everything in.
#' @param deflator Either a column in `data` holding the price index (unquoted),
#'   or `NULL` to fetch the World Bank GDP deflator (`NY.GDP.DEFL.ZS`) for the
#'   countries and years present. Fetching needs the network.
#' @param suffix Suffix for the new column (default `"_real"`).
#'
#' @return `data` with the constant-price column added.
#'
#' @section Which deflator:
#' The GDP deflator is the right default for aggregate output. For household
#' spending the CPI (`FP.CPI.TOTL`) is usually preferred, and for cross-country
#' *level* comparisons a deflator is not enough at all -- you want
#' [to_ppp()] as well, because exchange rates do not equalise purchasing power.
#' Deflating and converting to PPP are different corrections for different
#' problems, and a cross-country panel over time generally needs both.
#'
#' @seealso [to_ppp()], [per_capita()], [index_to()]
#' @export
#' @examples
#' d <- data.frame(iso3c = "USA", year = 2000:2002,
#'                 gdp = c(100, 110, 120), defl = c(90, 100, 105))
#' deflate(d, gdp, base_year = 2001, deflator = defl)
deflate <- function(data, value, base_year, deflator = NULL,
                    suffix = "_real") {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  defl_q <- rlang::enquo(deflator)
  check_string(suffix, "suffix")
  check_panel_cols(data, val_name)
  # The deflator column was checked for a number and the value it divides was
  # not, so a character value column reached the division inside mutate() and
  # surfaced as dplyr's "non-numeric argument to binary operator" wrapped in
  # "In group 1: `.wdj_unit = ...`", naming an internal key, not the column.
  check_numeric_col(data, val_name)
  # to_ppp() and smooth_rates(), the two verbs shaped exactly like this one,
  # both announce it before they clobber a column the caller already had.
  # deflate() wrote over it in silence.
  warn_overwrite(data, paste0(val_name, suffix))
  # deflate() joins the deflator on `year`, and a character year made dplyr
  # refuse with "Can't join `x$year` with `y$year` due to incompatible types"
  # -- an internal join the caller never asked for, named in place of their
  # column. Same guard complete_years() uses.
  check_numeric_col(data, "year")
  if (missing(base_year)) wdj_abort("{.arg base_year} is required.")
  # read_year(), not as.integer(): a Date became its day count, so
  # base_year = as.Date("2001-01-01") was reported back as
  # "`base_year` 11323 is not in year" -- a number the caller never supplied.
  shown <- paste(format(base_year), collapse = ", ")
  base_year <- suppressWarnings(read_year(base_year, "{.arg base_year}"))
  if (length(base_year) != 1L || is.na(base_year)) {
    wdj_abort(c(
      "{.arg base_year} must be a single year.",
      "x" = "Got {.val {shown}}."
    ))
  }
  # A zero-row panel has nothing to rebase, and every downstream step
  # misbehaved on it: the guard below aborted (nothing is `%in%` an empty
  # vector) while reporting "Years present: Inf and -Inf" from range() of
  # nothing, and the fetching branch would have asked the World Bank for the
  # range Inf..-Inf. Return early with the promised column, typed -- the
  # contract complete_years() and world_table() already follow.
  if (!nrow(data)) {
    data[[paste0(val_name, suffix)]] <- numeric(0)
    return(wdj_return_frame(data))
  }
  if (!base_year %in% data$year) {
    wdj_abort(c(
      "{.arg base_year} {.val {base_year}} is not in {.field year}.",
      "i" = "Years present: {.val {range(data$year, na.rm = TRUE)}}."
    ))
  }

  if (rlang::quo_is_null(defl_q)) {
    # Same collision per_capita() guards against: a caller's own `.wdj_defl`
    # column makes dplyr suffix both sides of the join to `.x`/`.y`, so
    # `data[[".wdj_defl"]]` comes back NULL and the arithmetic below fails on a
    # column that is not there. The fetched deflator is what this branch is
    # for, and the column is dropped again before returning either way.
    data[[".wdj_defl"]] <- NULL
    idx <- fetch_wdi(c(.wdj_defl = "NY.GDP.DEFL.ZS"),
                     start = min(data$year, na.rm = TRUE),
                     end = max(data$year, na.rm = TRUE))
    data <- dplyr::left_join(data, one_per_key(idx[, c("iso3c", "year", ".wdj_defl")]),
                             by = c("iso3c", "year"), na_matches = "never",
                             relationship = "many-to-one")
    defl_name <- ".wdj_defl"
    # The index is fetched for `year`; a value recorded as coming from
    # another year is deflated with the wrong year's prices.
    warn_mixed_years(data, val_name, "the deflator", yb = "year",
                     what = "deflate")
  } else {
    defl_name <- quo_arg_name(defl_q, "deflator")
    check_cols(data, defl_name)
    check_numeric_col(data, defl_name)
    warn_mixed_years(data, val_name, defl_name, what = "deflate")
  }

  # A country with no usable deflator in base_year has nothing to rebase
  # against, so every one of its values comes back NA -- which in the output is
  # indistinguishable from a country the source had no data for at all. The
  # arithmetic is right; the silence is not.
  no_base <- units_without_base(data, defl_name, base_year)
  if (length(no_base)) {
    wdj_warn(c(
      "{length(no_base)} countr{?y/ies} ha{?s/ve} no usable {base_year}
       deflator; the rebased values are all {.val {NA}}:",
      "*" = "{.val {utils::head(sort(unique(no_base)), 8)}}",
      "i" = "Choose a {.arg base_year} the panel covers, or drop those
             countries first."
    ))
  }

  # Rebase per country: the index's own base year is arbitrary and differs
  # between countries, so only the ratio to that country's base-year value is
  # meaningful.
  out <- data %>%
    group_by_unit() %>%
    dplyr::mutate(
      .wdj_base = .data[[defl_name]][match(base_year, .data$year)],
      # A zero (or non-finite) index divides to Inf, which then propagates
      # silently into every scale and summary downstream. An unusable deflator
      # means the value cannot be expressed in constant prices -- that is NA.
      "{val_name}{suffix}" := ifelse(
        is.finite(.data[[defl_name]]) & .data[[defl_name]] != 0 &
          is.finite(.data$.wdj_base) & .data$.wdj_base != 0,
        .data[[val_name]] / (.data[[defl_name]] / .data$.wdj_base),
        NA_real_)
    ) %>%
    dplyr::ungroup()
  # The same unusable index in any other year gives NA for that row, which was
  # silent where to_ppp() and per_capita() report it. Only rows whose country
  # has a base: the countries named above are NA throughout, and said so.
  new <- paste0(val_name, suffix)
  unusable <- is.finite(out$.wdj_base) & out$.wdj_base != 0 &
    !(is.finite(out[[defl_name]]) & out[[defl_name]] != 0)
  if (any(unusable)) {
    wdj_warn(c(
      if (rlang::quo_is_null(defl_q)) {
        "{sum(unusable)} row{?s} ha{?s/ve} no usable World Bank deflator, so
         {.field {new}} is {.val {NA}} there."
      } else {
        "{sum(unusable)} row{?s} ha{?s/ve} no usable {.field {defl_name}}, so
         {.field {new}} is {.val {NA}} there."
      },
      "i" = "A zero, infinite or missing index cannot rebase a value."
    ), class = "countryatlas_unusable_rows")
  }
  out$.wdj_base <- NULL
  # group_by_unit() rather than iso3c: the base-year deflator is read from
  # within the group, so two rows whose iso3c did not resolve were rebased
  # against each other. deflate() does not route through wdj_return_frame(),
  # so the key is dropped here. The warning above keys on the same unit, and
  # names each one by its code or, lacking one, by what identifies it.
  out$.wdj_unit <- NULL
  if (rlang::quo_is_null(defl_q)) out$.wdj_defl <- NULL
  out
}

#' Convert to purchasing-power-parity terms
#'
#' Market exchange rates do not equalise what money buys. `to_ppp()` divides a
#' local-currency series by the PPP conversion factor, putting every country on
#' comparable international dollars -- the correction that makes a cross-country
#' *level* comparison meaningful.
#'
#' @param data A panel with `iso3c`, `year` and the value column.
#' @param value The local-currency value column (unquoted).
#' @param factor Either a column holding the PPP conversion factor (unquoted),
#'   or `NULL` to fetch the World Bank's (`PA.NUS.PPP`). Fetching needs the
#'   network.
#' @param suffix Suffix for the new column (default `"_ppp"`).
#'
#' @return `data` with the PPP-converted column added.
#' @seealso [deflate()], [per_capita()]
#' @export
#' @examples
#' d <- data.frame(iso3c = c("IND", "USA"), year = 2020L,
#'                 gdp_lcu = c(1e5, 1e4), ppp = c(21.9, 1))
#' to_ppp(d, gdp_lcu, factor = ppp)
to_ppp <- function(data, value, factor = NULL, suffix = "_ppp") {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  fac_q <- rlang::enquo(factor)
  check_string(suffix, "suffix")
  check_panel_cols(data, val_name)
  # As in deflate(): the factor was checked and the value it divides was not,
  # so a character column died on base R's bare "non-numeric argument to
  # binary operator".
  check_numeric_col(data, val_name)

  if (rlang::quo_is_null(fac_q)) {
    # The fetched factor is joined on `year`, so a character year failed on
    # dplyr's "Can't join `x$year` with `y$year` due to incompatible types"
    # after the download; deflate() guards the same join. A factor column of
    # the caller's own needs no join and keeps accepting such a year.
    check_numeric_col(data, "year")
    # As in deflate() and per_capita(): drop a caller's colliding column so the
    # join cannot suffix the fetched one out of reach.
    data[[".wdj_ppp"]] <- NULL
    idx <- fetch_wdi(c(.wdj_ppp = "PA.NUS.PPP"),
                     start = min(data$year, na.rm = TRUE),
                     end = max(data$year, na.rm = TRUE))
    data <- dplyr::left_join(data, one_per_key(idx[, c("iso3c", "year", ".wdj_ppp")]),
                             by = c("iso3c", "year"), na_matches = "never",
                             relationship = "many-to-one")
    fac_name <- ".wdj_ppp"
    warn_mixed_years(data, val_name, "the PPP factor", yb = "year",
                     what = "convert")
  } else {
    fac_name <- quo_arg_name(fac_q, "factor")
    check_cols(data, fac_name)
    check_numeric_col(data, fac_name)
    warn_mixed_years(data, val_name, fac_name, what = "convert")
  }
  fac <- data[[fac_name]]
  new <- paste0(val_name, suffix)
  warn_overwrite(data, new)
  usable <- is.finite(fac) & fac > 0
  # Zero, negative and NA factors all yield NA here, which is right but was
  # silent: a bad factor column produced a mostly-empty result that looked
  # like a conversion had happened.
  # length() first: !any(logical(0)) is TRUE, so a zero-row frame was told
  # it had nothing usable rather than simply having nothing.
  if (length(usable) && !any(usable)) {
    wdj_warn(c(
      "No usable {.field {fac_name}}, so nothing could be converted.",
      "i" = "A conversion factor must be finite and positive;
             {.field {new}} is {.val {NA}} throughout."
    ), class = "countryatlas_no_rates")
  } else if (any(!usable)) {
    wdj_warn(c(
      "{sum(!usable)} row{?s} ha{?s/ve} no finite, positive
       {.field {fac_name}}, so {.field {new}} is {.val {NA}} there.",
      "i" = "Zero, negative and {.val {NA}} factors are all unusable."
    ), class = "countryatlas_unusable_rows")
  }
  data[[new]] <- num_ifelse(usable, data[[val_name]] / fac)
  if (rlang::quo_is_null(fac_q)) data$.wdj_ppp <- NULL
  # As in smooth_rates(): a bare `data` leaked an incoming grouping out.
  wdj_return_frame(data)
}

#' Convergence clubs
#'
#' Countries do not all converge to one steady state; they converge in groups.
#' This implements the Phillips-Sul (2007) log-t procedure: a regression test for
#' whether a set of countries is converging, applied iteratively to peel off
#' clubs that converge internally even when the whole sample does not.
#'
#' @param data A panel with `iso3c`, `year` and the value column.
#' @param value The value column (unquoted); usually income per head.
#' @param min_size Smallest club to report (default `2`). Countries left over
#'   are returned as club `NA`.
#' @param alpha Significance level for the one-sided log-t test (default
#'   `0.05`; the critical value is \eqn{-1.65}).
#'
#' @return A tibble: `iso3c`, `club` (an integer, 1 = highest-level club, `NA` =
#'   not classified), and the club's `log_t` statistic. The per-club test results
#'   are attached as the `"countryatlas_clubs"` attribute. Every country in
#'   `data` appears: one without a complete series (a missing or non-finite
#'   value in any year) cannot be tested, so it comes back with `club = NA` and
#'   a warning naming it.
#'
#' @section The test:
#' For each country form the relative transition path
#' \eqn{h_{it} = y_{it} / \bar{y}_t}, then regress
#' \eqn{\log(H_1/H_t) - 2\log(\log t)} on \eqn{\log t} over the last part of the
#' sample, where \eqn{H_t} is the cross-sectional mean of
#' \eqn{(h_{it}-1)^2}. The one-sided *t* statistic on \eqn{\log t} is the log-t
#' statistic: above \eqn{-1.65} the group is converging. Clubs are then formed by
#' sorting countries on their final-period value and growing a core group while
#' the test still passes.
#'
#' A panel needs a reasonable number of periods for this to mean anything --
#' below roughly fifteen the test has very little power, and the function warns.
#'
#' @references
#' Phillips, P. C. B. & Sul, D. (2007). Transition modeling and econometric
#' convergence tests. *Econometrica* 75(6), 1771-1855.
#' \doi{10.1111/j.1468-0262.2007.00811.x}
#'
#' @seealso [beta_convergence()], [sigma_convergence()]
#' @export
#' @examples
#' set.seed(1)
#' # two groups converging to different levels
#' panel <- expand.grid(iso3c = c(paste0("A", 1:5), paste0("B", 1:5)),
#'                      year = 2000:2024)
#' panel$y <- ifelse(startsWith(as.character(panel$iso3c), "A"), 100, 30) +
#'   rnorm(nrow(panel), 0, 2)
#' convergence_club(panel, y)
convergence_club <- function(data, value, min_size = 2, alpha = 0.05) {
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  check_panel_cols(data, val_name)
  # A non-numeric value column fell through to "Not enough countries with a
  # complete series to form clubs", which sends the reader to look at their
  # panel's coverage rather than the column's type.
  check_numeric_col(data, val_name)
  # hi: as.integer() below returns NA past 2^31-1, which makes every
  # group-size comparison NA rather than FALSE.
  check_number(min_size, "min_size", lo = 2, hi = .Machine$integer.max)
  check_number(alpha, "alpha", lo = 0, hi = 1)
  min_size <- as.integer(min_size)

  df <- tibble::as_tibble(sf_drop(data))[, c("iso3c", "year", val_name)]
  # Every country the caller supplied, before the filters below. The log-t test
  # needs a balanced panel, so a country with even one missing or non-finite
  # year cannot be classified -- but it used to vanish from the result
  # altogether, while `club = NA` is documented as "not classified" and the
  # help promises leftovers come back that way. The same panel with one gap in
  # one country returned nine rows for ten countries and said nothing.
  all_iso <- unique(as.character(df$iso3c[!is.na(df$iso3c)]))
  df <- df[!is.na(df$iso3c) & !is.na(df$year) & is.finite(df[[val_name]]), ]
  # pivot_wider() collapses a repeated country-year into a list-column, and the
  # as.matrix() below then died with base R's "invalid 'type' (list) of
  # argument" -- a bare simpleError naming neither this verb nor the rows that
  # caused it. check_panel_cols() above already warns about the shape, but for
  # the log-t test it is fatal rather than merely inaccurate, so stop here and
  # say which rows to fix.
  key <- df[, c("iso3c", "year")]
  dupes <- unique(key[duplicated(key), , drop = FALSE])
  if (nrow(dupes)) {
    wdj_abort(c(
      "Cannot form clubs: {.arg data} has {nrow(dupes)} repeated country-year{?s}.",
      "*" = "{.val {utils::head(paste(dupes$iso3c, dupes$year), 8)}}",
      "i" = "The log-t test needs one row per country per year; collapse or drop
             the duplicates first. {.fn check_panel_unique} lists them."
    ))
  }
  # Chronological columns, whatever order the rows arrived in. pivot_wider()
  # lays its columns out in order of first appearance, and everything below
  # reads them by position: ncol(y) is "the final period" countries are ranked
  # on, and log_t_stat() treats column t as time t. A panel whose first
  # country lacked the first year put that year last, and a shuffled panel put
  # the years anywhere: the same data came back with different clubs and
  # nothing said so. Sorted on year_sort_key() so a factor year sorts by its
  # labels, and handed over as text so the order established here is the one
  # pivot_wider() keeps.
  df <- df[order(year_sort_key(df$year)), , drop = FALSE]
  df$year <- as.character(df$year)
  wide <- tidyr::pivot_wider(df, names_from = "year", values_from = dplyr::all_of(val_name))
  wide <- wide[stats::complete.cases(wide), ]
  if (nrow(wide) < 2L) {
    wdj_abort(c(
      "Not enough countries with a complete series to form clubs.",
      "i" = "Got {nrow(wide)}; the log-t test needs a balanced panel.",
      "*" = "Try {.fn complete_years} first, or narrow the year range."
    ))
  }
  incomplete <- sort(setdiff(all_iso, as.character(wide$iso3c)))
  if (length(incomplete)) {
    wdj_warn(c(
      "{length(incomplete)} countr{?y/ies} {?lacks/lack} a complete series and
       {?is/are} returned unclassified ({.code club = NA}):",
      "*" = "{.val {utils::head(incomplete, 8)}}",
      "i" = "The log-t test needs every year for every country it compares.
             {.fn complete_years} and {.fn interpolate_missing} fill gaps, or
             narrow the year range."
    ), class = "countryatlas_incomplete_series")
  }
  y <- as.matrix(wide[, -1, drop = FALSE])
  rownames(y) <- wide$iso3c
  ti <- ncol(y)
  if (ti < 15L) {
    wdj_warn(c(
      "The log-t test has little power on {ti}
       {cli::qty(ti)}period{?s}.",
      "i" = "Phillips & Sul suggest at least 15; treat the clubs as indicative."
    ))
  }

  crit <- stats::qnorm(alpha)                    # -1.645 at the 5% level
  ordered <- rownames(y)[order(y[, ti], decreasing = TRUE)]

  clubs <- rep(NA_integer_, nrow(y))
  names(clubs) <- rownames(y)
  stats_out <- list()
  remaining <- ordered
  club_id <- 0L

  while (length(remaining) >= min_size) {
    # Grow a core from the top of the remaining ordering while the test holds.
    core <- remaining[1:min_size]
    # Once, not twice: log_t_stat() fits a regression over the whole group, and
    # calling it again for the comparison doubled that work on every pass of a
    # loop that runs once per candidate club.
    core_stat <- log_t_stat(y[core, , drop = FALSE])
    if (is.na(core_stat) || core_stat < crit) {
      # The top country cannot start a club; set it aside and try the next.
      remaining <- remaining[-1]
      next
    }
    k <- min_size
    while (k < length(remaining)) {
      cand <- remaining[1:(k + 1)]
      s <- log_t_stat(y[cand, , drop = FALSE])
      if (is.na(s) || s < crit) break
      k <- k + 1
    }
    club_id <- club_id + 1L
    members <- remaining[1:k]
    clubs[members] <- club_id
    stats_out[[club_id]] <- tibble::tibble(
      club = club_id, n = length(members),
      log_t = log_t_stat(y[members, , drop = FALSE])
    )
    remaining <- setdiff(remaining, members)
  }

  out <- tibble::tibble(
    iso3c = c(names(clubs), incomplete),
    club = c(unname(clubs), rep(NA_integer_, length(incomplete))))
  st <- if (length(stats_out)) dplyr::bind_rows(stats_out) else
    tibble::tibble(club = integer(0), n = integer(0), log_t = numeric(0))
  out <- dplyr::left_join(out, st[, c("club", "log_t")], by = "club",
                          relationship = "many-to-one")
  attr(out, "countryatlas_clubs") <- st
  dplyr::arrange(out, .data$club, .data$iso3c)
}

# The Phillips-Sul log-t statistic for a group: the one-sided t on log(t) in
# log(H1/Ht) - 2 log(log t) ~ a + b log(t), fitted over the last 70% of the
# sample (their r = 0.3 trimming recommendation).
log_t_stat <- function(y) {
  ti <- ncol(y)
  if (nrow(y) < 2L || ti < 5L) return(NA_real_)
  h <- sweep(y, 2, colMeans(y), "/")
  Ht <- colMeans((h - 1)^2)
  start <- max(2L, floor(0.3 * ti))
  idx <- start:ti
  # Only the regression window has to be usable. log(H_1 / H_t) is
  # log(H_1) - log(H_t), and log(H_1) is one constant across the whole
  # regression, so it lands entirely in the intercept and cannot move the t
  # statistic on log(t) -- which is the only thing this returns. Requiring
  # H_1 > 0 therefore discarded a perfectly computable statistic, and H_1 is
  # exactly 0 whenever every unit starts equal: index_to() guarantees that by
  # construction, so convergence_club() on an indexed panel found no clubs at
  # all where the same panel in levels found seven. Periods before the window
  # were over-checked for the same reason -- they never enter the fit.
  if (!all(is.finite(Ht[idx])) || any(Ht[idx] <= 0)) return(NA_real_)
  lhs <- -log(Ht[idx]) - 2 * log(log(idx))
  rhs <- log(idx)
  fit <- try(stats::lm(lhs ~ rhs), silent = TRUE)
  if (inherits(fit, "try-error")) return(NA_real_)
  # lm_summary(), not summary(): every unit starting equal makes this
  # regression an exact fit, and base R's "essentially perfect fit" warning
  # then reached the caller of convergence_club() talking about a model the
  # caller does not know exists. The t-statistic is still what it is, and a
  # degenerate one returns NA_real_ through the guards either side.
  cf <- lm_summary(fit)$coefficients
  if (nrow(cf) < 2L) return(NA_real_)
  # HAC would be the textbook choice; the plain t is adequate at these lengths
  # and keeps the dependency footprint at zero.
  unname(cf[2, 3])
}

# The control limit at probability P for a denominator d around rate
# `target`: the exact Poisson quantile, interpolated between counts
# (Spiegelhalter 2005, appendix A.1.1), or with additive overdispersion
# tau2 > 0 the normal limit on the rate scale.
funnel_limit <- function(d, P, target, tau2 = 0) {
  if (tau2 > 0) return(target + stats::qnorm(P) * sqrt(target / d + tau2))
  E <- target * d
  r <- stats::qpois(P, E)
  num <- stats::ppois(r, E) - P
  den <- stats::ppois(r, E) - stats::ppois(r - 1, E)
  (r - ifelse(den > 0, num / den, 0)) / d
}

#' A funnel plot for rates
#'
#' Each country's rate against its denominator, inside control limits for the
#' rate a country of that size would show by chance alone. A small country's
#' extreme rate falls inside the wide mouth of the funnel; a large country
#' outside the narrow neck is a real outlier. It completes the rates set:
#' [rate_check()] flags the unreliable rates, [smooth_rates()] shrinks them,
#' `rate_funnel()` shows them, [value_by_alpha_map()] maps them.
#'
#' @param data A country-level frame with `iso3c`.
#' @param numerator,denominator The counts and their population at risk
#'   (unquoted).
#' @param target The rate the limits are drawn around; `NULL` (default) is
#'   the pooled rate, `sum(numerator) / sum(denominator)`.
#' @param limits The coverage of the inner and outer limits (default
#'   `c(0.95, 0.998)`, Spiegelhalter's "two and three sigma").
#' @param overdispersion If `TRUE`, widen the limits by the additive
#'   random-effects adjustment (Spiegelhalter 2005), for rates that vary
#'   between countries far more than Poisson noise allows -- the usual case
#'   for country data, where a funnel with exact limits flags most countries.
#' @param label_outliers Label the countries outside the outer limit with their
#'   ISO code (default `TRUE`).
#'
#' @return A `ggplot`, with the per-country table attached as the
#'   `"countryatlas_funnel"` attribute: `iso3c`, the two columns, `rate`, `z`
#'   (the standardised deviation) and `flag` (`"within"`, `"above 95%"`,
#'   `"above 99.8%"`, `"below 95%"` or `"below 99.8%"`, named after `limits`).
#'
#' @section The limits:
#' For a denominator \eqn{d} the expected count is \eqn{E = t d}, and the
#' limit at probability \eqn{P} is the exact Poisson quantile, interpolated
#' so the funnel is smooth: with \eqn{r = F^{-1}(P; E)},
#' \eqn{y_P = r - (F(r; E) - P) / (F(r; E) - F(r - 1; E))}, and the rate limit
#' is \eqn{y_P / d}. With `overdispersion = TRUE` the limits are
#' \eqn{t \pm z_P \sqrt{t / d + \tau^2}}, \eqn{\tau^2} estimated from the
#' winsorised z-scores.
#'
#' @references
#' Spiegelhalter, D. J. (2005). Funnel plots for comparing institutional
#' performance. *Statistics in Medicine* 24(8), 1185-1202.
#' \doi{10.1002/sim.1970}
#' @seealso [rate_check()], [smooth_rates()]
#' @export
#' @examples
#' set.seed(1)
#' d <- data.frame(iso3c = c("CHN", "IND", "FRA", "TUV", "NRU", "MLT"),
#'                 pop = c(1.41e9, 1.39e9, 6.8e7, 1.1e4, 1.2e4, 5.3e5))
#' d$deaths <- stats::rpois(nrow(d), d$pop * 0.008)
#' rate_funnel(d, deaths, pop)
rate_funnel <- function(data, numerator, denominator, target = NULL,
                        limits = c(0.95, 0.998), overdispersion = FALSE,
                        label_outliers = TRUE) {
  num_name <- quo_arg_name(rlang::enquo(numerator), "numerator")
  den_name <- quo_arg_name(rlang::enquo(denominator), "denominator")
  check_bool(overdispersion, "overdispersion")
  check_bool(label_outliers, "label_outliers")
  if (!is.numeric(limits) || length(limits) != 2L || anyNA(limits) ||
      any(limits <= 0 | limits >= 1) || limits[1] >= limits[2]) {
    wdj_abort(c("{.arg limits} must be two increasing probabilities in (0, 1).",
                "x" = "Got {.val {limits}}."))
  }
  check_cols(data, c("iso3c", num_name, den_name))
  check_numeric_col(data, num_name)
  check_numeric_col(data, den_name)
  df <- distinct_countries(tibble::as_tibble(sf_drop(data)))
  y <- df[[num_name]]
  x <- df[[den_name]]
  ok <- is.finite(y) & y >= 0 & is.finite(x) & x > 0
  if (sum(ok) < 2L) {
    wdj_abort("A funnel needs at least two countries with a usable count and
               denominator.")
  }
  if (any(!ok)) {
    wdj_warn("{sum(!ok)} countr{?y/ies} without a usable count or denominator
              {?is/are} left out.", class = "countryatlas_unusable_rows")
  }
  df <- df[ok, , drop = FALSE]
  y <- y[ok]
  x <- x[ok]
  if (is.null(target)) target <- sum(y) / sum(x)
  check_number(target, "target", lo = 0)
  rate <- y / x
  tau2 <- 0
  if (isTRUE(overdispersion)) {
    z0 <- (rate - target) / sqrt(target / x)
    q <- stats::quantile(z0, c(0.1, 0.9), names = FALSE)
    zw <- pmin(pmax(z0, q[1]), q[2])
    n <- length(zw)
    phi <- mean(zw^2)
    w <- x / target
    if (n * phi > n - 1) tau2 <- (n * phi - (n - 1)) / (sum(w) - sum(w^2) / sum(w))
  }
  lim_at <- function(d, P) funnel_limit(d, P, target, tau2)
  grid <- exp(seq(log(min(x)), log(max(x)), length.out = 200))
  probs <- c((1 - limits) / 2, 1 - (1 - limits) / 2)
  curves <- do.call(rbind, lapply(seq_along(probs), function(k) {
    data.frame(d = grid, rate = pmax(lim_at(grid, probs[k]), 0),
               limit = rep(sprintf("%g%%", 100 * limits[(k - 1) %% 2 + 1]),
                           length(grid)),
               side = if (k > 2) "upper" else "lower", id = k)
  }))
  inner <- sprintf("%g%%", 100 * limits[1])
  outer <- sprintf("%g%%", 100 * limits[2])
  hi_out <- rate > lim_at(x, probs[4])
  hi_in <- rate > lim_at(x, probs[3])
  lo_out <- rate < lim_at(x, probs[2])
  lo_in <- rate < lim_at(x, probs[1])
  flag <- ifelse(hi_out, paste("above", outer), ifelse(hi_in, paste("above", inner),
          ifelse(lo_out, paste("below", outer), ifelse(lo_in, paste("below", inner),
          "within"))))
  tab <- tibble::tibble(iso3c = df$iso3c, "{num_name}" := y, "{den_name}" := x,
                        rate = rate,
                        z = (rate - target) / sqrt(target / x + tau2),
                        flag = flag)
  pts <- data.frame(d = x, rate = rate, iso3c = df$iso3c,
                    out = hi_out | lo_out)
  p <- ggplot2::ggplot() +
    ggplot2::geom_line(data = curves,
                       ggplot2::aes(.data$d, .data$rate, group = .data$id,
                                    linetype = .data$limit),
                       colour = "grey40", linewidth = 0.4) +
    ggplot2::geom_hline(yintercept = target, colour = "grey20", linewidth = 0.5) +
    ggplot2::geom_point(data = pts, ggplot2::aes(.data$d, .data$rate,
                                                 colour = .data$out),
                        size = 1.8) +
    ggplot2::scale_x_log10(name = den_name, labels = scales_format()) +
    ggplot2::scale_colour_manual(values = c(`FALSE` = "grey35", `TRUE` = "#B2182B"),
                                 guide = "none") +
    ggplot2::scale_linetype_manual(name = "Control limit",
                                   values = stats::setNames(c("dashed", "solid"),
                                                            c(inner, outer))) +
    ggplot2::labs(y = paste0(num_name, " per ", den_name),
                  caption = sprintf("Target %s; %d of %d countries outside the %s limits%s.",
                                    format(signif(target, 3)), sum(hi_out | lo_out),
                                    nrow(tab), outer,
                                    if (tau2 > 0) ", adjusted for overdispersion" else "")) +
    ggplot2::theme_minimal()
  if (isTRUE(label_outliers) && any(pts$out)) {
    p <- p + ggplot2::geom_text(data = pts[pts$out, , drop = FALSE],
                                ggplot2::aes(.data$d, .data$rate, label = .data$iso3c),
                                size = 2.6, vjust = -0.7, colour = "#B2182B")
  }
  attr(p, "countryatlas_funnel") <- tab
  p
}
