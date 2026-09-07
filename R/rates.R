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
#'   `expected_se` (the Poisson standard error of the rate, \eqn{\sqrt{r/d}}) and
#'   `flagged`, sorted with the least reliable first.
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
    ifelse(is.finite(den) & den > 0, num / den, NA_real_)
  } else {
    rate_name <- quo_arg_name(rate_q, "rate")
    check_cols(df, rate_name)
    df[[rate_name]]
  }
  thr <- min_denominator %||% stats::quantile(den[is.finite(den) & den > 0],
                                              0.10, na.rm = TRUE, names = FALSE)
  # With no positive finite denominator anywhere, quantile() returns NA and the
  # comparison below yields an all-NA `flagged` column -- so sum(out$flagged),
  # the obvious next step, is NA rather than a count. Say why once.
  if (!is.finite(thr)) {
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
    expected_se = ifelse(is.finite(r) & is.finite(den) & den > 0,
                         sqrt(pmax(r, 0) / den), NA_real_),
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
  ord <- ifelse(is.finite(num) & is.finite(den) & den > 0,
                sqrt(pmax(num, 1)) / den, NA_real_)
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
#' @param method `"eb"` (default) for empirical-Bayes shrinkage, or `"none"` to
#'   compute the raw rate only.
#' @param suffix Suffix for the new columns (default `"_smoothed"`).
#'
#' @return `data` with `<numerator>_rate` and `<numerator>_smoothed` columns
#'   added, plus `<numerator>_shrinkage` -- the weight given to the country's own
#'   rate, between 0 (fully shrunk to the global rate) and 1 (untouched).
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
                         method = c("eb", "none"), suffix = "_smoothed") {
  method <- rlang::arg_match(method)
  check_string(suffix, "suffix")
  num_name <- quo_arg_name(rlang::enquo(numerator), "numerator")
  den_name <- quo_arg_name(rlang::enquo(denominator), "denominator")
  check_cols(data, c(num_name, den_name))
  check_numeric_col(data, num_name)
  check_numeric_col(data, den_name)

  num <- data[[num_name]]
  den <- data[[den_name]]
  ok <- is.finite(num) & is.finite(den) & den > 0
  raw <- ifelse(ok, num / den, NA_real_)

  rate_col <- paste0(num_name, "_rate")
  sm_col <- paste0(num_name, suffix)
  sh_col <- paste0(num_name, "_shrinkage")
  warn_overwrite(data, c(rate_col, sm_col, sh_col))
  # Same silence rate_check() used to have: with no usable denominator every
  # rate is NA, so the smoothed column is NA too and the result looks like a
  # computation that ran rather than one with nothing to work with.
  if (!any(ok)) {
    wdj_warn(c(
      "No usable {.arg denominator}, so there are no rates to smooth.",
      "i" = "A rate needs a finite, positive denominator; {.field {rate_col}}
             and {.field {sm_col}} are {.val {NA}} throughout."
    ), class = "countryatlas_no_rates")
  } else if (any(!ok)) {
    wdj_warn(c(
      "{sum(!ok)} row{?s} ha{?s/ve} no finite, positive {.field {den_name}},
       so the rate there is {.val {NA}}.",
      "i" = "Those rows take no part in the smoothing either."
    ), class = "countryatlas_unusable_rows")
  }
  data[[rate_col]] <- raw

  if (identical(method, "none") || sum(ok) < 2L) {
    data[[sm_col]] <- raw
    data[[sh_col]] <- ifelse(ok, 1, NA_real_)
    # Normalised here too, not only on the smoothing path below: this early
    # return handed back whatever class arrived, so `method = "none"` leaked an
    # incoming grouping and returned a bare data.frame where every other mode
    # of the same function returns a tibble.
    return(wdj_return_frame(data))
  }

  # Method-of-moments Poisson-gamma (Marshall 1991): the global rate is the
  # pooled one, and the between-country variance is the excess over what Poisson
  # sampling alone would produce.
  d <- den[ok]; y <- num[ok]; r <- y / d
  rbar <- sum(y) / sum(d)
  dbar <- mean(d)
  s2 <- sum(d * (r - rbar)^2) / sum(d)
  phi <- s2 - rbar / dbar
  w <- rep(0, length(r))
  if (is.finite(phi) && phi > 0) w <- d / (d + rbar / phi)

  sm <- rep(NA_real_, length(raw))
  shr <- rep(NA_real_, length(raw))
  sm[ok] <- w * r + (1 - w) * rbar
  shr[ok] <- w
  data[[sm_col]] <- sm
  data[[sh_col]] <- shr
  # Was a bare `data`, so this verb handed back whatever class arrived: a
  # grouped frame stayed grouped, and the caller's next mutate() then computed
  # per-group without asking. The eleven sibling verbs all normalise here.
  wdj_return_frame(data)
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
    data <- dplyr::left_join(data, idx[, c("iso3c", "year", ".wdj_defl")],
                             by = c("iso3c", "year"), na_matches = "never")
    defl_name <- ".wdj_defl"
  } else {
    defl_name <- quo_arg_name(defl_q, "deflator")
    check_cols(data, defl_name)
    check_numeric_col(data, defl_name)
  }

  # A country with no usable deflator in base_year has nothing to rebase
  # against, so every one of its values comes back NA -- which in the output is
  # indistinguishable from a country the source had no data for at all. The
  # arithmetic is right; the silence is not.
  base_ok <- data %>%
    dplyr::group_by(.data$iso3c) %>%
    dplyr::summarise(
      has = any(.data$year == base_year & is.finite(.data[[defl_name]]) &
                  .data[[defl_name]] != 0, na.rm = TRUE),
      .groups = "drop")
  no_base <- base_ok$iso3c[!base_ok$has]
  if (length(no_base)) {
    wdj_warn(c(
      "{length(no_base)} countr{?y/ies} ha{?s/ve} no usable {base_year}
       deflator; the rebased values are all {.val {NA}}:",
      "*" = "{.val {utils::head(no_base, 8)}}",
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
  out$.wdj_base <- NULL
  # group_by_unit() rather than iso3c: the base-year deflator is read from
  # within the group, so two rows whose iso3c did not resolve were rebased
  # against each other. deflate() does not route through wdj_return_frame(),
  # so the key is dropped here. The base_ok warning above still groups on
  # iso3c, because its job is to name the countries it found.
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

  if (rlang::quo_is_null(fac_q)) {
    # As in deflate() and per_capita(): drop a caller's colliding column so the
    # join cannot suffix the fetched one out of reach.
    data[[".wdj_ppp"]] <- NULL
    idx <- fetch_wdi(c(.wdj_ppp = "PA.NUS.PPP"),
                     start = min(data$year, na.rm = TRUE),
                     end = max(data$year, na.rm = TRUE))
    data <- dplyr::left_join(data, idx[, c("iso3c", "year", ".wdj_ppp")],
                             by = c("iso3c", "year"), na_matches = "never")
    fac_name <- ".wdj_ppp"
  } else {
    fac_name <- quo_arg_name(fac_q, "factor")
    check_cols(data, fac_name)
    check_numeric_col(data, fac_name)
  }
  fac <- data[[fac_name]]
  new <- paste0(val_name, suffix)
  warn_overwrite(data, new)
  usable <- is.finite(fac) & fac > 0
  # Zero, negative and NA factors all yield NA here, which is right but was
  # silent: a bad factor column produced a mostly-empty result that looked
  # like a conversion had happened.
  if (!any(usable)) {
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
  data[[new]] <- ifelse(usable, data[[val_name]] / fac, NA_real_)
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
#'   are attached as the `"countryatlas_clubs"` attribute.
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
  wide <- tidyr::pivot_wider(df, names_from = "year", values_from = dplyr::all_of(val_name))
  wide <- wide[stats::complete.cases(wide), ]
  if (nrow(wide) < 2L) {
    wdj_abort(c(
      "Not enough countries with a complete series to form clubs.",
      "i" = "Got {nrow(wide)}; the log-t test needs a balanced panel.",
      "*" = "Try {.fn complete_years} first, or narrow the year range."
    ))
  }
  y <- as.matrix(wide[, -1, drop = FALSE])
  rownames(y) <- wide$iso3c
  ti <- ncol(y)
  if (ti < 15L) {
    wdj_warn(c(
      "The log-t test has little power on {ti} periods.",
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

  out <- tibble::tibble(iso3c = names(clubs), club = unname(clubs))
  st <- if (length(stats_out)) dplyr::bind_rows(stats_out) else
    tibble::tibble(club = integer(0), n = integer(0), log_t = numeric(0))
  out <- dplyr::left_join(out, st[, c("club", "log_t")], by = "club")
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
  cf <- summary(fit)$coefficients
  if (nrow(cf) < 2L) return(NA_real_)
  # HAC would be the textbook choice; the plain t is adequate at these lengths
  # and keeps the dependency footprint at zero.
  unname(cf[2, 3])
}
