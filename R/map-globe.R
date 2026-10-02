# Maps: globes -----------------------------------------------------------------

#' Orthographic globe choropleth
#'
#' The world as a globe (orthographic projection) centred on `lon`/`lat` -- the
#' honest answer to "the whole world on a rectangle exaggerates the poles". Takes
#' the same `fill` / `style` options as [world_map()]. The default `"sf"` backend
#' gives the cleanest limb; the `"polygon"` backend draws the globe with
#' [ggplot2::coord_map()] and needs only `mapproj` (no `sf`).
#'
#' @param data A map-ready frame: an `sf` frame for `backend = "sf"`, or a
#'   country-level frame with `iso3c` (or a polygon frame) for
#'   `backend = "polygon"`.
#' @param fill The fill column (unquoted).
#' @param lon,lat The longitude / latitude the globe is centred on (the face
#'   pointing at the viewer).
#' @param backend `"sf"` (default, via [ggplot2::coord_sf()]) or `"polygon"`
#'   (via [ggplot2::coord_map()], no `sf` required).
#' @param style,palette,n_bins,breaks,midpoint,borders,title,legend,na_label
#'   As in [world_map()].
#' @param footnote,small_states,small_area_km2 As in [world_map()].
#' @param interactive If `TRUE`, return a MapLibre WebGL globe you can spin and
#'   zoom instead of a static image. Needs `mapgl` and an `sf` frame; `lon` and
#'   `lat` become the initial camera position and the drawing arguments above do
#'   not apply.
#'
#' @return A `ggplot` object.
#' @export
#' @examples
#' \donttest{
#' # No sf required -- the polygon backend needs only mapproj:
#' if (requireNamespace("mapproj", quietly = TRUE)) {
#'   globe_map(countryatlas::world_snapshot$countries, continent,
#'             backend = "polygon", style = "categorical")
#' }
#' }
#' \dontrun{
#' # The sf backend gives the cleanest limb (needs a World Bank fetch):
#' world_data(2020, geometry = "sf") |>
#'   globe_map(gdp_per_capita, lon = 10, lat = 30)
#' }
globe_map <- function(data, fill, lon = 0, lat = 20,
                      backend = c("sf", "polygon"),
                      style = c("quantile", "continuous", "binned", "equal",
                                "jenks", "fisher", "headtails", "sd", "fixed",
                                "categorical"),
                      palette = NULL, n_bins = 5, breaks = NULL,
                      midpoint = NULL, borders = TRUE,
                      title = NULL, legend = NULL, na_label = "No data",
                      footnote = "auto", small_states = c("auto", "none", "dots"),
                      small_area_km2 = 1000, interactive = FALSE) {
  check_bool(borders, "borders")
  check_bool(interactive, "interactive")
  style_given <- !missing(style)
  if (isTRUE(interactive)) {
    # MapLibre renders a real WebGL globe you can spin with the mouse, which is
    # the thing the static orthographic projection and spin_globe()'s GIF are
    # both approximating. Everything else about this function is about drawing
    # one fixed viewpoint, so hand off rather than reimplement.
    #
    # Validated *here*, because arg_match() and check_label_args() sat below
    # this branch: an interactive globe accepted `style = "nonsense"` and a
    # length-3 `title` without a murmur.
    check_label_args(palette, title, legend, na_label)
    backend <- rlang::arg_match(backend)
    style <- rlang::arg_match(style)
    check_number(lon, "lon", lo = -360, hi = 360)
    check_number(lat, "lat", lo = -90, hi = 90)
    # And the ggplot2 styling arguments cannot travel to MapLibre, which
    # builds its own scale and legend. They were accepted and dropped.
    ignored <- c(
      if (!identical(backend, "sf")) "backend",
      if (style_given) "style",
      if (!is.null(breaks)) "breaks",
      if (!is.null(midpoint)) "midpoint",
      if (!is.null(palette)) "palette",
      if (!identical(n_bins, 5) && !identical(n_bins, 5L)) "n_bins",
      if (!isTRUE(borders)) "borders",
      if (!is.null(title)) "title",
      if (!is.null(legend)) "legend",
      if (!identical(na_label, "No data")) "na_label"
    )
    warn_engine_ignored(ignored, "mapgl", "interactive = FALSE")
    fill_q0 <- rlang::enquo(fill)
    if (!is_sf(data)) {
      wdj_abort(c(
        "{.code interactive = TRUE} needs an sf frame.",
        "i" = 'Build one with {.code world_data(..., geometry = "sf")} or
               {.fn attach_geometry}.'
      ))
    }
    m <- interactive_map(data, !!fill_q0, engine = "mapgl",
                         center = c(lon, lat), zoom = 1)
    return(mapgl::add_globe_control(m))
  }
  check_label_args(palette, title, legend, na_label)
  backend <- rlang::arg_match(backend)
  style <- rlang::arg_match(style)
  small_states <- rlang::arg_match(small_states)
  check_number(small_area_km2, "small_area_km2", lo = 0)
  fill_q <- rlang::enquo(fill)
  fill_name <- quo_arg_name(fill_q, "fill")
  # The sf backend validates these via wdj_crs(), but the polygon backend goes
  # to coord_map() instead, which took a nonsense orientation without comment.
  check_number(lon, "lon", lo = -360, hi = 360)
  check_number(lat, "lat", lo = -90, hi = 90)
  # Same notice world_map() gives: n_bins means nothing to a colourbar or to
  # categories. This verb has its own copy of the argument.
  check_number(n_bins, "n_bins", lo = 2, hi = .Machine$integer.max)
  view <- sprintf("orthographic (lon %s, lat %s)", fmt_num(lon), fmt_num(lat))

  if (backend == "polygon") {
    need_pkg("mapproj", "for globe_map(backend = \"polygon\")")
    # Bring a country-level table onto polygon geometry if it isn't already.
    if (!all(c("long", "lat", "group") %in% names(data))) {
      if (!"iso3c" %in% names(data)) {
        wdj_abort("{.arg data} needs an {.field iso3c} column (or polygon geometry).")
      }
      # No drop_map_geometry() here: this branch is reached only when the frame
      # lacks long/lat/group, so there is nothing to drop.
      data <- attach_geometry(
        distinct_countries(tibble::as_tibble(data)),
        geometry = "polygon"
      )
    }
    check_cols(data, fill_name)
    style <- resolve_style(style, style_given, breaks, midpoint, n_bins,
                           data[[fill_name]])
    if (!identical(as.numeric(n_bins), 5)) warn_n_bins_ignored(style)
    check_categorical_fill(style, data[[fill_name]], fill_name)
    # An infinity draws as no data here too; see world_map().
    warn_infinite_fill(data, fill_name)
    pf <- prepare_fill(data, fill_name, style, n_bins, breaks, midpoint,
                       small_states, small_area_km2)
    data <- pf$data
    fill_mapped <- pf$fill
    p <- ggplot2::ggplot(
      data, ggplot2::aes(.data$long, .data$lat, group = .data$group,
                         fill = !!fill_mapped)
    ) +
      ggplot2::geom_polygon(color = if (borders) "grey25" else NA, linewidth = 0.1) +
      small_state_layer(pf$points, fill_mapped, FALSE, NULL, "orthographic",
                        lon, lat) +
      ggplot2::coord_map("orthographic", orientation = c(lat, lon, 0)) +
      add_fill_scale(style, palette, n_bins, na_label,
                   legend %||% legend_title(data, fill_name),
                     binned = pf$binned, limits = pf$limits,
                     na_present = pf$na_present) +
      theme_world_map()
    if (!is.null(title)) p <- p + ggplot2::labs(title = title)
    return(wdj_provenance(p, data, fill_name, "polygon", view, style = style,
                          extra = list(n_bins = n_bins,
                                       breaks = attr(pf$binned, "breaks"),
                                       midpoint = midpoint,
                                       coverage = pf$coverage),
                          footnote = footnote,
                          notes = small_state_note(pf$ss)))
  }

  # sf backend.
  need_pkg("sf", "for globe_map()")
  if (!is_sf(data)) {
    wdj_abort("{.fn globe_map} needs an sf frame ({.code geometry = \"sf\"}) for {.code backend = \"sf\"}.")
  }
  check_cols(data, fill_name)
  style <- resolve_style(style, style_given, breaks, midpoint, n_bins,
                         data[[fill_name]])
  if (!identical(as.numeric(n_bins), 5)) warn_n_bins_ignored(style)
  check_categorical_fill(style, data[[fill_name]], fill_name)
  warn_infinite_fill(data, fill_name)
  pf <- prepare_fill(data, fill_name, style, n_bins, breaks, midpoint,
                     small_states, small_area_km2)
  data <- pf$data
  fill_mapped <- pf$fill

  # Drawn from the visible hemisphere only -- see clip_to_hemisphere() for
  # the 63 of 216 viewpoints that built and then could not be drawn. The
  # breaks above and the provenance below still see every country, so the
  # colours mean the same thing from every side of a spinning globe.
  p <- ggplot2::ggplot(clip_to_hemisphere(data, lon, lat)) +
    ggplot2::geom_sf(ggplot2::aes(fill = !!fill_mapped),
                     color = if (borders) "grey30" else NA, linewidth = 0.1) +
    small_state_layer(pf$points, fill_mapped, TRUE, NULL, "orthographic",
                      lon, lat) +
    wdj_coord_sf("orthographic", recenter = lon, lat0 = lat) +
    add_fill_scale(style, palette, n_bins, na_label,
                   legend %||% legend_title(data, fill_name),
                   binned = pf$binned, limits = pf$limits,
                   na_present = pf$na_present) +
    theme_world_map()
  if (!is.null(title)) p <- p + ggplot2::labs(title = title)
  wdj_provenance(p, data, fill_name, backend, view, style = style,
                 extra = list(n_bins = n_bins, breaks = attr(pf$binned, "breaks"),
                              midpoint = midpoint, coverage = pf$coverage),
                 footnote = footnote, notes = small_state_note(pf$ss))
}

#' Spin the globe
#'
#' An animated GIF of the world rotating on its axis: a sequence of orthographic
#' [globe_map()] frames at evenly spaced central longitudes, assembled into a
#' looping animation with the optional `gifski` (preferred) or `magick` package.
#' Embeds directly in R Markdown / Quarto / a README.
#'
#' @param data A map-ready frame (see [globe_map()]): a country-level frame with
#'   `iso3c` for the `"polygon"` backend, or an `sf` frame for `"sf"`.
#' @param fill The fill column (unquoted).
#' @param lat The latitude the globe is tilted toward (the viewer's eye line).
#' @param n_frames Number of frames in one full 360 degrees rotation.
#' @param fps Frames per second of the output animation.
#' @param backend `"polygon"` (default; needs `mapproj`, no `sf`) or
#'   `"sf"`.
#' @param width,height Pixel dimensions of the animation.
#' @param file Optional output path (`.gif`); a temporary file is used if `NULL`.
#' @param ... Passed to [globe_map()] (e.g. `fill` `style`, `palette`).
#'
#' @return The path to the written GIF, invisibly.
#' @export
#' @examples
#' # Six frames rather than the default 60, so this stays quick enough to be
#' # checked: \dontrun{} meant the example was never executed by anything, and
#' # an example nothing runs is an example free to rot.
#' \donttest{
#' if (requireNamespace("mapproj", quietly = TRUE) &&
#'     (requireNamespace("gifski", quietly = TRUE) ||
#'      requireNamespace("magick", quietly = TRUE))) {
#'   # No sf required on the polygon backend.
#'   gif <- spin_globe(world_snapshot$countries, continent,
#'                     backend = "polygon", style = "categorical",
#'                     n_frames = 6, width = 200, height = 200)
#'   file.exists(gif)   # written to a temporary file
#' }
#' }
spin_globe <- function(data, fill, lat = 20, n_frames = 60, fps = 15,
                       backend = c("polygon", "sf"), width = 480, height = 480,
                       file = NULL, ...) {
  backend <- rlang::arg_match(backend)
  fill_q <- rlang::enquo(fill)
  # Validate the arguments before gating on the animation packages: a bad
  # argument is the caller's bug and the message should not depend on which
  # optional packages happen to be installed. (globe_map() orders these the
  # same way.)
  check_number(n_frames, "n_frames", lo = 2, hi = .Machine$integer.max)
  check_number(fps, "fps", lo = 1)
  # `file` was the one this block missed, so a non-string path leaked base R's
  # "invalid 'path' argument" -- or, for a length-2 vector, "the condition has
  # length > 1" -- from deep inside the writer.
  if (!is.null(file)) check_string(file, "file")
  check_number(width, "width", lo = 1)
  check_number(height, "height", lo = 1)
  check_number(lat, "lat", lo = -90, hi = 90)
  # The scalars were moved ahead of the gate but the fill column was not, so a
  # mistyped column still reported a missing gifski.
  check_cols(data, quo_arg_name(fill_q, "fill"))
  if (!has_pkg("gifski") && !has_pkg("magick")) {
    need_pkg("gifski", "to assemble the animation (or install 'magick')")
  }
  n_frames <- as.integer(n_frames)

  # One full turn: drop the duplicated 360 == 0 frame so the loop is seamless.
  lons <- utils::head(seq(0, 360, length.out = n_frames + 1L), -1L)
  tmpdir <- tempfile("spin_globe_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)
  frames <- file.path(tmpdir, sprintf("frame_%04d.png", seq_along(lons)))

  for (i in seq_along(lons)) {
    p <- globe_map(data, !!fill_q, lon = lons[i], lat = lat, backend = backend, ...)
    suppressWarnings(ggplot2::ggsave(
      frames[i], p, width = width / 72, height = height / 72, dpi = 72,
      bg = "white"
    ))
  }

  out <- file %||% tempfile(fileext = ".gif")
  if (has_pkg("gifski")) {
    gifski::gifski(frames, gif_file = out, width = width, height = height,
                   delay = 1 / fps, loop = TRUE, progress = FALSE)
  } else {
    anim <- magick::image_animate(magick::image_read(frames), fps = fps)
    magick::image_write(anim, out)
  }
  invisible(out)
}
