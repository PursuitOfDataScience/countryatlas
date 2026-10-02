# Ternary choropleth -------------------------------------------------------------------
#
# The ternary balance scheme: each part has a primary hue, 120 degrees apart on
# the HCL wheel, and a composition's colour is the share-weighted sum of the
# three as vectors. The sum's direction is the hue and its length the chroma,
# so a composition dominated by one part takes that part's colour at full
# chroma and an even one is grey. Lightness falls away from the grey by
# TERNARY_CONTRAST, as in a diverging palette: the balanced middle is a light
# grey and the more unbalanced a composition, the darker. Schoeley (2021) centres the scheme by perturbing every composition by
# the inverse of a centre, which moves the centre to the barycentre: grey is
# then the average country, and the colours show which part a country has
# more of than the average. The package draws it natively; tricolore, the
# reference implementation, draws its key through ggtern.

TERNARY_CHROMA <- 140
TERNARY_LIGHTNESS <- 80
TERNARY_CONTRAST <- 0.4

# Colours for the rows of a closed composition matrix (rows sum to 1). A row
# with a missing part has no colour.
ternary_colours <- function(P, hue) {
  out <- rep(NA_character_, nrow(P))
  ok <- stats::complete.cases(P)
  if (!any(ok)) return(out)
  phi <- (hue + c(0, 120, 240)) * pi / 180
  z <- as.vector(P[ok, , drop = FALSE] %*% exp(1i * phi))
  # |z| is 0 at the barycentre and 1 at a vertex; pmin() only absorbs rounding.
  m <- pmin(Mod(z), 1)
  out[ok] <- grDevices::hcl(h = (Arg(z) * 180 / pi) %% 360,
                            c = TERNARY_CHROMA * m,
                            l = TERNARY_LIGHTNESS * (1 - TERNARY_CONTRAST * m),
                            fixup = TRUE)
  out
}

# The three parts as a closed composition, one row per row of `df`. A row is
# usable when every part is a finite, non-negative number and they do not all
# vanish; any other row is NA.
ternary_closure <- function(df, parts) {
  P <- as.matrix(as.data.frame(df)[, parts, drop = FALSE])
  storage.mode(P) <- "double"
  P[!is.finite(P)] <- NA
  tot <- rowSums(P)
  P[!is.na(tot) & tot <= 0, ] <- NA
  P / rowSums(P)
}

# Perturb by the inverse of the centre and close again: Schoeley's centring.
ternary_perturb <- function(P, centre) {
  if (is.null(centre)) return(P)
  Q <- sweep(P, 2L, centre, "/")
  Q / rowSums(Q)
}

# The centre: the closed geometric mean of the parts over the countries with
# all three positive (the compositional mean, Aitchison 1986), a composition
# the caller gives, or none.
ternary_centre <- function(P, centre, parts, call = rlang::caller_env()) {
  if (isFALSE(centre)) return(NULL)
  if (isTRUE(centre)) {
    pos <- stats::complete.cases(P) & rowSums(P > 0, na.rm = TRUE) == 3L
    if (!any(pos)) {
      wdj_abort(c(
        "No country has all three parts above zero, so there is no average
         composition to centre on.",
        "i" = "Pass {.code centre = FALSE}, or a composition such as
               {.code centre = c(1, 1, 1)}."
      ), call = call)
    }
    g <- exp(colMeans(log(P[pos, , drop = FALSE])))
    return(stats::setNames(g / sum(g), parts))
  }
  stats::setNames(centre / sum(centre), parts)
}

check_ternary_centre <- function(centre, call = rlang::caller_env()) {
  if (isTRUE(centre) || isFALSE(centre)) return(invisible(centre))
  if (!is.numeric(centre) || length(centre) != 3L || any(!is.finite(centre)) ||
      any(centre <= 0)) {
    wdj_abort(c(
      "{.arg centre} must be {.code TRUE}, {.code FALSE} or three positive
       numbers.",
      "x" = "Got {.obj_type_friendly {centre}}.",
      "i" = "Three numbers are a composition to centre on, in the order
             {.arg x}, {.arg y}, {.arg z}; they need not add to 1."
    ), call = call)
  }
  invisible(centre)
}

# The key: the colour triangle, with every country on it. Drawn with grid and
# placed in the legend area by guide_custom(), so it does not depend on the
# map's coordinate system. Shown in the centred space when the map is
# centred, where the barycentre is the centre.
ternary_key_grob <- function(Pc, labels, hue, centred, n = 12L) {
  h <- sqrt(3) / 2
  tri <- list()
  for (i in 0:(n - 1L)) for (j in 0:(n - 1L - i)) {
    tri[[length(tri) + 1L]] <- rbind(c(i, j), c(i + 1L, j), c(i, j + 1L))
    if (i + j <= n - 2L) {
      tri[[length(tri) + 1L]] <- rbind(c(i + 1L, j), c(i, j + 1L), c(i + 1L, j + 1L))
    }
  }
  # Lattice (i, j) is the composition (1 - (i + j) / n, i / n, j / n).
  cen <- t(vapply(tri, function(v) colMeans(v) / n, numeric(2)))
  cols <- ternary_colours(cbind(1 - cen[, 1] - cen[, 2], cen[, 1], cen[, 2]), hue)
  xs <- unlist(lapply(tri, function(v) (v[, 1] + v[, 2] / 2) / n))
  ys <- unlist(lapply(tri, function(v) v[, 2] * h / n))
  ids <- rep(seq_along(tri), each = 3L)
  ok <- stats::complete.cases(Pc)
  px <- Pc[ok, 2] + Pc[ok, 3] / 2
  py <- Pc[ok, 3] * h
  # Equal scales on both axes keep the triangle equilateral in a square key.
  vp <- grid::viewport(xscale = c(-0.14, 1.14), yscale = c(-0.2, 1.08))
  grid::gTree(children = grid::gList(
    grid::polygonGrob(xs, ys, id = ids, default.units = "native",
                      gp = grid::gpar(fill = cols, col = cols, lwd = 0.4)),
    grid::polygonGrob(c(0, 1, 0.5), c(0, 0, h), default.units = "native",
                      gp = grid::gpar(fill = NA, col = "grey30", lwd = 0.6)),
    grid::pointsGrob(px, py, pch = 16, size = grid::unit(0.7, "mm"),
                     default.units = "native",
                     gp = grid::gpar(col = "grey15", alpha = 0.7)),
    if (centred) grid::pointsGrob(0.5, h / 3, pch = 3, size = grid::unit(2.6, "mm"),
                                  default.units = "native",
                                  gp = grid::gpar(col = "black", lwd = 1.1)),
    grid::textGrob(labels, x = c(0, 1, 0.5), y = c(-0.1, -0.1, h + 0.07),
                   hjust = c(0, 1, 0.5), default.units = "native",
                   gp = grid::gpar(fontsize = 7.5))
  ), vp = vp)
}

#' Ternary choropleth for three-part compositions
#'
#' Colours each country by the balance of three parts of a whole: the
#' agriculture, industry and services shares of GDP, or the young, working-age
#' and old shares of a population. Each part has a primary colour, and a
#' country's colour mixes the three in proportion to its shares, so a country
#' dominated by one part takes that part's colour and an even mix is grey
#' (the ternary balance scheme).
#'
#' Countries' compositions usually sit close together, and on the plain scheme
#' they come out in near-identical colours. `centre = TRUE` (the default)
#' centres the scheme on the average composition (Schoeley 2021): grey is the
#' average country, and a colour says which part a country has more of than
#' the average. The key is the colour triangle with every country on it as a
#' ring, and the caption states the average composition the colours are
#' relative to.
#'
#' @param data A map-ready frame from [attach_geometry()], on either backend.
#' @param x,y,z The three parts (unquoted), each non-negative. They are closed
#'   to shares, so counts and percentages work as well as proportions. A
#'   country missing any part, or with all three zero, is drawn as no data.
#' @param centre `TRUE` (default) to centre on the average composition, the
#'   closed geometric mean over the countries with all three parts above zero;
#'   three positive numbers, a composition to centre on, in the order `x`, `y`,
#'   `z`; or `FALSE` for the plain scheme, where grey means equal shares.
#' @param projection,recenter As in [world_map()].
#' @param hue The hue of `x`'s colour, in degrees on the HCL wheel; `y` and `z`
#'   take the hues 120 and 240 degrees on.
#' @param key Draw the colour triangle in the legend area? Needs ggplot2 3.5.0
#'   or later.
#' @param title,legend Optional plot title and key title.
#' @param footnote The caption, as in [world_map()]: `"auto"` (default)
#'   states the coverage, the centre and the source, a string is used as
#'   given, `FALSE` adds nothing.
#'
#' @return A `ggplot` object. [map_provenance()] records the centre.
#' @references
#' Schoeley, J. (2021). The centered ternary balance scheme: a technique to
#' visualize surfaces of unbalanced three-part compositions. *Demographic
#' Research* 44(19), 443-458. \doi{10.4054/DemRes.2021.44.19}
#' @seealso [world_map()], [bivariate_map()]
#' @export
#' @examples
#' \donttest{
#' # A made-up composition: three parts that add up to each country's total.
#' snap <- countryatlas::world_snapshot$countries
#' set.seed(1)
#' snap$a <- stats::runif(nrow(snap), 1, 4)
#' snap$b <- stats::runif(nrow(snap), 2, 6)
#' snap$c <- stats::runif(nrow(snap), 4, 9)
#' ternary_map(attach_geometry(snap), a, b, c)
#' }
ternary_map <- function(data, x, y, z, centre = TRUE,
                        projection = "equal_earth", recenter = NULL,
                        hue = 80, key = TRUE, title = NULL, legend = NULL,
                        footnote = "auto") {
  parts <- c(quo_arg_name(rlang::enquo(x), "x"),
             quo_arg_name(rlang::enquo(y), "y"),
             quo_arg_name(rlang::enquo(z), "z"))
  check_ternary_centre(centre)
  check_number(hue, "hue", lo = 0, hi = 360)
  check_bool(key, "key")
  check_label_args(title = title, legend = legend)
  check_map_geometry(data)
  check_cols(data, parts)
  if (anyDuplicated(parts)) {
    wdj_abort(c("{.arg x}, {.arg y} and {.arg z} must be three different columns.",
                "x" = "Got {.val {parts}}."))
  }
  for (nm in parts) check_numeric_col(data, nm)
  unplaced <- attr(data, "countryatlas_unplaced")
  for (nm in parts) {
    v <- c(data[[nm]], if (!is.null(unplaced) && nm %in% names(unplaced)) unplaced[[nm]])
    neg <- !is.na(v) & v < 0
    if (any(neg)) {
      wdj_abort(c(
        "{.arg x}, {.arg y} and {.arg z} are parts of a whole and cannot be
         negative.",
        "x" = "{.field {nm}} has {sum(neg)} negative value{?s}."
      ), class = "countryatlas_negative_part")
    }
    warn_infinite_fill(data, nm)
  }
  warn_map_panel(data)
  sf_mode <- is_sf(data)
  pc <- if (!sf_mode) wdj_polygon_coord(projection, recenter)

  # The centre is the average *country*: one row per drawable unit, the small
  # states included, since the polygon backend repeats a country's values down
  # every vertex.
  df <- tibble::as_tibble(sf_drop(data))
  unit <- unit_ids(df)
  one <- if (is.null(unit)) rep(TRUE, nrow(df)) else !duplicated(unit) & !is.na(unit)
  per_unit <- df[one, parts, drop = FALSE]
  if (!is.null(unplaced) && all(parts %in% names(unplaced))) {
    per_unit <- rbind(per_unit, unplaced[, parts, drop = FALSE])
  }
  P_unit <- ternary_closure(per_unit, parts)
  if (!any(stats::complete.cases(P_unit))) {
    wdj_abort(c(
      "No country has all three of {.val {parts}}.",
      "i" = "A ternary map needs every part of a country's composition."
    ))
  }
  cen <- ternary_centre(P_unit, centre, parts)

  data[[".wdj_tern"]] <- ternary_colours(
    ternary_perturb(ternary_closure(df, parts), cen), hue)
  if (!is.null(unplaced) && all(parts %in% names(unplaced))) {
    unplaced[[".wdj_tern"]] <- ternary_colours(
      ternary_perturb(ternary_closure(unplaced, parts), cen), hue)
    attr(data, "countryatlas_unplaced") <- unplaced
  }
  data_full <- data
  coverage <- na_coverage(data, ".wdj_tern")
  ss <- small_state_points(data, ".wdj_tern", "auto", 1000)
  coverage <- small_state_coverage(coverage, ss)
  fill_q <- rlang::quo(.data[[".wdj_tern"]])

  if (sf_mode) {
    data <- clip_for_projection(data, projection, recenter)
    p <- ggplot2::ggplot(data) +
      ggplot2::geom_sf(ggplot2::aes(fill = !!fill_q), color = "grey30",
                       linewidth = 0.1) +
      wdj_coord_sf(projection, recenter)
  } else {
    data <- recenter_rings(data, recenter)
    data <- apply_polygon_transform(data, pc)
    p <- ggplot2::ggplot(data, ggplot2::aes(x = .data$long, y = .data$lat,
                                            group = .data$group, fill = !!fill_q)) +
      ggplot2::geom_polygon(color = "grey30", linewidth = 0.1) +
      pc$coord
  }
  p <- p + ggplot2::scale_fill_identity(na.value = "grey85", guide = "none") +
    theme_world_map()
  pt_layer <- small_state_layer(ss$points, fill_q, sf_mode, pc, projection, recenter)
  if (!is.null(pt_layer)) {
    p <- suppressMessages(p + pt_layer)
    p <- suppressMessages(p + if (sf_mode) wdj_coord_sf(projection, recenter) else pc$coord)
  }
  if (isTRUE(key)) {
    if ("guide_custom" %in% getNamespaceExports("ggplot2")) {
      P_key <- ternary_perturb(P_unit, cen)
      p <- p + ggplot2::guides(custom = ggplot2::guide_custom(
        ternary_key_grob(P_key, parts, hue, centred = !is.null(cen)),
        width = grid::unit(3.4, "cm"), height = grid::unit(3.4, "cm"),
        title = legend %||% if (is.null(cen)) "Composition" else
          "Relative to the\naverage country"))
    } else {
      wdj_warn(c("The key needs ggplot2 3.5.0 or later, and is left out.",
                 "i" = "Update ggplot2 to draw it."),
               class = "countryatlas_ternary_key")
    }
  }
  if (!is.null(title)) p <- p + ggplot2::labs(title = title)

  auto <- identical(footnote, "auto") || isTRUE(footnote)
  centre_note <- if (auto && !is.null(cen)) {
    sprintf("\nGrey is the %s composition: %s.",
            if (isTRUE(centre)) "average" else "centre",
            paste(sprintf("%s %s%%", parts, format(round(100 * cen, 1), nsmall = 1,
                                                  trim = TRUE)),
                  collapse = ", "))
  }
  sources <- fill_source_info(data_full, parts)
  p <- wdj_provenance(
    p, data_full, NULL, if (sf_mode) "sf" else "polygon",
    if (sf_mode) projection else pc$label,
    style = if (is.null(cen)) "ternary balance" else "ternary balance, centred",
    extra = list(fill = paste(parts, collapse = ", "), parts = parts,
                 centre = cen, recenter = recenter, coverage = coverage,
                 sources = sources, small_states = "auto",
                 n_points = if (is.null(ss$points)) 0L else
                   length(unique(ss$points$iso3c)),
                 undrawable = ss$undrawable),
    footnote = footnote,
    notes = c(centre_note, if (auto) small_state_note(ss)))
  p
}
