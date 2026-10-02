# Maps: the choropleth core -------------------------------------------------
#
# world_map() and what every polygon-fill verb shares with it: the theme, the
# classification, the fill scales and the coverage counting.

#' A clean theme for world maps
#'
#' Strips axes, panel grid and background so the map is the focus. Applied by
#' every plotting function in the package except [bivariate_map()], which uses
#' `biscale::bi_theme()` so the map matches its own legend, and exported here for
#' reuse on plots you build yourself.
#'
#' @param base_size Base font size.
#' @param base_family Base font family.
#' @return A `ggplot2` theme object.
#' @export
#' @examples
#' library(ggplot2)
#' ggplot() + theme_world_map()
theme_world_map <- function(base_size = 12, base_family = "") {
  # Both feed ggplot2's own arithmetic and font lookup, so a non-number
  # surfaced as base R's bare "non-numeric argument to binary operator" and a
  # non-string got no check at all.
  check_number(base_size, "base_size", lo = 0)
  check_string(base_family, "base_family", allow_empty = TRUE)
  ggplot2::theme_minimal(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      axis.title = ggplot2::element_blank(),
      axis.text = ggplot2::element_blank(),
      axis.ticks = ggplot2::element_blank(),
      panel.grid = ggplot2::element_blank(),
      panel.background = ggplot2::element_blank(),
      legend.position = "right",
      plot.title = ggplot2::element_text(face = "bold")
    )
}

# Is this an sf object?
is_sf <- function(x) inherits(x, "sf")

#' One-line choropleth, several honest styles
#'
#' Encapsulates the choropleth boilerplate and goes beyond a single style.
#' Auto-detects the polygon vs `sf` backend, applies [theme_world_map()], and
#' projects the map (Equal Earth by default). Classes are the default because
#' a continuous fill on a skewed indicator hides almost all the variation;
#' binning is the honest default for choropleths, and quantiles the safe
#' choice for a general audience.
#'
#' @param data A map-ready frame from [world_data()] / [join_world()] (polygon
#'   tibble or `sf`).
#' @param fill The fill column (unquoted).
#' @param style How the fill is classified: `"quantile"` (default),
#'   `"continuous"` (a colourbar), `"binned"` or its alias `"equal"` (equal
#'   intervals, drawn as a stepped colourbar), `"jenks"` and `"fisher"` (natural
#'   breaks; both need `classInt`), `"headtails"` (Jiang 2013, for heavy-tailed
#'   variables such as GDP and population; it chooses its own number of
#'   classes), `"sd"` (the mean plus or minus whole and half standard
#'   deviations), `"fixed"` (the classes given in `breaks`, which implies it) or
#'   `"categorical"` for a discrete column. Pass `style = "continuous"` for the
#'   3.0.0 default.
#' @param projection Any of the projections in [projection_info()]:
#'   `"equal_earth"` (default), `"robinson"`, `"mollweide"`,
#'   `"natural_earth"`, `"plate_carree"`, `"mercator"`, `"winkel_tripel"`,
#'   `"eckert4"`, `"gall_peters"`, `"orthographic"`, `"azimuthal_equal_area"`,
#'   `"north_polar"` or `"south_polar"`; or `"none"` for unprojected
#'   longitude/latitude, the polygon backend's output before 4.0.0. Both
#'   backends project; see *Projections on the polygon backend* below.
#' @param palette Optional palette: a viridis option (`"viridis"`, the default,
#'   `"magma"`, `"cividis"`, ...) or any base R HCL palette
#'   ([grDevices::hcl.pals()]), such as the diverging `"RdBu"`.
#' @param n_bins Number of classes for the classed styles.
#' @param breaks Fixed class boundaries: a sorted, unique numeric vector of at
#'   least two values, for thresholds that mean something (the World Bank's
#'   income thresholds) and for maps that must be comparable across years and
#'   publications. Implies `style = "fixed"`. Classes close on the left, so
#'   `c(1136, 4466)` puts 1,136 in the first class. Values outside the range go
#'   in open end classes, labelled `"< 1.14K"` and `">= 4.47K"`, with a warning
#'   (class `countryatlas_breaks_open`) unless `breaks` starts with `-Inf` or
#'   ends with `Inf`.
#' @param midpoint A value to centre a diverging palette on: zero growth, a
#'   target, a threshold. On a colourbar the scale is rescaled so `midpoint`
#'   takes the neutral colour; with classes, a break is forced there and the
#'   classes either side take the two arms of the palette. The palette
#'   defaults to `"RdBu"`; a sequential one is refused (class
#'   `countryatlas_palette_not_diverging`).
#' @param borders Draw country borders (default `TRUE`).
#' @param title,legend Optional plot title and legend title.
#' @param na_label Legend key label for missing data, used by the styles with
#'   a discrete legend (`"quantile"`, `"jenks"`, `"categorical"`); the
#'   continuous and binned colourbars have no `NA` key to name. Honoured by
#'   both engines. A length-1 `NA` leaves the engine's own formatter alone.
#' @param recenter Optional central meridian (e.g. `150` for a Pacific-centred
#'   map), on either backend.
#' @param na_style How to draw countries with no data: `"grey"` (default),
#'   `"hatched"` (diagonal hatching via the optional `ggpattern`, unmistakable
#'   and greyscale-safe; grey, with a message, when `ggpattern` or the `sf` it
#'   draws with cannot be loaded), `"outline"` (white fill, keeping only the
#'   border) or `"omit"` (do not draw them at all). See the section below.
#' @param footnote The caption. `"auto"` (default) states the coverage
#'   ("174 of 195 countries shown; 21 missing") and, where the data carries a
#'   [source_info()] record, the source, so the map cannot quietly overstate
#'   what it covers. A string is used verbatim; `FALSE` (or `NULL`) adds
#'   nothing.
#' @param uncertainty Optional uncertainty column (unquoted) -- a standard
#'   error, a confidence half-width, anything where larger means less certain.
#'   Supplying it switches the fill to a **value-suppressing uncertainty
#'   palette** (Correll, Moritz & Heer 2018): the value range contracts as
#'   uncertainty rises, so an uncertain estimate cannot claim an extreme colour,
#'   and the legend becomes the value x uncertainty grid.
#' @param n_uncertainty Number of uncertainty levels for the VSUP (default `3`).
#' @param engine `"ggplot2"` (default) or `"tmap"`. The package is
#'   ggplot2-native; the `tmap` path is an alternative renderer for people
#'   already working in tmap, and needs an `sf` frame. It honours `style`,
#'   `n_bins`, `palette`, `title` and `legend`, and ignores the ggplot2-specific
#'   arguments.
#' @param disputes `"ignore"` (default) or `"mark"`, which outlines the
#'   [disputed_territories] present in the data and notes the convention in the
#'   caption. See [dispute_policy()].
#' @param small_states What to do with countries too small to see, or missing
#'   from the basemap: `"auto"` (default) draws a country that has a value but
#'   no polygon -- most small states on the `sf` backend at its default
#'   1:110m -- as a filled point at its centroid, on the same fill scale;
#'   `"dots"` also adds a point over every country smaller than
#'   `small_area_km2`; `"none"` drops them, as 3.0.0 did. The caption counts
#'   the points, and names any country with neither a polygon nor a centroid.
#' @param small_area_km2 The area under which `small_states = "dots"` adds a
#'   point (default `1000` square kilometres).
#' @param classification_report If `TRUE`, attach the breaks, the method and
#'   the count of countries per class to the returned plot as the
#'   `"countryatlas_classification"` attribute, and print them with
#'   [map_provenance()]. A map whose top class holds one country and whose
#'   bottom holds ninety is misleading, and the counts say so immediately.
#'   `style = "continuous"` draws a colourbar and so has no classes to report:
#'   there the attribute is `NULL` and a warning says why.
#'
#' @return A `ggplot` object.
#'
#' @section Missing data is not zero:
#' The default grey reads as "low" to many people, which is exactly wrong for
#' "unknown". `na_style = "hatched"` draws diagonal hatching instead --
#' unambiguous, and it survives greyscale printing. `"omit"` leaves a hole,
#' which is honest but can be mistaken for ocean. Whichever you pick,
#' `footnote = "auto"` states the count in words:
#' ```r
#' world_map(mapdf, gdp_per_capita, na_style = "hatched", footnote = "auto")
#' ```
#' [coverage_map()] goes further and maps availability itself.
#'
#' @section Projections on the polygon backend:
#' The polygon backend (the default of [attach_geometry()], [world_data()] and
#' [join_world()]) keeps its frame in longitude and latitude and is projected
#' when it is drawn. Where `sf` can be loaded that is
#' [ggplot2::coord_sf()] with `default_crs = sf::st_crs(4326)`, so any layer
#' you add in longitude and latitude is projected with the map, point by
#' point: the map's own outlines are dense, so a segment is drawn straight
#' between its two projected ends rather than re-interpolated, and a long line
#' of your own needs points along it to follow the projection. Where it
#' cannot, Equal Earth is computed by the package itself, on the sphere, and
#' the vertices are drawn in metres under [ggplot2::coord_fixed()]; place your
#' own layers on that map with [project_lonlat()], and zoom with [zoom_map()],
#' which keeps the projection where `coord_quickmap(xlim, ylim)` would replace
#' it. Another projection without `sf` falls back to that Equal Earth with a
#' warning (class `countryatlas_projection_fallback`). `"orthographic"` draws
#' through [ggplot2::coord_map()] and needs `mapproj`. [map_provenance()]
#' records which of these drew the map: `"equal_earth"`, `"equal_earth
#' (spherical, built-in)"` or `"none"`.
#'
#' @section Choosing a classification:
#' The classification changes what readers conclude, and not by a little.
#' Brewer & Pickle's 56-subject study over nine map series found **quantiles**
#' among the best methods for general choropleth reading, and natural breaks
#' (Jenks) below 70% as accurate -- the opposite of the common GIS default.
#' `style = "quantile"` is therefore the safe choice for a general audience.
#' Jenks earns its place on strongly clustered distributions, where quantiles
#' would split a natural group across two colours. Use [classify_compare()] to
#' see the difference on your own data before committing.
#'
#' @references
#' Brewer, C. A. & Pickle, L. (2002). Evaluation of methods for classifying
#' epidemiological data on choropleth maps in series. *Annals of the
#' Association of American Geographers* 92(4), 662-681.
#' \doi{10.1111/1467-8306.00310}
#'
#' Correll, M., Moritz, D. & Heer, J. (2018). Value-suppressing uncertainty
#' palettes. *Proceedings of the 2018 CHI Conference on Human Factors in
#' Computing Systems*, 1-11. \doi{10.1145/3173574.3174216}
#'
#' @seealso [classify_compare()], [coverage_map()], [projection_compare()],
#'   [map_provenance()], [dispute_policy()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' mapdf <- attach_geometry(snap, geometry = "polygon")
#' world_map(mapdf, gdp_per_capita, style = "quantile")
#' }
world_map <- function(data, fill,
                      style = c("quantile", "continuous", "binned", "equal",
                                "jenks", "fisher", "headtails", "sd", "fixed",
                                "categorical"),
                      projection = "equal_earth",
                      palette = NULL, n_bins = 5, breaks = NULL,
                      midpoint = NULL, borders = TRUE,
                      title = NULL, legend = NULL, na_label = "No data",
                      recenter = NULL,
                      na_style = c("grey", "hatched", "outline", "omit"),
                      footnote = "auto", classification_report = FALSE,
                      uncertainty = NULL, n_uncertainty = 3,
                      disputes = c("ignore", "mark"),
                      small_states = c("auto", "none", "dots"),
                      small_area_km2 = 1000,
                      engine = c("ggplot2", "tmap")) {
  engine <- rlang::arg_match(engine)
  check_bool(borders, "borders")
  check_bool(classification_report, "classification_report")
  disputes <- rlang::arg_match(disputes)
  check_label_args(palette, title, legend, na_label)
  style_given <- !missing(style)
  style <- rlang::arg_match(style)
  na_style <- rlang::arg_match(na_style)
  small_states <- rlang::arg_match(small_states)
  check_number(small_area_km2, "small_area_km2", lo = 0)
  footnote_given <- !missing(footnote)
  fill_q <- rlang::enquo(fill)
  fill_name <- quo_arg_name(fill_q, "fill")

  check_cols(data, fill_name)
  check_map_geometry(data)
  style <- resolve_style(style, style_given, breaks, midpoint, n_bins,
                         data[[fill_name]])

  # Validated before the engine hand-off below, not after it. The tmap branch
  # returns early and passed `n_bins` straight to tm_scale_intervals(), which
  # coerces with as.integer() -- so n_bins = 1e18 became NA there, and a string
  # was accepted, while every other path rejected both. Same shape as the
  # globe_map(interactive = TRUE) hand-off that was fixed for arg_match() and
  # check_label_args(): validate first, dispatch second. The drawing path
  # downstream validates it too; an unusable value should get that error and
  # not a notice that the argument it just rejected does not apply.
  check_number(n_bins, "n_bins", lo = 2, hi = .Machine$integer.max)
  sf_mode <- is_sf(data)
  check_categorical_fill(style, data[[fill_name]], fill_name)

  if (identical(engine, "tmap")) {
    # This engine used ten of world_map()'s arguments and dropped the rest
    # without a word. `na_label`, `projection` and `recenter` are now passed
    # through; what is left is genuinely ggplot2-specific -- hatched and
    # outlined NA fills, the footnote caption, the classification report, the
    # VSUP uncertainty scale and the dispute overlay -- so it is named instead
    # of quietly not happening.
    ignored <- c(
      if (!identical(na_style, "grey")) "na_style",
      if (footnote_given && !isFALSE(footnote) && !is.null(footnote)) "footnote",
      if (!is.null(midpoint)) "midpoint",
      if (!identical(small_states, "auto")) "small_states",
      if (isTRUE(classification_report)) "classification_report",
      if (!is.null(uncertainty)) "uncertainty",
      if (!identical(disputes, "ignore")) "disputes"
    )
    warn_engine_ignored(ignored, "tmap", 'engine = "ggplot2"')
    return(world_map_tmap(data, fill_name, style, n_bins, palette, title,
                          legend, na_label, borders, sf_mode,
                          projection, recenter, breaks = breaks))
  }

  # The polygon backend draws in the requested projection too: see
  # wdj_polygon_coord(). It used to draw through coord_quickmap() whatever
  # `projection` said, the default Equal Earth included.
  pc <- if (!sf_mode) wdj_polygon_coord(projection, recenter)
  # `n_bins` only means something to a style that bins. It was silently inert
  # under "continuous" (a colourbar has no classes) and "categorical" (the
  # classes are the values), which is the same complaint the 3.0.0 fix for
  # style = "binned" answered -- n_bins was ignored there too. Compared against
  # the default rather than missing(), matching warn_projection_ignored().
  #
  # Except under `uncertainty`, where the value-suppressing palette takes its
  # value classes from `n_bins` whatever `style` says: the notice fired there
  # too, telling the caller an argument the map was using had been ignored.
  unc_given <- !rlang::quo_is_null(rlang::enquo(uncertainty))
  if (!identical(as.numeric(n_bins), 5) && !unc_given) warn_n_bins_ignored(style)
  # The converse: `n_uncertainty` belongs to the value-suppressing palette
  # alone, and without `uncertainty` it was accepted and dropped in silence.
  # identical() rather than as.numeric(), which would warn on a string before
  # the notice could say anything.
  if (!unc_given && !identical(n_uncertainty, 3) &&
      !identical(n_uncertainty, 3L)) {
    wdj_warn(c(
      "{.arg n_uncertainty} applies only with {.arg uncertainty} and is ignored.",
      "i" = "It sets the uncertainty levels of a value-suppressing palette;
             pass {.arg uncertainty} to draw one."
    ), class = "countryatlas_n_uncertainty_ignored")
  }

  # A panel drawn as one static map overplots each country's years on top of
  # each other and whichever row happens to come last wins -- silently, and the
  # caption still counts each country once, so nothing looks wrong.
  # attach_geometry() joins a panel deliberately (facet_map() and
  # animate_world() are built on it, and its own comment says so), which is
  # exactly why the guard belongs here, where a single map is what was asked
  # for. Keyed on `year` rather than duplicate iso3c: the bundled sf basemap
  # legitimately carries one country twice, and the polygon backend carries
  # every country once per vertex.
  warn_map_panel(data)

  # An infinity has no colour on any scale: ggplot2 paints it in `na.value`
  # and cut() puts it in no class, so it is drawn as no data. It is counted
  # that way below; say so here, because a country holding a real-looking
  # value that comes out grey is otherwise baffling. It is nearly always a
  # division by zero upstream.
  warn_infinite_fill(data, fill_name)
  # Coverage is counted before anything is dropped, so `na_style = "omit"` still
  # reports honestly on what it removed.
  coverage <- na_coverage(data, fill_name)
  # Kept for the VSUP recount below, which has to run against the frame as it
  # arrived rather than whatever `na_style = "omit"` leaves behind.
  data_full <- data
  # has_value(), so "omit" and "hatched" treat an infinity as the no-data it is
  # drawn as, rather than leaving it grey among the hatched or omitted ones.
  missing_rows <- !has_value(data[[fill_name]])
  if (identical(na_style, "omit")) data <- data[!missing_rows, , drop = FALSE]

  # A value-suppressing uncertainty palette replaces the ordinary fill entirely:
  # colour becomes a function of value *and* uncertainty, so it cannot go
  # through the usual style/scale machinery.
  unc_q <- rlang::enquo(uncertainty)
  vsup <- NULL
  if (!rlang::quo_is_null(unc_q)) {
    unc_name <- quo_arg_name(unc_q, "uncertainty")
    check_cols(data, unc_name)
    check_numeric_col(data, unc_name)
    # A VSUP contracts a *value range*, so there has to be one. Falling through
    # to check_numeric_col() named the right column but gave nonsense advice --
    # "convert `continent` to numeric" -- for what is really a category error.
    if (!is.numeric(data[[fill_name]])) {
      wdj_abort(c(
        "{.arg uncertainty} needs a numeric {.arg fill}.",
        "x" = "{.field {fill_name}} is {.cls {class(data[[fill_name]])[1]}}.",
        "i" = "A value-suppressing palette works by narrowing the value range as
               uncertainty rises; a categorical fill has no range to narrow.",
        "*" = "Map the uncertainty separately, or use {.fn coverage_map}."
      ))
    }
    check_number(n_uncertainty, "n_uncertainty", lo = 2, hi = 6)
    n_uncertainty <- as.integer(n_uncertainty)
    # A VSUP needs both numbers, so a country with a value but no uncertainty
    # gets no colour -- and `coverage`, which counts missing *fill* values,
    # said it was shown anyway. On a frame whose uncertainty column is sparser
    # than its value column, `footnote = "auto"` therefore overstated coverage
    # by every country the uncertainty join had missed, which is precisely the
    # claim that footnote exists to keep honest.
    coverage <- na_coverage(
      data_full, fill_name,
      shown = has_value(data_full[[fill_name]]) & is.finite(data_full[[unc_name]]))
    lost <- setdiff(coverage$missing_iso3c,
                    na_coverage(data_full, fill_name)$missing_iso3c)
    if (length(lost)) {
      wdj_warn(c(
        "{length(lost)} countr{?y/ies} ha{?s/ve} {.field {fill_name}} but no
         {.field {unc_name}}, so the palette has no colour to give:",
        "*" = "{.val {utils::head(lost, 8)}}",
        "i" = "A value-suppressing palette encodes both numbers at once, so a
               country missing either one is drawn as no-data."
      ))
    }
    # `palette` reaches the value-suppressing palette now. It used to reach
    # neither vsup_fill() nor vsup_scale(), both of which assumed viridis, so
    # world_map(uncertainty = , palette = "magma") drew viridis without a word.
    vsup <- vsup_fill(data[[fill_name]], data[[unc_name]],
                      n_bins = as.integer(n_bins),
                      n_uncertainty = n_uncertainty,
                      option = palette %||% "viridis",
                      unit = unit_ids(data))
    data[[".wdj_vsup"]] <- factor(
      vsup$label,
      levels = sprintf("v%d / u%d",
                       rep(seq_len(as.integer(n_bins)), times = n_uncertainty),
                       rep(seq_len(n_uncertainty), each = as.integer(n_bins))))
  }

  # `style` cannot apply when a value-suppressing palette is drawn: the VSUP
  # mapping replaces the binned fill below, so the classification is computed
  # and discarded. It used to be discarded in silence, and the provenance then
  # reported that unused style as though the map had used it.
  if (!is.null(vsup) && (style_given || !is.null(breaks) || !is.null(midpoint)) &&
      !identical(style, "continuous")) {
    wdj_warn(c(
      "{.arg style} does not apply when {.arg uncertainty} is given and is
       ignored.",
      "i" = "A value-suppressing palette encodes the value and its uncertainty
             together, so it sets its own classes; {.arg n_bins} controls how
             many."
    ), class = "countryatlas_style_ignored")
  }
  # Small states: the countries attach_geometry() had no polygon for, drawn as
  # points on the same scale, so their values shape the classes too. A
  # value-suppressing palette is computed over the polygons alone, so it
  # draws none.
  ss <- small_state_points(data_full, fill_name,
                           if (is.null(vsup)) small_states else "none",
                           small_area_km2)
  coverage <- small_state_coverage(coverage, ss)
  binned <- apply_binned_fill(data, fill_name, style, n_bins, breaks = breaks,
                              midpoint = midpoint,
                              extra = if (!is.null(ss$points))
                                ss$points[[fill_name]][!ss$points$iso3c %in% data$iso3c])
  data <- binned$data
  fill_mapped <- if (is.null(vsup)) binned$fill else rlang::quo(.data[[".wdj_vsup"]])
  pts <- ss$points
  if (!is.null(pts) && !is.null(attr(binned, "breaks")) && style %in% CLASSED_STYLES) {
    pts[[".wdj_bin"]] <- bin_values(pts[[fill_name]], attr(binned, "breaks"),
                                    attr(binned, "right") %||% TRUE)
  }
  if (!is.null(pts) && is.character(pts[[fill_name]]) &&
      is.factor(data[[fill_name]])) {
    pts[[fill_name]] <- factor(pts[[fill_name]], levels = levels(data[[fill_name]]))
  }

  na_value <- switch(na_style, grey = "grey85", outline = "white", "grey85")
  # Cut at the horizon before coord_sf() projects anything: see
  # clip_to_hemisphere(). After the counting above, which it would not change
  # anyway (every row is kept), and before the hatch and dispute layers, which
  # draw from this frame too.
  if (sf_mode) data <- clip_for_projection(data, projection, recenter)
  if (sf_mode) {
    p <- ggplot2::ggplot(data) +
      ggplot2::geom_sf(ggplot2::aes(fill = !!fill_mapped),
                       color = if (borders) "grey30" else NA,
                       linewidth = 0.1) +
      wdj_coord_sf(projection, recenter)
  } else {
    # Recentring cuts the rings at the new antimeridian first; the built-in
    # Equal Earth (when sf cannot load) then projects the vertices, which the
    # hatch and dispute layers below draw from as well.
    data <- recenter_rings(data, recenter)
    data <- apply_polygon_transform(data, pc)
    p <- ggplot2::ggplot(
      data,
      ggplot2::aes(x = .data$long, y = .data$lat, group = .data$group,
                   fill = !!fill_mapped)
    ) +
      ggplot2::geom_polygon(
        color = if (borders) "grey30" else NA, linewidth = 0.1
      ) +
      pc$coord
  }

  p <- p + if (is.null(vsup)) {
    add_fill_scale(style, palette, n_bins, na_label,
                   legend %||% legend_title(data_full, fill_name),
                   na_value = na_value, binned = binned,
                   limits = fill_limits(data, pts, fill_name),
                   na_present = anyNA(data[[if (".wdj_bin" %in% names(data))
                     ".wdj_bin" else fill_name]]))
  } else {
    vsup_scale(vsup, as.integer(n_bins), n_uncertainty,
               legend %||% legend_title(data_full, fill_name),
               quo_arg_name(unc_q, "uncertainty"),
               option = palette %||% "viridis")
  }
  p <- p + theme_world_map()

  # suppressMessages() on both: each returns list(<layer>, <CoordSf>), and
  # ggplot_add.Coord announces "Coordinate system already present. Adding new
  # coordinate system, which will replace the existing one." whenever the
  # existing coord is non-default -- which it is, wdj_coord_sf() having been
  # added above. Replacing it is exactly what the re-assertion below handles, so
  # the note describes bookkeeping the caller cannot act on. A plain sf call is
  # silent (test-pre-cran-polish.R asserts that of every verb); these two
  # arguments were the gap.
  # The layer is *built* outside the suppression and only *added* inside it.
  # na_hatch_layer() announces a missing ggpattern -- "asking for hatching and
  # silently getting grey is the one thing worse than not offering hatching" --
  # and wrapping the whole expression swallowed that too.
  if (identical(na_style, "hatched")) {
    hatch <- na_hatch_layer(data, fill_name, sf_mode, borders)
    if (!is.null(hatch)) p <- suppressMessages(p + hatch)
  }
  if (identical(disputes, "mark")) {
    marks <- dispute_layer(data, sf_mode)
    if (!is.null(marks)) p <- suppressMessages(p + marks)
  }
  pt_layer <- small_state_layer(pts, fill_mapped, sf_mode, pc, projection,
                                recenter)
  if (!is.null(pt_layer)) p <- suppressMessages(p + pt_layer)
  # Re-assert the coordinate system after those two. Both return
  # list(<layer>, <CoordSf>) -- geom_sf() and ggpattern::geom_sf_pattern() each
  # carry a default coord_sf(crs = NULL) -- and ggplot2's ggplot_add.Coord
  # replaces the plot's coord unconditionally. Added after wdj_coord_sf() they
  # therefore threw the requested projection away along with its latitude clip,
  # so `mercator + hatched` and `robinson + hatched` drew byte-identical maps.
  # The coord is not a layer, so re-adding it here does not disturb draw order.
  if (identical(na_style, "hatched") || identical(disputes, "mark") ||
      !is.null(pt_layer)) {
    p <- suppressMessages(p + if (sf_mode) wdj_coord_sf(projection, recenter)
                          else pc$coord)
  }
  if (!is.null(title)) p <- p + ggplot2::labs(title = title)

  cap <- resolve_footnote(footnote, coverage)
  # "auto" says where the numbers came from as well as how many there are,
  # when the data carries a source_info() record for the fill, and how many
  # countries are drawn as points.
  auto <- identical(footnote, "auto")
  notes <- c(if (auto) small_state_note(ss), dispute_note(disputes, data),
             imputed_note(data))
  src_note <- if (auto) source_caption(fill_source_info(data_full, fill_name))
  cap <- paste(stats::na.omit(c(cap, notes, src_note)), collapse = " ")
  if (nzchar(cap)) p <- p + ggplot2::labs(caption = cap)

  # Provenance travels on the object, not in a print side effect, so it survives
  # being saved, faceted or handed to map_provenance() later.
  attr(p, "countryatlas_provenance") <- list(
    fill = fill_name,
    # "vsup" rather than `style` when a value-suppressing palette was drawn:
    # the classification `style` names is computed and then replaced, so
    # reporting it claimed the map used a classification it did not, and the
    # attached break table below described the same unused one.
    style = if (is.null(vsup)) style else "vsup",
    projection = if (sf_mode) projection else pc$label,
    recenter = recenter, midpoint = midpoint,
    backend = if (sf_mode) "sf" else "polygon", n_bins = n_bins,
    na_style = na_style, coverage = coverage,
    breaks = if (is.null(vsup)) attr(binned, "breaks") else NULL,
    disputes = disputes, dispute_policy = dispute_policy(),
    worldview = attr(data_full, "countryatlas_worldview") %||% NA_character_,
    uncertainty = if (is.null(vsup)) NA_character_ else quo_arg_name(unc_q, "uncertainty"),
    n_imputed = imputed_count(data),
    sources = fill_source_info(data_full, fill_name),
    footnote = if (auto) "auto" else if (is.character(footnote)) "custom" else "none",
    caption_notes = notes, caption = if (nzchar(cap)) cap,
    small_states = small_states,
    n_points = if (is.null(pts)) 0L else length(unique(pts$iso3c)),
    undrawable = ss$undrawable,
    values = dplyr::bind_rows(
      alt_values(data_full, fill_name),
      if (!is.null(pts)) alt_values(pts[!pts$iso3c %in% data_full$iso3c, , drop = FALSE],
                                    fill_name))
  )
  # Set after the provenance it reads, and before the attributes are copied
  # anywhere: ggplot2 evaluates it on the final plot.
  prov_tmp <- attr(p, "countryatlas_provenance")
  p <- with_alt_text(p)
  attr(p, "countryatlas_provenance") <- prov_tmp
  if (isTRUE(classification_report)) {
    attr(p, "countryatlas_classification") <-
      classification_table(data, fill_name, style, n_bins, binned)
  }
  p
}

# The panel guard of a verb that draws one map: see world_map().
warn_map_panel <- function(data) {
  if (!"year" %in% names(data)) return(invisible(NULL))
  yrs <- unique(stats::na.omit(sf_drop(data)$year))
  if (length(yrs) > 1L) {
    wdj_warn(c(
      "{.arg data} spans {length(yrs)} years and a single map can show one.",
      "x" = "Each country is drawn once per year, so the last row wins.",
      "i" = "Filter to one year, or use {.fn facet_map} or
             {.fn animate_world}, which are built for a panel."
    ), class = "countryatlas_panel")
  }
  invisible(NULL)
}

# The column that identifies one drawable unit, most specific first. These
# frames are de-duplicated before counting or computing breaks, because the
# polygon backend repeats a country's value down every vertex. Keying on iso3c
# was wrong for a *subnational* frame, which carries iso3c as well as a region
# code: every NUTS region of a country collapsed to one row, so a 280-region map
# reported "27 of 27", four blank regions inside a country whose first region
# had data were reported as zero missing, and -- worst -- the quantile breaks
# were computed from 27 values instead of 280.
wdj_unit_key <- function(nms) {
  intersect(c("nuts_id", "iso_3166_2", "iso3c", "group"), nms)
}

# The drawable-unit id of every row (see wdj_unit_key()), or NULL for a frame
# with no key column.
unit_ids <- function(data) {
  key <- wdj_unit_key(names(data))
  if (!length(key)) return(NULL)
  as.character(data[[key[1]]])
}

# percent_rank() over one value per drawable unit, handed back row-aligned.
# The polygon backend repeats a country's value down every one of its
# vertices, so a rank over the raw rows weighted each country by how complex
# its outline is -- the defect apply_binned_fill() de-duplicates away for the
# quantile breaks. value_by_alpha_map()'s default opacity and the VSUP ramp
# both ranked the raw rows: Chile, at the 69th percentile of countries by
# population, drew at the 30th because the countries below it have long
# coastlines, and 101 of 189 countries landed in the wrong VSUP cell.
# De-duplicating (unit, value) pairs rather than units keeps every year of a
# panel in play, as apply_binned_fill() does. Ties share a rank either way, so
# match() can take the first copy of a value.
unit_percent_rank <- function(x, unit = NULL) {
  if (is.null(unit)) return(dplyr::percent_rank(x))
  xu <- x[!duplicated(data.frame(unit = unit, x = x))]
  dplyr::percent_rank(xu)[match(x, xu)]
}

# Countries present vs countries with a value, counted once per country rather
# than once per polygon vertex (the polygon backend repeats a country's value
# for every boundary point, so a naive count would report tens of thousands).
na_coverage <- function(data, fill_name, shown = NULL) {
  df <- tibble::as_tibble(sf_drop(data))
  # `shown` joins the frame before the de-duplication so it survives it: a
  # value-suppressing palette needs the uncertainty column too, and "did this
  # country get a colour" is then no longer the same question as "is its fill
  # value present".
  if (!is.null(shown)) df[[".wdj_shown"]] <- shown
  # A geometry row carrying no ISO code is not a country -- it is a fragment the
  # basemap has and the codelist does not. Counting it put a phantom in the
  # denominator and in n_missing, while missing_iso3c (which sorts, and so drops
  # NA) listed one fewer than n_missing claimed: the caption said "17 missing"
  # where provenance could name only 16.
  if ("iso3c" %in% names(df)) df <- df[!is.na(df$iso3c), , drop = FALSE]
  key <- wdj_unit_key(names(df))
  # has_value(), not !is.na(): an infinite value is drawn in the no-data grey
  # by every scale here, so counting it as shown made the caption read "189 of
  # 240 countries shown" over a map showing 187.
  ok <- if (is.null(shown)) has_value(df[[fill_name]]) else df[[".wdj_shown"]]
  if (length(key)) {
    # Counted once per country, as imputed_count() does, and by "has a value in
    # any of its rows" rather than distinct()'s first row. On the map-ready
    # cross-section this is documented for, the two are identical. On a panel
    # the first row is whichever year happens to come first, so the same panel
    # reordered reported 2 of 4 countries missing or 0 of 4 -- and
    # facet_map(facet = "year") hands world_map() the whole panel, so that
    # arbitrary number was the caption on a plot showing every year.
    unit <- as.character(df[[key[1]]])
    agg <- vapply(split(ok, unit), function(z) any(z, na.rm = TRUE), logical(1))
    iso <- if ("iso3c" %in% names(df)) {
      vapply(split(as.character(df$iso3c), unit), function(z) z[1L], character(1))
    } else NULL
    # unname(): split() names its result by the grouping value, and the caller
    # gets this vector straight into a caption and into expect_equal(). It was
    # unnamed before the per-unit aggregation and has to stay that way.
    return(list(n_total = length(agg), n_shown = sum(agg), n_missing = sum(!agg),
                missing_iso3c = if (is.null(iso)) character(0) else
                  unname(sort(iso[!agg]))))
  }
  list(n_total = length(ok), n_shown = sum(ok), n_missing = sum(!ok),
       missing_iso3c = if ("iso3c" %in% names(df)) sort(df$iso3c[!ok]) else character(0))
}

# Name the countries whose fill is infinite: they are drawn as no data and
# counted as missing, and the reason is otherwise invisible. Counted once per
# country, since the polygon backend repeats the value down every vertex.
warn_infinite_fill <- function(data, fill_name) {
  v <- data[[fill_name]]
  if (!is.numeric(v)) return(invisible(NULL))
  inf <- is.infinite(v)
  if (!any(inf)) return(invisible(NULL))
  df <- sf_drop(data)
  who <- if ("iso3c" %in% names(df)) {
    sort(unique(unit_label(df[inf, , drop = FALSE])))
  } else character(0)
  # Two whole templates rather than one with the noun spliced in: cli does not
  # re-interpolate a substituted value, so a spliced "{?y/ies}" would print as
  # literal braces.
  if (length(who)) {
    n <- length(who)
    head_msg <- "{n} countr{?y/ies} ha{?s/ve} an infinite {.field {fill_name}},
                 drawn as no data:"
  } else {
    n <- sum(inf)
    head_msg <- "{n} row{?s} ha{?s/ve} an infinite {.field {fill_name}}, drawn
                 as no data."
  }
  wdj_warn(c(
    head_msg,
    if (length(who)) c("*" = "{.val {utils::head(who, 8)}}"),
    "i" = "No colour scale can place an infinity; it is usually a division
           by zero upstream. It is counted as missing in the caption and in
           {.fn map_provenance}."
  ), class = "countryatlas_infinite_fill")
  invisible(NULL)
}

# Drop sf geometry for counting without requiring sf to be attached.
sf_drop <- function(x) if (is_sf(x)) sf::st_drop_geometry(x) else x

resolve_footnote <- function(footnote, coverage, call = rlang::caller_env()) {
  if (is.null(footnote) || isFALSE(footnote)) return(NULL)
  if (isTRUE(footnote)) footnote <- "auto"
  if (!identical(footnote, "auto")) {
    check_string(footnote, "footnote", call = call)
    return(footnote)
  }
  n_total <- coverage$n_total
  # This lands on a published map, so it has to read as English at every size.
  # sprintf() alone produced "All 1 countries shown." for a single-country
  # frame and "All 0 countries shown." for an empty one.
  if (length(n_total) != 1L || is.na(n_total)) return(NULL)
  if (n_total < 1L) return("No countries to show.")
  noun <- countries_noun(n_total)
  if (!coverage$n_missing) {
    return(sprintf("All %d %s shown.", n_total, noun))
  }
  sprintf("%d of %d %s shown; %d missing.",
          coverage$n_shown, n_total, noun, coverage$n_missing)
}

# Diagonal hatching over the no-data countries. ggpattern is optional, so say
# plainly when the request cannot be honoured rather than silently drawing grey.
na_hatch_layer <- function(data, fill_name, sf_mode, borders) {
  if (!has_pkg("ggpattern")) {
    wdj_inform(
      c("i" = "Package {.pkg ggpattern} not installed; drawing missing data in grey
              instead of hatched."),
      .frequency = "once", .frequency_id = "world_map-no-ggpattern"
    )
    return(NULL)
  }
  nd <- data[!has_value(data[[fill_name]]), , drop = FALSE]
  if (!nrow(nd)) return(NULL)
  # The stripes are clipped by gridpattern with sf, and only when the map is
  # drawn. gridpattern imports sf, so sf is always installed here, but
  # installed is not loadable: where sf's system libraries (udunits, GDAL,
  # GEOS, PROJ) are not on the library path, world_map() returned a plot that
  # failed only on print, deep in grid, with "unable to load shared object
  # units.so". That is how R CMD build died weaving the honest-maps vignette.
  # Ask now, while falling back is still possible.
  if (!has_pkg("sf")) {
    wdj_inform(
      c("i" = "Package {.pkg sf}, which {.pkg ggpattern} draws its stripes with,
              cannot be loaded; drawing missing data in grey instead of
              hatched."),
      .frequency = "once", .frequency_id = "world_map-no-sf-hatch"
    )
    return(NULL)
  }
  common <- list(
    data = nd, fill = "grey93", pattern = "stripe",
    pattern_fill = "grey55", pattern_colour = NA, pattern_angle = 45,
    pattern_density = 0.08, pattern_spacing = 0.012, pattern_size = 0.2,
    colour = if (borders) "grey30" else NA, linewidth = 0.1,
    inherit.aes = FALSE
  )
  if (sf_mode) {
    do.call(ggpattern::geom_sf_pattern, common)
  } else {
    # One shape, its rings as subgroups, not one shape per polygon.
    # geom_polygon_pattern() clips a fresh set of stripes to every group, and
    # on the polygon basemap the no-data countries are many groups (169 for
    # co2_per_capita in world_snapshot, most of them islands, plus a
    # 4658-vertex Antarctica), so one hatched world map took 29s to print and
    # the honest-maps vignette spent 56s on it. Clipped once, it takes under
    # a second. gridpattern buffers the boundary by zero first, which merges
    # overlapping rings, so an enclave missing alongside its host is still
    # hatched.
    do.call(ggpattern::geom_polygon_pattern, c(
      list(mapping = ggplot2::aes(x = .data$long, y = .data$lat, group = 1L,
                                  subgroup = .data$group)), common
    ))
  }
}

# Pick the fill scale from the *column*, for the verbs that take a free-form
# `fill` rather than a `style`. cartogram_map() and tile_map() both hard-wired
# scale_fill_viridis_c(), so a categorical fill -- which their `fill` argument
# documents no restriction on, and which check_numeric_col() only rejects for
# `weight` -- was accepted at the call and then died at *print* time with
# ggplot2's bare "Discrete value supplied to a continuous scale". world_map()
# has had check_categorical_fill() guarding exactly this since 2.0.0; these two
# verbs never got the equivalent.
auto_fill_scale <- function(vals, name, na_value = "grey85") {
  if (is.numeric(vals)) {
    ggplot2::scale_fill_viridis_c(name = name, na.value = na_value,
                                  labels = scales_format())
  } else {
    ggplot2::discrete_scale(
      aesthetics = "fill", name = name, na.value = na_value,
      palette = function(n) grDevices::hcl.colors(n, CATEGORICAL_PALETTE))
  }
}

# `style = "categorical"` maps onto a discrete scale, which ggplot2 refuses a
# numeric column outright -- but only at build time ("Continuous value supplied
# to a discrete scale"), long after the call and without naming the column or
# the style that caused it.
check_categorical_fill <- function(style, vals, fill_name,
                                   call = rlang::caller_env()) {
  # The numeric styles need a numeric column, and said so only obliquely and
  # late: "continuous" and "binned" reached ggplot2 and failed at *print* time
  # ("Discrete value supplied to a continuous scale", "Binned scales only
  # support continuous data"), neither naming the column. Worse, "quantile" and
  # "jenks" did not fail at all -- compute_breaks() returns early on a
  # non-numeric column, so the fill fell through to the discrete scale and drew
  # a perfectly plausible map whose legend claimed quantile bins it had never
  # computed.
  if (style %in% c("continuous", BAR_STYLES, CLASSED_STYLES) &&
      !is.numeric(vals)) {
    wdj_abort(c(
      '{.code style = "{style}"} needs a numeric {.arg fill} column.',
      "x" = "{.val {fill_name}} is {.cls {class(vals)}}.",
      "i" = 'Use {.code style = "categorical"} for a discrete column, or convert it with {.code as.numeric()}.'
    ), call = call)
  }
  if (!identical(style, "categorical") || !is.numeric(vals)) return(invisible(TRUE))
  wdj_abort(c(
    '{.code style = "categorical"} needs a discrete {.arg fill} column.',
    "x" = "{.val {fill_name}} is {.cls {class(vals)}}.",
    "i" = 'Use {.code style = "quantile"}, {.code "jenks"} or {.code "binned"} for a numeric column, or convert it to a factor first.'
  ), call = call)
}

# Label the discrete scales' NA key with `na_label` instead of a bare "NA".
# (Continuous / binned colourbars have no NA key to name, so they are left
# to the default formatter.)
# Only the first element can label the single NA key; a NULL / empty / NA
# label means "leave the default formatter alone". (Guarding with anyNA()
# rather than is.na() so a length > 1 na_label can't error the condition.)
# Shared with the tmap engine, which used to ignore `na_label` entirely, so
# the two backends agree on what the argument means by construction.
na_label_value <- function(na_label) {
  if (is.null(na_label) || !length(na_label) || anyNA(na_label)) return(NULL)
  as.character(na_label)[[1]]
}

discrete_na_labels <- function(na_label) {
  na_label <- na_label_value(na_label)
  if (is.null(na_label)) {
    return(ggplot2::waiver())
  }
  function(x) {
    x <- as.character(x)
    x[is.na(x)] <- as.character(na_label)
    x
  }
}

# Use scales::label_number if available, else identity labels. SI-style
# cut_short_scale() turns 4e+06 into "4M" so binned legends stay readable.
scales_format <- function() {
  if (has_pkg("scales")) {
    scales::label_number(scale_cut = scales::cut_short_scale())
  } else {
    ggplot2::waiver()
  }
}

#' Two-variable bivariate choropleth
#'
#' A 2-D bivariate choropleth with a built-in 2-D legend (via the optional
#' `biscale` package), e.g. GDP per capita x life expectancy in one map.
#'
#' @param data An `sf` map-ready frame (use `geometry = "sf"`).
#' @param fill_x,fill_y The two value columns (unquoted).
#' @param palette A `biscale` palette name (default `"GrPink"`).
#' @param dim Bivariate dimension: classes per variable, 2, 3 (default) or 4.
#'   A 4 x 4 map needs a palette that has one, such as `"GrPink2"`.
#' @param projection Projection; see [world_map()] for the ones available.
#'
#' @param footnote The caption, as in [world_map()]: `"auto"` (default)
#'   states the coverage and source, a string is used as given, `FALSE` adds
#'   nothing.
#' @section Backend:
#' The `sf` backend only, since `biscale` classes an `sf` frame; drawn in
#' `projection` (Equal Earth by default).
#'
#' @return A `ggplot` object (the map; combine with `biscale::bi_legend()` for a
#'   standalone legend).
#' @export
#' @examples
#' \donttest{
#' if (requireNamespace("sf", quietly = TRUE) &&
#'     requireNamespace("rnaturalearth", quietly = TRUE) &&
#'     requireNamespace("biscale", quietly = TRUE)) {
#'   attach_geometry(countryatlas::world_snapshot$countries, geometry = "sf") |>
#'     bivariate_map(gdp_per_capita, life_expectancy)
#' }
#' }
bivariate_map <- function(data, fill_x, fill_y, palette = "GrPink", dim = 3,
                          projection = "equal_earth", footnote = "auto") {
  # `dim` was the one argument here nothing checked: "a" reached the class
  # count check below as a string comparison and reported "too few for a
  # classes", NA died on base R's "missing value where TRUE/FALSE needed",
  # c(2, 3) on "the condition has length > 1", and 2.5 on biscale's own
  # wording. biscale's built-in palettes go up to 4 x 4.
  check_number(dim, "dim", lo = 2, hi = 4)
  if (dim != round(dim)) {
    wdj_abort(c("{.arg dim} must be a whole number of classes: 2, 3 or 4.",
                "x" = "Got {.val {dim}}."))
  }
  dim <- as.integer(dim)
  need_pkg("biscale", "for bivariate_map()")
  need_pkg("sf", "for bivariate_map()")
  if (!is_sf(data)) wdj_abort("{.fn bivariate_map} needs an sf frame ({.code geometry = \"sf\"}).")
  x_name <- quo_arg_name(rlang::enquo(fill_x), "fill_x")
  y_name <- quo_arg_name(rlang::enquo(fill_y), "fill_y")

  for (nm in c(x_name, y_name)) {
    if (!nm %in% names(data)) {
      wdj_abort("Column {.val {nm}} not found in {.arg data}.")
    }
    check_numeric_col(data, nm)
  }
  # biscale indexes its break vector as sVar[1:(length(sVar) - 1)]. With nothing
  # to classify that is 1:-1, and the call dies on "only 0's may be mixed with
  # negative subscripts" -- which says nothing about the data. Note this bites
  # a *joined* frame too: attach_geometry() keeps every geometry row, so an
  # empty input arrives here as full-length columns of NA.
  # An infinity cannot be classified (biscale's quantile breaks would take
  # it as a bound), so, as in world_map(), it is named, then treated as the
  # missing value it is drawn as.
  for (nm in c(x_name, y_name)) {
    warn_infinite_fill(data, nm)
    data[[nm]][is.infinite(data[[nm]])] <- NA
  }
  if (!any(!is.na(data[[x_name]]) & !is.na(data[[y_name]]))) {
    wdj_abort(c(
      "No country has both {.val {x_name}} and {.val {y_name}}.",
      "i" = "A bivariate map needs values for both variables in the same row."
    ))
  }
  # classInt needs at least two distinct values per axis to cut `dim` classes
  # from. A constant column reached it as classIntervals(...)'s bare "single
  # unique value" -- a simpleError from a third-party package naming neither
  # the column nor the function, and offering nothing to do about it.
  for (nm in c(x_name, y_name)) {
    nd <- length(unique(stats::na.omit(data[[nm]])))
    # Fewer distinct values than classes and classInt cannot cut them: a
    # constant column arrived as its bare "single unique value", and two values
    # against dim = 3 as "n greater than number of different finite values",
    # both simpleErrors/warnings from a third-party package naming neither the
    # column nor the function. Exactly `dim` distinct values is legal -- each
    # becomes its own class, and classInt says so, which is worth hearing.
    if (nd < dim) {
      wdj_abort(c(
        "{.field {nm}} has {nd} distinct value{?s}, too few for {dim} classes.",
        "i" = "A bivariate map cuts each variable into {dim} classes, so each
               axis needs at least that many different values. Lower
               {.arg dim}, or use {.fn world_map}."
      ), class = "countryatlas_not_classifiable")
    }
  }
  # bi_class() reads its x/y arguments with as.character(substitute(...)), not
  # tidy eval: a `!!sym()` injection deparses into a multi-element vector and
  # blows up inside biscale ("the condition has length > 1"), and a variable
  # holding the name deparses to the variable's own name. Build the call so
  # the column names are inlined as literals.
  bidata <- withCallingHandlers(
    do.call(
      biscale::bi_class,
      list(.data = data, x = x_name, y = y_name, style = "quantile", dim = dim)
    ),
    # Real-world indicators always have gaps, so biscale's "var has missing
    # values, omitted in finding classes" fires on essentially every call. The
    # classes are still valid; any other warning passes through untouched.
    warning = function(w) {
      if (grepl("missing values", conditionMessage(w), fixed = TRUE)) {
        invokeRestart("muffleWarning")
      }
    }
  )
  bidata <- clip_for_projection(bidata, projection)
  p <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = bidata, ggplot2::aes(fill = .data$bi_class),
                     color = "grey30", linewidth = 0.1, show.legend = FALSE) +
    biscale::bi_scale_fill(pal = palette, dim = dim) +
    wdj_coord_sf(projection) +
    biscale::bi_theme()
  # A bivariate class needs both variables, so a country holding only one is
  # drawn as no-data. Coverage counted on x alone called it shown -- the same
  # overstatement the VSUP path made, in a different verb.
  cov <- na_coverage(data, x_name,
                     shown = has_value(data[[x_name]]) & has_value(data[[y_name]]))
  lost <- setdiff(cov$missing_iso3c, na_coverage(data, x_name)$missing_iso3c)
  if (length(lost)) {
    wdj_warn(c(
      "{length(lost)} countr{?y/ies} ha{?s/ve} {.field {x_name}} but no
       {.field {y_name}}, so {.fn bivariate_map} has no class to give:",
      "*" = "{.val {utils::head(lost, 8)}}",
      "i" = "A bivariate map classifies the two together; a country missing
             either one is drawn as no-data."
    ))
  }
  wdj_provenance(p, data, x_name, "sf", projection,
                 # biscale also takes a custom palette as a named colour
                 # vector, which paste0() would have spread into one style
                 # string per colour.
                 style = paste0("bivariate ", dim, "x", dim, " (",
                                if (is.character(palette) && length(palette) == 1L)
                                  palette else "custom palette", ")"),
                 extra = list(coverage = cov),
                 footnote = footnote)
}
