# Alt text, and what the final plot actually shows -------------------------------------
#
# ggplot2::get_alt_text() returned "" for every map the package drew, so a map
# published from it reached a screen reader as nothing. Every map verb now
# sets labs(alt = <function>), which ggplot2 evaluates on the final plot, so
# the description follows whatever the caller did to the plot afterwards.

PROJECTION_NAMES <- c(
  equal_earth = "Equal Earth", robinson = "Robinson", mollweide = "Mollweide",
  natural_earth = "Natural Earth", plate_carree = "plate carree",
  mercator = "Mercator", winkel_tripel = "Winkel tripel", eckert4 = "Eckert IV",
  gall_peters = "Gall-Peters", orthographic = "orthographic",
  azimuthal_equal_area = "Lambert azimuthal equal-area",
  north_polar = "north polar azimuthal equal-area",
  south_polar = "south polar azimuthal equal-area",
  none = "unprojected longitude and latitude",
  "equal_earth (spherical, built-in)" = "Equal Earth (spherical)")

projection_name <- function(x) {
  if (is.null(x) || !length(x) || is.na(x[1])) return("an unrecorded projection")
  x <- x[1]
  if (x %in% names(PROJECTION_NAMES)) return(unname(PROJECTION_NAMES[x]))
  if (startsWith(x, "orthographic")) return(sub("^orthographic", "orthographic", x))
  x
}

# --- What the plot shows now (V7) --------------------------------------------------

# The projection a plot is drawn in, read from its coordinate system rather
# than from what the verb recorded: a coord_sf() added afterwards changes the
# map, and the provenance said otherwise.
current_projection <- function(p, recorded = NA_character_) {
  coord <- p$coordinates
  if (inherits(coord, "CoordSf")) {
    crs <- coord$crs
    if (is.null(crs)) return(recorded)
    crs_txt <- if (is.character(crs)) crs else tryCatch(
      as.character(sf::st_crs(crs)$proj4string), error = function(e) NA_character_)
    if (is.na(crs_txt)) return("custom")
    if (grepl("+proj=longlat", crs_txt, fixed = TRUE)) return("none")
    # Same projection, any central meridian or latitude: the verb records the
    # recentring separately.
    norm <- function(s) {
      s <- gsub("\\+lon_0=[^ ]*", "", s)
      if (grepl("+proj=ortho", s, fixed = TRUE)) s <- gsub("\\+lat_0=[^ ]*", "", s)
      s <- gsub("\\+(datum|units|no_defs|ellps|towgs84|type)(=[^ ]*)?", "", s)
      gsub("\\s+", " ", trimws(s))
    }
    for (pr in wdj_projections()) {
      if (identical(norm(wdj_crs(pr)), norm(crs_txt))) {
        rec <- sub(" .*$", "", recorded %||% "")
        return(if (identical(rec, pr) || startsWith(recorded %||% "", pr)) recorded else pr)
      }
    }
    return("custom")
  }
  if (inherits(coord, "CoordMap")) {
    if (identical(coord$projection, "orthographic")) {
      return(if (startsWith(recorded %||% "", "orthographic")) recorded else "orthographic")
    }
    return(paste("custom", coord$projection))
  }
  if (inherits(coord, "CoordQuickmap")) return("none")
  d <- gg_plot_data(p)
  if (!is.null(d) && ".wdj_projection" %in% names(d)) return(d$.wdj_projection[1])
  # A verb that builds in metres (the built-in Equal Earth) or a frame of its
  # own (tile grids, cartograms) keeps what it recorded.
  recorded
}

# The fill scale's kind, to compare with the style the verb recorded.
current_scale_kind <- function(p) {
  sc <- tryCatch(p$scales$get_scales("fill"), error = function(e) NULL)
  if (is.null(sc)) return(NA_character_)
  if (inherits(sc, "ScaleBinned")) return("binned")
  if (inherits(sc, "ScaleContinuous")) return("continuous")
  if (inherits(sc, "ScaleDiscrete")) return("discrete")
  NA_character_
}

style_scale_kind <- function(style) {
  if (is.null(style) || is.na(style)) return(NA_character_)
  if (style %in% BAR_STYLES) return("binned")
  if (identical(style, "continuous")) return("continuous")
  if (style %in% c(CLASSED_STYLES, "categorical", "vsup") ||
      grepl("per panel", style, fixed = TRUE)) return("discrete")
  NA_character_
}

# --- The description ----------------------------------------------------------------

#' Describe a map in words, for alt text
#'
#' A text description of a map drawn by the package, computed from the final
#' plot -- its projection, its fill scale and the data it draws -- so it stays
#' true when the plot is modified afterwards. Every map verb sets it as the
#' plot's alt text (`labs(alt =)`), which [ggplot2::get_alt_text()] returns and
#' which knitr, Quarto and Shiny can pass to a screen reader.
#'
#' The levels follow Lundgard & Satyanarayan (2022). **Level 1** describes the
#' construction: the kind of map, the projection, what the fill shows and how
#' it is classified, and how many countries have data. **Level 2** adds
#' statistics: the three highest and three lowest countries, the share
#' missing, and the continent with the highest median. Levels 3 and 4 --
#' trends, and what the map means -- are the author's to write; add them to
#' the text this returns.
#'
#' knitr does not ask ggplot2 for alt text when a chunk sets none, so in
#' R Markdown set it on the chunk, from a plot built in an earlier chunk:
#' `fig.alt = countryatlas::map_alt_text(p)`.
#'
#' @param p A map from one of the package's map verbs.
#' @param level `1` or `2` (default).
#'
#' @return A single string.
#' @references
#' Lundgard, A. & Satyanarayan, A. (2022). Accessible visualization via
#' natural language descriptions: a four-level model of semantic content.
#' *IEEE Transactions on Visualization and Computer Graphics* 28(1), 1073-1083.
#' \doi{10.1109/TVCG.2021.3114770}
#' @seealso [map_provenance()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' p <- world_map(attach_geometry(snap), gdp_per_capita)
#' map_alt_text(p)
#' ggplot2::get_alt_text(p)
#' }
map_alt_text <- function(p, level = 2) {
  if (!inherits(p, "ggplot")) {
    wdj_abort(c("{.arg p} must be a map from one of the package's map verbs.",
                "x" = "Got {.obj_type_friendly {p}}."))
  }
  if (!identical(level, 1) && !identical(level, 2) &&
      !identical(level, 1L) && !identical(level, 2L)) {
    wdj_abort(c("{.arg level} must be 1 or 2.",
                "i" = "Levels 3 and 4 (trends, and what the map means) are the
                       author's to write."))
  }
  prov <- attr(p, "countryatlas_provenance")
  if (is.null(prov)) return("A map.")
  fill <- prov$fill %||% NA_character_
  title <- gg_title(p)
  legend <- tryCatch(p$scales$get_scales("fill")$name, error = function(e) NULL)
  if (inherits(legend, "waiver") || !is.character(legend)) legend <- NULL
  what <- if (!is.na(fill)) {
    lab <- gsub("\n", " ", legend %||% fill)
    if (!identical(lab, fill) && !startsWith(fill, ".wdj")) {
      sprintf("%s (%s)", lab, fill)
    } else lab
  }
  kind <- map_kind(prov)
  proj <- projection_name(current_projection(p, prov$projection))
  parts <- c(
    if (!is.null(title)) paste0(title, "."),
    sprintf("%s%s, %s projection.", kind,
            if (!is.null(what)) paste0(" of ", what, " by country") else "",
            proj),
    classes_sentence(prov),
    coverage_sentence(prov$coverage))
  if (identical(as.numeric(level), 2)) {
    parts <- c(parts, stats_sentences(prov))
  }
  paste(parts[nzchar(parts)], collapse = " ")
}

map_kind <- function(prov) {
  st <- prov$style %||% ""
  bk <- prov$backend %||% ""
  if (startsWith(st, "proportional symbol")) return("Proportional-symbol map")
  if (identical(st, "spike")) return("Spike map")
  if (startsWith(st, "great-circle flow")) return("Flow map")
  if (startsWith(st, "value-by-alpha")) return("Value-by-alpha choropleth")
  if (startsWith(st, "gridded cartogram")) return("Gridded cartogram")
  if (startsWith(st, "cartogram")) return("Cartogram")
  if (identical(st, "tile sparkline")) return("Tile-grid map of line charts")
  if (grepl(" tile$", st) || identical(bk, "tile-grid")) return("Tile-grid map")
  if (startsWith(st, "bivariate")) return("Bivariate choropleth")
  if (startsWith(st, "ternary")) return("Ternary choropleth")
  if (startsWith(prov$projection %||% "", "orthographic")) return("Globe choropleth")
  "Choropleth map"
}

classes_sentence <- function(prov) {
  st <- prov$style %||% NA_character_
  br <- prov$breaks
  if (is.na(st)) return("")
  if (startsWith(st, "ternary")) {
    return(sprintf("Each country mixes three colours in proportion to its shares; grey is %s.",
                   if (is.null(prov$centre)) "an even split" else "the average composition"))
  }
  if (!is.null(br) && length(br) > 2L) {
    fin <- br[is.finite(br)]
    how <- switch(st, fixed = "fixed", quantile = "quantile", jenks = "natural-breaks (Jenks)",
                  fisher = "natural-breaks (Fisher)", headtails = "head/tail",
                  sd = "standard-deviation", binned = , equal = "equal-interval", st)
    return(sprintf("Coloured in %d %s classes from %s to %s%s.",
                   length(br) - 1L, how, si_label(min(fin)), si_label(max(fin)),
                   if (!is.null(prov$midpoint)) sprintf(", diverging at %s",
                                                        si_label(prov$midpoint)) else ""))
  }
  switch(st,
         continuous = if (!is.null(prov$midpoint)) {
           sprintf("Coloured on a continuous diverging scale centred on %s.",
                   si_label(prov$midpoint))
         } else "Coloured on a continuous scale.",
         categorical = "Coloured by category.",
         vsup = "Coloured by value and uncertainty together.",
         "")
}

coverage_sentence <- function(cov) {
  if (is.null(cov) || is.na(cov$n_total %||% NA)) return("")
  sprintf("%d of %d %s have data.", cov$n_shown, cov$n_total,
          countries_noun(cov$n_total))
}

stats_sentences <- function(prov) {
  v <- prov$values
  if (is.null(v) || !nrow(v)) return(character(0))
  nm <- suppressWarnings(convert_country(v$iso3c, to = "country", origin = "iso3c",
                                         warn = FALSE))
  nm[is.na(nm)] <- v$iso3c[is.na(nm)]
  ok <- !is.na(v$value)
  out <- character(0)
  if (is.numeric(v$value)) {
    ok <- ok & is.finite(v$value)
    if (sum(ok) >= 2L) {
      o <- order(v$value[ok], decreasing = TRUE)
      vv <- v$value[ok][o]; nn <- nm[ok][o]
      k <- min(3L, length(vv))
      fmt <- function(i) sprintf("%s (%s)", nn[i], si_label(vv[i]))
      out <- c(out,
               sprintf("Highest: %s.", paste(vapply(seq_len(k), fmt, ""), collapse = ", ")),
               sprintf("Lowest: %s.", paste(vapply(rev(seq_len(length(vv)))[seq_len(k)],
                                                   fmt, ""), collapse = ", ")))
      cont <- countryatlas::country_meta$continent[match(v$iso3c[ok],
                                                         countryatlas::country_meta$iso3c)]
      if (any(!is.na(cont))) {
        med <- tapply(v$value[ok], cont, stats::median)
        med <- med[!is.na(med)]
        if (length(med) > 1L) {
          out <- c(out, sprintf("%s has the highest median (%s).",
                                names(med)[which.max(med)], si_label(max(med))))
        }
      }
    }
  } else if (any(ok)) {
    tab <- sort(table(as.character(v$value[ok])), decreasing = TRUE)
    top <- utils::head(tab, 5)
    out <- c(out, sprintf("Most common: %s.", paste(sprintf("%s (%d)", names(top),
                                                           as.integer(top)),
                                                   collapse = ", ")))
  }
  miss <- mean(!ok)
  if (miss > 0) out <- c(out, sprintf("%d%% of countries have no data.", round(100 * miss)))
  out
}

# One value per country for the description, from the frame the verb drew:
# the latest year of a panel, the first row otherwise.
alt_values <- function(data, fill) {
  if (is.null(fill) || is.na(fill) || !fill %in% names(data) ||
      !"iso3c" %in% names(data)) return(NULL)
  df <- tibble::as_tibble(sf_drop(data))
  df <- df[!is.na(df$iso3c), c("iso3c", fill, intersect("year", names(df))),
           drop = FALSE]
  if ("year" %in% names(df)) df <- df[order(-df$year), , drop = FALSE]
  df <- df[!duplicated(df$iso3c), , drop = FALSE]
  tibble::tibble(iso3c = df$iso3c, value = df[[fill]])
}

# Set the plot's alt text to the description, evaluated on the final plot.
# ggplot2 also calls a label function with the default label while building,
# to transform it the way labs(x = toupper) does; that call gets a string, and
# hands it back.
with_alt_text <- function(p) {
  # A tmap or plotly object has no labs(); adding one returned NULL.
  if (!inherits(p, "ggplot")) return(p)
  p + ggplot2::labs(alt = function(plot) {
    if (inherits(plot, "ggplot")) map_alt_text(plot) else plot
  })
}
