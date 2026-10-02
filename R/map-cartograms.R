# Maps: cartograms and tile grids --------------------------------------------
#
# Every verb here resizes or replaces the countries themselves: contiguous and
# Dorling cartograms, the equal-area tile grid and the gridded cartogram.

#' Area-honest cartogram
#'
#' Resizes countries by `weight` (population, GDP, ...) via the optional
#' `cartogram` package, defeating the "big empty countries dominate the eye"
#' bias of world choropleths.
#'
#' @section Which algorithm:
#' `"contiguous"` (Dougenik) and `"dorling"`/`"noncontiguous"` come from
#' `cartogram`. `"flow"` comes from `cartogramR` and implements the
#' Gastner-Seguy-More flow-based method, which is both the current state of the
#' art and far faster than diffusion-based approaches -- prefer it for
#' contiguous cartograms when `cartogramR` is available.
#'
#' Cartograms fail quietly: an under-converged one looks plausible while still
#' misrepresenting the areas it exists to make honest. Pass a larger `itermax`
#' if the result still looks close to the true map.
#'
#' @references
#' Gastner, M. T., Seguy, V. & More, P. (2018). Fast flow-based algorithm for
#' creating density-equalizing map projections. *Proceedings of the National
#' Academy of Sciences* 115(10), E2156-E2164. \doi{10.1073/pnas.1712674115}
#'
#' @param data An `sf` map-ready frame.
#' @param weight The column to resize by (unquoted).
#' @param type `"contiguous"` (default), `"dorling"`, `"noncontiguous"` or
#'   `"flow"`. `"flow"` is the Gastner-Seguy-More flow-based algorithm from the
#'   optional `cartogramR` package -- the current state of the art for
#'   contiguous cartograms, and seconds rather than minutes where the
#'   diffusion-based `"contiguous"` method is slow.
#' @param fill Optional fill column (unquoted); defaults to `weight`.
#' @param projection Projection; an equal-area CRS is recommended. See
#'   [world_map()] for the projections available.
#' @param ... Passed to the underlying `cartogram::cartogram_*()` function
#'   (e.g. `itermax`, or `k` for `type = "dorling"` -- see [dorling_map()]), or
#'   to `cartogramR::cartogramR()` for `type = "flow"`.
#'
#' @param footnote The caption, as in [world_map()]: `"auto"` (default)
#'   states the coverage and source, a string is used as given, `FALSE` adds
#'   nothing.
#' @section Backend:
#' The `sf` backend only: the `cartogram` package distorts `sf` geometry, in
#' `projection` (Equal Earth by default).
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE) &&
#'     requireNamespace("rnaturalearth", quietly = TRUE) &&
#'     requireNamespace("cartogram", quietly = TRUE)) {
#'   attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf") |>
#'     cartogram_map(population, type = "dorling")
#' }
#' }
cartogram_map <- function(data, weight, type = c("contiguous", "dorling",
                                                 "noncontiguous", "flow"),
                          fill = NULL, projection = "equal_earth",
                          footnote = "auto", ...) {
  type <- rlang::arg_match(type)
  # "flow" is cartogramR's algorithm, not cartogram's, so gate on the package
  # the chosen type actually needs rather than demanding both.
  need_pkg(if (identical(type, "flow")) c("cartogramR", "sf") else c("cartogram", "sf"),
           sprintf('for cartogram_map(type = "%s")', type))
  if (!is_sf(data)) wdj_abort("{.fn cartogram_map} needs an sf frame.")
  w_name <- quo_arg_name(rlang::enquo(weight), "weight")
  fill_q <- rlang::enquo(fill)
  fill_name <- if (rlang::quo_is_null(fill_q)) w_name else quo_arg_name(fill_q, "fill")
  check_cols(data, unique(c(w_name, fill_name)))

  check_numeric_col(data, w_name)
  # Cut at the horizon before projecting; see clip_to_hemisphere(). The
  # orthographic transform drops the far side's vertices, and what was left
  # failed inside cartogram as "all sizes are missing and/or non-positive"
  # (Dorling) or "argument must be coercible to non-negative integer"
  # (contiguous). The far side is out of view rather than missing, so it is
  # left out of the cartogram but still counted as covered, as on the globe.
  far <- rep(FALSE, nrow(data))
  if (identical(projection, "orthographic")) {
    data <- clip_to_hemisphere(data, 0, ORTHO_LAT0)
    far <- sf::st_is_empty(data)
  }
  data <- sf::st_transform(data, wdj_crs(projection))
  # A cartogram can only size a country it has a positive weight for, so the
  # rest have to go. That was happening silently, and provenance was then
  # computed on the survivors -- so n_total shrank to match and the map claimed
  # near-complete coverage of a world it had quietly cut down. Measure coverage
  # against the frame as it arrived, and say what could not be sized.
  # is.finite(), not !is.na(): an infinite weight passed this filter and
  # reached cartogram, which rejected the whole frame as "all sizes are missing
  # and/or non-positive", naming neither the country nor the column.
  keep <- is.finite(data[[w_name]]) & data[[w_name]] > 0
  full_cov <- na_coverage(sf_drop(data), fill_name,
                          shown = keep & has_value(data[[fill_name]]))
  # The baseline is "has a value at all", not has_value(): an infinite weight
  # is exactly the case this warning is for, and has_value() would already
  # have counted it missing, leaving the country off without a word.
  lost <- setdiff(full_cov$missing_iso3c,
                  na_coverage(sf_drop(data), fill_name,
                              shown = !is.na(data[[fill_name]]))$missing_iso3c)
  # Only when something survives: if nothing does, the abort below says it
  # better on its own, and warning first just doubles the message.
  if (length(lost) && any(keep)) {
    wdj_warn(c(
      "{length(lost)} countr{?y/ies} ha{?s/ve} no finite, positive
       {.field {w_name}} and cannot be sized, so the cartogram leaves
       {cli::qty(length(lost))}{?it/them} off:",
      "*" = "{.val {utils::head(lost, 8)}}",
      "i" = "A cartogram's area *is* the weight; there is no area to give a
             country the weight is missing for."
    ))
  }
  data <- data[keep & !far, ]
  # cartogram iterates until `if (meanSizeError < maxSizeError) break`, which on
  # an empty frame compares NA and fails with "missing value where TRUE/FALSE
  # needed". Nothing left to weight is worth saying plainly.
  if (!nrow(data)) {
    wdj_abort(c(
      "No country has a positive {.val {w_name}} to size a cartogram by.",
      "i" = "Cartogram weights must be finite and greater than zero."
    ))
  }
  carto <- switch(
    type,
    contiguous = cartogram::cartogram_cont(data, weight = w_name, ...),
    dorling = cartogram::cartogram_dorling(data, weight = w_name, ...),
    noncontiguous = cartogram::cartogram_ncont(data, weight = w_name, ...),
    # cartogramR returns a classed object carrying the deformed geometry plus
    # its own diagnostics; as.sf() is its documented way back to a plain sf
    # frame, and the non-geometry columns have to be reattached because it keeps
    # only the weight.
    flow = {
      cg <- cartogramR::cartogramR(data, count = w_name, ...)
      out <- cartogramR::as.sf(cg)
      sf::st_geometry(data) <- sf::st_geometry(out)
      data
    }
  )
  # `datum = NA`: no graticule. The theme blanks it anyway, and a graticule
  # has nothing to say about a distorted map, but ggplot2 still computed one
  # over the cartogram's bounding box, and at print a contiguous cartogram in
  # Winkel Tripel died on GEOS's "point array must contain 0 or >1 elements".
  p <- ggplot2::ggplot(carto) +
    ggplot2::geom_sf(ggplot2::aes(fill = .data[[fill_name]]),
                     color = "grey30", linewidth = 0.1) +
    ggplot2::coord_sf(datum = NA) +
    auto_fill_scale(carto[[fill_name]], legend_title(data, fill_name)) +
    theme_world_map()
  # Remember what it was weighted by, so cartogram_diagnostics() can check the
  # convergence without being told again -- and the frame itself, so that
  # function does not have to reach into the plot object's data slot. That read
  # went through ggplot2's `$` compatibility layer over its S7 class, which is
  # not something to depend on indefinitely.
  attr(p, "countryatlas_cartogram_weight") <- w_name
  attr(p, "countryatlas_cartogram_data") <- carto
  wdj_provenance(p, sf_drop(carto), fill_name, "sf", projection,
                 style = paste0("cartogram (", type, ")"),
                 extra = list(coverage = full_cov), footnote = footnote)
}

#' Dorling cartogram (first-class verb)
#'
#' Non-overlapping proportional circles sized by `weight`, positioned to stay
#' as close as possible to each country's true location -- arguably the most
#' legible cartogram variant, since a microstate's circle is exactly as
#' visible as a giant country's. A first-class verb for
#' [cartogram_map()]`(type = "dorling")` that surfaces the Dorling-specific
#' tuning knobs.
#'
#' @param data An `sf` map-ready frame.
#' @param weight The column controlling circle size (unquoted).
#' @param fill Optional fill column (unquoted); defaults to `weight`.
#' @param k Share of the bounding box filled by the largest circle (default
#'   `5`; passed to `cartogram::cartogram_dorling()`).
#' @param itermax Maximum iterations of the circle-repulsion algorithm
#'   (default `1000`; raise it if circles still overlap in the result).
#' @param projection Projection; an equal-area CRS is recommended. See
#'   [world_map()] for the projections available.
#'
#' @param footnote The caption, as in [world_map()]: `"auto"` (default)
#'   states the coverage and source, a string is used as given, `FALSE` adds
#'   nothing.
#' @section Backend:
#' The `sf` backend only: the `cartogram` package places its circles from `sf`
#' geometry, in `projection` (Equal Earth by default).
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE) &&
#'     requireNamespace("rnaturalearth", quietly = TRUE) &&
#'     requireNamespace("cartogram", quietly = TRUE)) {
#'   attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf") |>
#'     dorling_map(population)
#' }
#' }
dorling_map <- function(data, weight, fill = NULL, k = 5, itermax = 1000,
                        projection = "equal_earth", footnote = "auto") {
  # Unchecked, these surfaced as cartogram's own diagnostics -- "all sizes are
  # missing and/or non-positive" for k, and an assertion naming cartogram's
  # internal `maxiter` rather than our `itermax`.
  # Bounded above as well as below: check_number() already refuses Inf, but a
  # merely enormous finite k passed and then overflowed the coordinate
  # arithmetic inside GEOS, which surfaced as "IllegalArgumentException:
  # CGAlgorithmsDD::orientationIndex encountered NaN/Inf numbers" -- a bare
  # simpleError from a C++ library, naming neither k nor this function.
  # k = 1e12 still works; only values that cannot produce finite geometry are
  # refused. The cap matches the one the counting arguments elsewhere use.
  check_number(k, "k", lo = 0, hi = .Machine$integer.max)
  check_number(itermax, "itermax", lo = 1, hi = .Machine$integer.max)
  # check_number()'s bounds are inclusive, but cartogram needs k > 0 and reports
  # a zero as "all sizes are missing and/or non-positive". Same shape as
  # simplify_geometry()'s keep guard. Anything above zero is fine (1e-6 works).
  if (k == 0) {
    wdj_abort(c(
      "{.arg k} must be greater than 0.",
      "x" = "A spread factor of {.val {k}} leaves every circle with no size."
    ))
  }
  cartogram_map(data, !!rlang::enquo(weight), type = "dorling",
                fill = !!rlang::enquo(fill), projection = projection,
                footnote = footnote, k = k, itermax = itermax)
}

#' Equal-area world tile grid
#'
#' A statebins-style equal-area tile grid of the world (one square per country)
#' so tiny states are actually visible. Uses the bundled [world_tiles] layout.
#' For small multiples of a tile grid, facet the result as you would any other
#' `ggplot` (or see [facet_map()] for the choropleth equivalent).
#'
#' Every tile in the layout is drawn, taking the scale's `na.value` fill where
#' `data` has no row for it. The converse also holds and is quieter: `data` rows
#' keyed on one of the 3 countries with no tile are dropped without a warning
#' (see [world_tiles] for which).
#'
#' @param data A country-level frame with `iso3c` and the `fill` column.
#' @param fill The fill column (unquoted).
#' @param label Whether to draw ISO codes on the tiles (default `TRUE`).
#'
#' @param footnote The caption, as in [world_map()]: `"auto"` (default)
#'   states the coverage and source, a string is used as given, `FALSE` adds
#'   nothing.
#' @section Backend:
#' Drawn on the bundled equal-area tile grid ([world_tiles]), one square per
#' country; no geometry backend is involved.
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' tile_map(countryatlas::world_snapshot$countries, gdp_per_capita)
#' }
tile_map <- function(data, fill, label = TRUE, footnote = "auto") {
  check_bool(label, "label")
  fill_q <- rlang::enquo(fill)
  fill_name <- quo_arg_name(fill_q, "fill")
  if (!"iso3c" %in% names(data)) {
    wdj_abort("{.arg data} must contain an {.field iso3c} column.")
  }
  check_cols(data, fill_name)
  grid <- countryatlas::world_tiles
  warn_no_geometry_match(data$iso3c, grid$iso3c, "iso3c")
  # One row per country before the join. The grid has exactly one cell per
  # country, so a panel fanned it out -- 239 cells became 659 overlapping ones,
  # each country's tile drawn once per year with the last row winning, and
  # nothing said. The other one-cell-per-country verbs go through the same
  # helper; this one joined the grid directly and was missed.
  # Deduplicated once and reused below: calling distinct_countries() a second
  # time for the coverage would emit its panel warning twice for one call.
  one_per_country <- distinct_countries(tibble::as_tibble(data))
  # An infinity draws as no data here too; see world_map().
  warn_infinite_fill(one_per_country, fill_name)
  # The grid supplies `row` and `col`, and those are common enough column names
  # that a caller's frame may carry its own. They collided in the join below:
  # dplyr suffixed both sides to `.x`/`.y`, and aes(.data$col, -.data$row) then
  # failed with ggplot2's "Problem while computing aesthetics" about a column
  # renamed out from under it. Same fix as drop_centroid_cols() before the
  # centroid joins -- the grid's own coordinates are what this verb draws. The
  # one case that cannot be resolved by dropping is a fill column of that name,
  # which would have to be both the value and a coordinate.
  clash <- intersect(names(one_per_country), c("row", "col"))
  if (fill_name %in% clash) {
    wdj_abort(c(
      "{.arg fill} cannot be {.field {fill_name}}: the tile grid uses that name
       for its own coordinates.",
      "i" = "Rename the column before drawing."
    ))
  }
  one_per_country <- one_per_country[
    , setdiff(names(one_per_country), clash), drop = FALSE]
  tiles <- dplyr::left_join(grid,
                            one_per_country,
                            by = "iso3c", na_matches = "never",
                            relationship = "one-to-one")
  p <- ggplot2::ggplot(tiles, ggplot2::aes(.data$col, -.data$row)) +
    ggplot2::geom_tile(ggplot2::aes(fill = !!quo_col_mapping(fill_name)),
                       color = "white") +
    auto_fill_scale(tiles[[fill_name]], legend_title(data, fill_name),
                    na_value = "grey90") +
    ggplot2::coord_equal() +
    theme_world_map()
  if (isTRUE(label)) {
    p <- p + ggplot2::geom_text(ggplot2::aes(label = .data$iso3c), size = 2.5)
  }
  # The bundled grid does not cover every code -- Hong Kong and Macao have data
  # in the snapshot and no tile -- so counting the input's coded countries as
  # "shown" overstated the map by exactly the ones it could not place, the same
  # way bubble_map() and spike_map() did.
  tile_cov <- centroid_coverage(one_per_country, fill_name, grid$iso3c,
                                "tile in the bundled grid")
  # auto_fill_scale() picks a continuous or a discrete scale from the column's
  # own type, so recording "categorical tile" unconditionally described a
  # numeric fill drawn with scale_fill_viridis_c() as categorical -- in the
  # provenance record whose whole job is to say what was drawn.
  wdj_provenance(p, data, fill_name, "tile-grid", "equal-area tile grid",
                 style = if (is.numeric(tiles[[fill_name]])) {
                   "continuous tile"
                 } else {
                   "categorical tile"
                 },
                 extra = list(coverage = tile_cov), footnote = footnote)
}

#' A small line chart for every country, on the tile grid
#'
#' Every country's trajectory in a panel at once: a sparkline per country,
#' placed on the bundled equal-area [world_tiles] grid, so Europe and the
#' Caribbean are as readable as Russia. It is the glyph-map idea (Wickham,
#' Hofmann, Wickham & Cook 2012) on a grid of equal cells, which removes the
#' overlap glyphs at country centroids suffer where countries are small and
#' close together.
#'
#' @param data A panel with `iso3c`, `year` and the `value` column, one row
#'   per country and year.
#' @param value The column to draw (unquoted).
#' @param years Optional years to draw: a range `c(from, to)`, or the years
#'   themselves. `NULL` (default) draws every year in `data`.
#' @param label Whether to print each tile's ISO code (default `TRUE`).
#' @param scales `"free_y"` (default) draws each country on its own scale, so
#'   every line shows its own shape; `"fixed"` puts every country on one
#'   scale, so the lines can be compared in level as well as shape. The
#'   subtitle says which.
#' @param footnote The caption, as in [world_map()]: `"auto"` (default) says
#'   how many countries have a line.
#'
#' @section Backend:
#' Drawn on the bundled equal-area tile grid ([world_tiles]), one square per
#' country; no geometry backend is involved.
#'
#' @return A `ggplot` object. A country needs two years with values to have a
#'   line; one with fewer, or with no tile (see [world_tiles]), counts as
#'   missing in the caption and in [map_provenance()].
#' @references
#' Wickham, H., Hofmann, H., Wickham, C. & Cook, D. (2012). Glyph-maps for
#' visually exploring temporal patterns in climate data and models.
#' *Environmetrics* 23(5), 382-393. \doi{10.1002/env.2152}
#' @seealso [tile_map()] for one value per country, [facet_map()]
#' @export
#' @examples
#' \donttest{
#' set.seed(1)
#' pan <- expand.grid(iso3c = countryatlas::world_tiles$iso3c, year = 2000:2020)
#' pan$v <- stats::ave(stats::rnorm(nrow(pan)), pan$iso3c, FUN = cumsum)
#' tile_trend_map(pan, v)
#' }
tile_trend_map <- function(data, value, years = NULL, label = TRUE,
                           scales = c("free_y", "fixed"), footnote = "auto") {
  check_bool(label, "label")
  scales <- rlang::arg_match(scales)
  val_name <- quo_arg_name(rlang::enquo(value), "value")
  check_cols(data, c("iso3c", "year", val_name))
  check_numeric_col(data, val_name)
  check_numeric_col(data, "year")
  df <- tibble::as_tibble(sf_drop(data))
  df <- df[!is.na(df$iso3c) & is.finite(df$year), c("iso3c", "year", val_name),
           drop = FALSE]
  if (!is.null(years)) {
    if (!is.numeric(years) || !length(years) || anyNA(years)) {
      wdj_abort("{.arg years} must be a numeric range or vector of years.")
    }
    df <- if (length(years) == 2L) {
      df[df$year >= min(years) & df$year <= max(years), , drop = FALSE]
    } else {
      df[df$year %in% years, , drop = FALSE]
    }
  }
  if (anyDuplicated(df[, c("iso3c", "year")])) {
    wdj_abort(c(
      "{.arg data} has more than one row for some country and year.",
      "i" = "A sparkline needs one value per country and year; summarise
             first."
    ))
  }
  grid <- countryatlas::world_tiles
  warn_no_geometry_match(df$iso3c, grid$iso3c, "iso3c")
  # An empty frame draws the bare grid; range() of nothing warned twice and
  # put Inf in the subtitle.
  yr <- if (nrow(df)) range(df$year) else c(NA_real_, NA_real_)
  pts <- dplyr::inner_join(df[is.finite(df[[val_name]]), , drop = FALSE],
                           grid[, c("iso3c", "row", "col")], by = "iso3c",
                           na_matches = "never", relationship = "many-to-one")
  n_years <- table(pts$iso3c)
  pts <- pts[pts$iso3c %in% names(n_years)[n_years >= 2L], , drop = FALSE]
  pts <- pts[order(pts$iso3c, pts$year), , drop = FALSE]
  v <- pts[[val_name]]
  if (identical(scales, "fixed") && length(v)) {
    lo <- rep(min(v), length(v))
    hi <- rep(max(v), length(v))
  } else {
    lo <- stats::ave(v, pts$iso3c, FUN = min)
    hi <- stats::ave(v, pts$iso3c, FUN = max)
  }
  span <- if (all(is.finite(yr)) && diff(yr) > 0) diff(yr) else 1
  pts$.x <- pts$col - 0.42 + 0.84 * (pts$year - yr[1]) / span
  pts$.y <- -pts$row - 0.3 + 0.6 * ifelse(hi > lo, (v - lo) / (hi - lo), 0.5)
  p <- ggplot2::ggplot() +
    ggplot2::geom_tile(data = grid, ggplot2::aes(.data$col, -.data$row),
                       fill = "grey94", colour = "white", width = 0.96,
                       height = 0.96) +
    ggplot2::geom_path(data = pts, ggplot2::aes(.data$.x, .data$.y,
                                                group = .data$iso3c),
                       colour = "#2166AC", linewidth = 0.35) +
    ggplot2::coord_equal() +
    ggplot2::labs(subtitle = sprintf(
      "%s, %s; %s", gsub("\n", " ", legend_title(data, val_name)),
      if (!all(is.finite(yr))) "no years" else if (yr[2] > yr[1])
        paste0(yr[1], "-", yr[2]) else yr[1],
      if (identical(scales, "fixed")) "one scale for every country"
      else "each country on its own scale")) +
    theme_world_map()
  if (isTRUE(label)) {
    p <- p + ggplot2::geom_text(
      data = grid, ggplot2::aes(.data$col - 0.44, -.data$row + 0.44,
                                label = .data$iso3c),
      size = 1.6, hjust = 0, vjust = 1, colour = "grey45")
  }
  # A country with data but no tile is named, as tile_map() names it; one
  # with too few years for a line counts as missing without a word.
  one <- tibble::tibble(iso3c = unique(df$iso3c))
  has_data <- one$iso3c %in% df$iso3c[is.finite(df[[val_name]])]
  one[[val_name]] <- rep(NA_real_, nrow(one))
  one[[val_name]][has_data] <- 1
  invisible(centroid_coverage(one, val_name, grid$iso3c,
                              "tile in the bundled grid"))
  cov <- na_coverage(one, val_name, shown = one$iso3c %in% pts$iso3c)
  wdj_provenance(p, data, val_name, "tile-grid", "equal-area tile grid",
                 style = "tile sparkline",
                 extra = list(coverage = cov, scales = scales, years = yr),
                 footnote = footnote)
}

#' One square per N people
#'
#' A gridded (or "waffle") cartogram: the world redrawn as equal cells, each
#' worth a fixed quantity, allocated to countries in proportion to their value
#' and placed near where they belong. Where a Dorling cartogram preserves
#' position and a contiguous one preserves adjacency, this preserves
#' *countability* -- the reader can literally count the cells.
#'
#' @param data A country-level or map-ready frame with `iso3c`.
#' @param value The column to allocate cells by (unquoted).
#' @param cells Total number of cells to distribute (default `1000`). Each cell
#'   is then worth `sum(value) / cells`.
#' @param fill Optional fill column (unquoted); defaults to `value`.
#' @param cell_size Grid spacing in degrees of latitude (default `2.5`). On a
#'   projected map the cells are laid out in the projection's own units at
#'   that ground distance (one degree is about 111 km), so every cell is the
#'   same square wherever it stands.
#' @param projection Where the blocks are placed: a projection as in
#'   [world_map()] (default `"equal_earth"`), or `"none"` for the unprojected
#'   grid of 3.0.0.
#'
#' @param footnote The caption, as in [world_map()]: `"auto"` (default)
#'   states the coverage and source, a string is used as given, `FALSE` adds
#'   nothing.
#' @section Backend:
#' The cells are laid out from the bundled centroids in `projection` (Equal
#' Earth by default), so it needs no geometry backend and no `sf`.
#'
#' @return A `ggplot` object. The per-country cell allocation is attached as the
#'   `"countryatlas_cells"` attribute -- every placeable country, including the
#'   ones that rounded to zero cells, so `share` sums to 1 and the rounding is
#'   fully visible.
#'
#' @section Rounding is the whole difficulty:
#' Allocating a whole number of cells to each country cannot be exact, so the
#' remainder has to go somewhere. This uses the largest-remainder method, which
#' guarantees the cell total is exactly `cells` and that no country with a
#' positive value gets zero cells while a smaller one gets one. The attached
#' table reports each country's exact share alongside its integer allocation so
#' the rounding is inspectable rather than hidden.
#'
#' @section Crowded neighbours overlap:
#' Each country's block is centred on its own centroid, with no collision
#' avoidance between countries. That is deliberate -- a global packing solve
#' would push countries away from where they belong -- but it means blocks in
#' crowded regions are drawn on top of one another, and a partly hidden block
#' cannot be counted or compared. The effect is not marginal: at the defaults
#' (`cells = 1000`, `cell_size = 2.5`) about two fifths of the cells overlap a
#' cell of a different country, across some eighty countries, and it grows
#' with `cells` -- at `cells = 2500` it is roughly 70%.
#'
#' `cell_size` is the lever, because it scales the tiles without moving the
#' centroids: dropping it to `1.5` cuts the overlap at `cells = 1000` to about
#' a sixth of the cells. Fewer `cells` also helps. Where exact areas matter
#' more than geographic position, [dorling_map()] resolves collisions by
#' displacing circles instead.
#'
#' @seealso [cartogram_map()], [dorling_map()], [tile_map()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' gridded_cartogram(snap, population, cells = 400)
#' }
gridded_cartogram <- function(data, value, cells = 1000, fill = NULL,
                              cell_size = 2.5, projection = "equal_earth",
                              footnote = "auto") {
  value_q <- rlang::enquo(value)
  val_name <- quo_arg_name(value_q, "value")
  fill_q <- rlang::enquo(fill)
  check_number(cells, "cells", lo = 1, hi = 1e6)
  check_number(cell_size, "cell_size", lo = 0.1, hi = 30)
  pc <- wdj_polygon_coord(projection)
  cells <- as.integer(cells)
  if (!"iso3c" %in% names(data)) {
    wdj_abort("{.arg data} must contain an {.field iso3c} column.")
  }
  check_cols(data, val_name)
  check_numeric_col(data, val_name)

  df <- distinct_countries(tibble::as_tibble(sf_drop(data)))
  df <- df[!is.na(df$iso3c), ]
  fill_name <- if (rlang::quo_is_null(fill_q)) val_name else quo_arg_name(fill_q, "fill")
  check_cols(df, fill_name)
  # Held back so coverage can be measured against the frame as it arrived. The
  # two filters below drop countries the grid cannot represent, and provenance
  # was computed on whatever survived them -- so n_total shrank to match and a
  # grid covering 94 of 215 countries reported "94 of 94".
  df_all <- df
  usable <- is.finite(df[[val_name]]) & df[[val_name]] > 0
  # As in cartogram_map(): when nothing is usable the abort below is the whole
  # story, so do not warn first.
  if (any(!usable) && any(usable)) {
    wdj_warn(c(
      "{sum(!usable)} countr{?y/ies} ha{?s/ve} no finite, positive
       {.field {val_name}} and {cli::qty(sum(!usable))}{?gets/get} no cells:",
      "*" = "{.val {utils::head(sort(df$iso3c[!usable]), 8)}}",
      "i" = "A gridded cartogram allocates cells in proportion to the value,
             so there is no share to give without one."
    ))
  }
  df <- df[usable, ]
  if (!nrow(df)) {
    wdj_abort(c("No country has a positive {.val {val_name}} to allocate cells by.",
                "i" = "Gridded cartograms need positive weights."))
  }

  # Attach centroids and drop the unplaceable countries *before* allocating.
  # Allocating first and filtering after leaked cells: a country with no bundled
  # centroid still won its share, then vanished with it, so `cells = 997` laid
  # out 996 and the caption's "1 cell = N people" quietly stopped being true.
  cent <- countryatlas::country_meta[, c("iso3c", "centroid_lon", "centroid_lat")]
  # drop_centroid_cols() first, as bubble_map() and spike_map() do before the
  # same join. country_meta carries `centroid_lon`/`centroid_lat`, so a caller
  # who joined it for capitals or area already has those columns -- dplyr then
  # suffixed both sides to `.x`/`.y`, `df$centroid_lon` became NULL, and the
  # filter below failed with vctrs' "Can't subset rows with
  # `is.na(df$centroid_lon) | ...`" rather than anything about countries.
  df <- drop_centroid_cols(df)
  df <- dplyr::left_join(df, cent, by = "iso3c", na_matches = "never",
                         relationship = "many-to-one")
  # The blocks are laid out in the projection's own metres, so a cell is the
  # same square everywhere; "none" and orthographic lay them out in degrees.
  xy <- polygon_metres(df$centroid_lon, df$centroid_lat, pc)
  unit <- if (is.null(xy)) 1 else METRES_PER_DEGREE
  if (!is.null(xy)) {
    df$centroid_lon <- xy$x
    df$centroid_lat <- xy$y
  }
  lost <- df[is.na(df$centroid_lon) | is.na(df$centroid_lat), ]
  df <- df[!is.na(df$centroid_lon) & !is.na(df$centroid_lat), ]
  if (!nrow(df)) wdj_abort("No country has both a positive weight and a bundled centroid.")
  if (nrow(lost)) {
    wdj_warn(c(
      "{nrow(lost)} countr{?y/ies} ha{?s/ve} no bundled centroid and cannot be
       placed on the grid.",
      "*" = "{.val {utils::head(sort(lost$iso3c), 8)}}",
      "i" = "Their weight is excluded, so the cells shown cover
             {.val {round(100 * sum(df[[val_name]]) / (sum(df[[val_name]]) + sum(lost[[val_name]])), 1)}}% of the total."
    ))
  }

  # Largest-remainder allocation: floor everybody, then hand the leftover cells
  # to the largest fractional parts. Exact total, and no country rounded to
  # nothing while a smaller one keeps a cell.
  df$.wdj_share <- df[[val_name]] / sum(df[[val_name]])
  exact <- df$.wdj_share * cells
  n <- floor(exact)
  left <- cells - sum(n)
  if (left > 0) {
    ord <- order(exact - n, decreasing = TRUE)
    n[ord[seq_len(left)]] <- n[ord[seq_len(left)]] + 1L
  }
  df$.wdj_cells <- as.integer(n)
  # Keep the zero-cell countries in the reported table and drop them only from
  # the drawing. Which countries rounded away is exactly what the table exists
  # to show, and excluding them made `share` sum to less than 1.
  drawn <- df[df$.wdj_cells > 0, ]
  # Not currently reachable, and kept deliberately: the largest-remainder
  # allocation above hands out exactly `cells` cells and `cells` is validated
  # lo = 1, so at least one country always keeps one -- a single-country frame
  # gets all of them however small its weight. The guard stays because it is
  # the allocation that guarantees this, and an allocation is the kind of thing
  # that gets rewritten. (An earlier comment here claimed the single-country
  # case lands in it; it does not.)
  if (!nrow(drawn)) {
    wdj_abort(c(
      "Every country rounded to zero cells.",
      "i" = "Raise {.arg cells}: there {cli::qty(nrow(df))}{?is/are} {nrow(df)}
             countr{?y/ies} to place."
    ))
  }

  # Lay each country's cells out as a compact block on the grid, centred on its
  # centroid. Overlap between crowded neighbours is possible and preferable to
  # a global packing solve, which would move countries far from where they are.
  step <- cell_size * unit
  blocks <- lapply(seq_len(nrow(drawn)), function(i) {
    k <- drawn$.wdj_cells[i]
    w <- ceiling(sqrt(k))
    idx <- seq_len(k) - 1L
    tibble::tibble(
      iso3c = drawn$iso3c[i],
      x = drawn$centroid_lon[i] + ((idx %% w) - (w - 1) / 2) * step,
      y = drawn$centroid_lat[i] - ((idx %/% w) - (ceiling(k / w) - 1) / 2) * step,
      .wdj_fill = drawn[[fill_name]][i]
    )
  })
  grid <- dplyr::bind_rows(blocks)

  per_cell <- sum(df[[val_name]]) / cells
  tiles <- if (!is.null(pc$crs)) {
    # coord_sf() reads ordinary layers as longitude/latitude, so cells laid out
    # in metres go in as sf squares, in the map's own CRS.
    half <- step * 0.45
    sq <- lapply(seq_len(nrow(grid)), function(i) {
      x <- grid$x[i]; y <- grid$y[i]
      sf::st_polygon(list(cbind(c(x - half, x + half, x + half, x - half, x - half),
                                c(y - half, y - half, y + half, y + half, y - half))))
    })
    ggplot2::geom_sf(data = sf::st_sf(.wdj_fill = grid$.wdj_fill,
                                      geometry = sf::st_sfc(sq, crs = pc$crs)),
                     ggplot2::aes(fill = .data$.wdj_fill), color = NA,
                     inherit.aes = FALSE)
  } else {
    ggplot2::geom_tile(ggplot2::aes(.data$x, .data$y, fill = .data$.wdj_fill),
                       data = grid, width = step * 0.9, height = step * 0.9)
  }
  p <- ggplot2::ggplot(grid) +
    tiles +
    auto_fill_scale(grid$.wdj_fill, legend_title(data, fill_name)) +
    pc$coord +
    ggplot2::labs(caption = sprintf("1 cell = %s %s.",
                                    si_label(signif(per_cell, 3)), val_name)) +
    theme_world_map()
  # share travels in `df`, so it stays aligned with the rows that survived the
  # centroid filter. Indexing a separately-computed vector by match(x, x) -- the
  # identity permutation -- silently kept the wrong values, and the shares
  # summed to 0.69 rather than 1.
  attr(p, "countryatlas_cells") <- tibble::tibble(
    iso3c = df$iso3c, value = df[[val_name]], share = df$.wdj_share,
    cells = df$.wdj_cells
  )
  # `shown` is exactly the set that survived both filters, so the count matches
  # what the grid actually draws while the denominator stays the whole input.
  wdj_provenance(p, df_all, fill_name, "grid", pc$label,
                 style = paste0("gridded cartogram, ", cells, " cells"),
                 extra = list(coverage = na_coverage(
                   df_all, fill_name, shown = df_all$iso3c %in% df$iso3c)),
                 footnote = footnote)
}

#' Did the cartogram actually converge?
#'
#' Cartograms fail quietly. An under-converged one looks entirely plausible
#' while still misrepresenting the areas it exists to make honest. This reports
#' the residual error per country, so the failure is visible.
#'
#' @param x A `ggplot` from [cartogram_map()] or [dorling_map()], or the `sf`
#'   frame the cartogram was computed from.
#' @param weight The weight column (unquoted). Required when `x` is a plain `sf`
#'   frame; read from the plot otherwise.
#'
#' @return A tibble of `iso3c`, `target_share` (the country's share of the
#'   weight), `actual_share` (its share of the cartogram's area) and
#'   `area_error` (the relative difference). The summary -- mean absolute error,
#'   worst country -- is attached as the `"countryatlas_cartogram"` attribute.
#'
#' @section What counts as converged:
#' A perfect cartogram has `area_error` of 0 everywhere. In practice a mean
#' absolute error under a few percent is good and under 10% is usually
#' acceptable; a systematically large error, or one concentrated in the small
#' countries, means the algorithm stopped early. Raise `itermax` and try again.
#'
#' @seealso [cartogram_map()], [dorling_map()], [gridded_cartogram()]
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE) &&
#'     requireNamespace("cartogram", quietly = TRUE) &&
#'     requireNamespace("rnaturalearth", quietly = TRUE)) {
#'   sfd <- attach_geometry(countryatlas::world_snapshot$countries,
#'                          geometry = "sf")
#'   cg <- cartogram_map(sfd, population)
#'   cartogram_diagnostics(cg)
#' }
#' }
cartogram_diagnostics <- function(x, weight = NULL) {
  need_pkg("sf", "for cartogram_diagnostics()")
  weight_q <- rlang::enquo(weight)
  geom <- NULL
  w_name <- NULL
  if (inherits(x, "ggplot")) {
    # The attribute first, the data slot only as a fallback -- a plot built by
    # an older version of the package carries the weight name but not the
    # frame.
    geom <- attr(x, "countryatlas_cartogram_data") %||% gg_plot_data(x)
    prov <- attr(x, "countryatlas_cartogram_weight")
    w_name <- if (!rlang::quo_is_null(weight_q)) quo_arg_name(weight_q, "weight") else prov
    if (is.null(w_name)) {
      wdj_abort(c(
        "Cannot tell which column the cartogram was weighted by.",
        "i" = "Pass it as {.arg weight}."
      ))
    }
  } else if (is_sf(x)) {
    geom <- x
    if (rlang::quo_is_null(weight_q)) {
      wdj_abort("{.arg weight} is required when {.arg x} is an sf frame.")
    }
    w_name <- quo_arg_name(weight_q, "weight")
  } else {
    wdj_abort(c(
      "{.arg x} must be a cartogram plot or an sf frame.",
      "x" = "Got {.cls {class(x)[1]}}."
    ))
  }
  if (!is_sf(geom)) {
    wdj_abort("The plot's data is not an sf frame; this is not a cartogram.")
  }
  check_cols(geom, w_name, arg = "x")
  # An invalid ring makes s2 refuse st_area() outright, and its message --
  # "Loop 0 is not valid: Edge 0 crosses edge 2" -- names neither the country
  # nor the package, so a caller with one broken polygon had nothing to go on.
  # country_borders() and get_world_sf() hit the same wall and drop to GEOS's
  # planar predicate; an *area* is what this function reports, though, so
  # silently switching engines would change the numbers. Name the rows instead.
  area <- tryCatch(as.numeric(quietly_sf(sf::st_area(geom))),
                   error = function(e) {
    bad <- tryCatch(which(!sf::st_is_valid(geom)), error = function(e2) integer())
    who <- if (length(bad) && "iso3c" %in% names(geom)) {
      utils::head(geom$iso3c[bad], 4)
    } else if (length(bad)) {
      paste0("row ", utils::head(bad, 4))
    } else NULL
    wdj_abort(c(
      "Could not measure the geometry in {.arg x}.",
      "x" = if (!is.null(who)) {
        "{length(bad)} geometr{?y/ies} {?is/are} invalid: {.val {who}}."
      } else "The geometry engine rejected it: {conditionMessage(e)}",
      "i" = "Repair it with {.code sf::st_make_valid()} first."
    ), call = verb_env(), class = "countryatlas_invalid_geometry")
  })
  w <- geom[[w_name]]
  ok <- is.finite(area) & is.finite(w) & w > 0
  out <- tibble::tibble(
    iso3c = if ("iso3c" %in% names(geom)) geom$iso3c else NA_character_,
    target_share = ifelse(ok, w / sum(w[ok]), NA_real_),
    actual_share = ifelse(ok, area / sum(area[ok]), NA_real_)
  )
  out$area_error <- (out$actual_share - out$target_share) / out$target_share
  out <- dplyr::arrange(out, dplyr::desc(abs(.data$area_error)))
  # Guarded on sum(ok): with no usable row -- an all-NA or all-non-positive
  # weight column, both reachable through the documented entry point --
  # max(numeric(0)) returned -Inf *and* leaked base R's "no non-missing
  # arguments to max", mean() returned NaN, and `worst` named whichever country
  # happened to sort first. Report the emptiness instead of three numbers that
  # describe nothing.
  attr(out, "countryatlas_cartogram") <- if (!sum(ok)) {
    tibble::tibble(n = 0L, mean_abs_error = NA_real_, max_abs_error = NA_real_,
                   worst = NA_character_)
  } else {
    tibble::tibble(
      n = sum(ok),
      mean_abs_error = mean(abs(out$area_error), na.rm = TRUE),
      max_abs_error = max(abs(out$area_error), na.rm = TRUE),
      worst = out$iso3c[1]
    )
  }
  if (!sum(ok)) {
    wdj_warn(c(
      "No country has a usable {.field {w_name}}, so no area error could be
       measured.",
      "i" = "A cartogram's target share needs a finite, positive weight."
    ), class = "countryatlas_no_usable_weight")
  }
  out
}
