# Labels ---------------------------------------------------------------------

#' Centroid-anchored country labels
#'
#' A `ggplot2` layer that places labels (names, ISO codes or flag emoji) at
#' country centroids, with optional `ggrepel` collision avoidance. Designed for
#' the polygon backend produced by [world_data()] / [join_world()]: it reads the
#' `long`, `lat` and `group` columns, so it errors on an `sf` frame and points at
#' [ggplot2::geom_sf_text()] instead. Placement is exact only while `group` is
#' present -- that is what identifies each country's separate pieces, and the
#' label goes on the largest one.
#'
#' @param mapping Aesthetic mapping; defaults to `aes(label = iso3c)`.
#' @param data Optional layer data, as for any `ggplot2` geom: a frame (label
#'   only those countries -- the usual way to label a handful rather than all
#'   two hundred), or a function of the plot's data. Whatever you pass is
#'   reduced to one centroid per country before it is drawn. Defaults to the
#'   plot's own data.
#' @param repel Use `ggrepel` to avoid overlaps (default `TRUE`). Falls back to
#'   plain labels, with a one-time note, when `ggrepel` is not installed.
#' @param flag If `TRUE`, label with flag emoji instead of the mapped label.
#' @param size Label text size.
#' @param ... Passed to the underlying text geom.
#'
#' @return A `ggplot2` layer.
#' @export
#' @examples
#' \donttest{
#' library(ggplot2)
#' snap <- countryatlas::world_snapshot$countries
#' mapdf <- attach_geometry(snap, geometry = "polygon")
#'
#' # Labelling all 188 countries at once is unreadable, and ggrepel responds
#' # by dropping nearly every label. Pass `data` to choose a subset ...
#' world_map(mapdf, gdp_per_capita) +
#'   geom_country_labels(
#'     data = ~ dplyr::filter(.x, iso3c %in% c("USA", "BRA", "CHN", "IND", "ZAF"))
#'   )
#'
#' # ... or zoom in, where there is room for every label.
#' europe <- attach_geometry(
#'   dplyr::filter(snap, continent == "Europe"), geometry = "polygon")
#' world_map(europe, gdp_per_capita) +
#'   geom_country_labels(size = 2.5) +
#'   coord_quickmap(xlim = c(-25, 45), ylim = c(34, 72))
#' }
geom_country_labels <- function(mapping = NULL, data = NULL, repel = TRUE,
                                flag = FALSE, size = 3, ...) {
  check_bool(repel, "repel")
  check_bool(flag, "flag")
  # `size` feeds ggplot2's own arithmetic, so a string or a vector failed deep
  # inside the geom rather than here; `mapping` reaches modifyList(), which
  # errors on anything that is not a list.
  check_number(size, "size", lo = 0)
  if (!is.null(mapping) && !inherits(mapping, "uneval")) {
    wdj_abort(c(
      "{.arg mapping} must be a {.fn ggplot2::aes} mapping.",
      "x" = "Got {.obj_type_friendly {mapping}}.",
      "i" = 'Write {.code mapping = ggplot2::aes(label = country)}.'
    ))
  }
  explicit <- !is.null(data)
  to_centroids <- function(d) {
    # An sf frame has no long/lat columns, so the layer's own aes() died on
    # rlang's "Column `long` not found in `.data`" before ever reaching the
    # guard below. Say what to use instead.
    if (is_sf(d)) {
      wdj_abort(c(
        "{.fn geom_country_labels} needs the polygon backend.",
        "x" = "Got an sf frame, which has no {.field long}/{.field lat} columns.",
        "i" = 'Attach polygon geometry with
               {.code attach_geometry(data, geometry = "polygon")}, or label an
               sf map with {.code ggplot2::geom_sf_text(aes(label = iso3c))}.'
      ), call = verb_env())
    }
    if (!all(c("long", "lat", "iso3c") %in% names(d))) {
      # Silently empty is right for the *plot's* data (a multi-layer plot may
      # hand this geom a frame it has nothing to say about), but not for a frame
      # the caller passed on purpose -- that used to reach ggplot2's "Column
      # `long` not found in `.data`" from inside the layer's aes, naming neither
      # the geom nor the missing piece.
      if (explicit) {
        wdj_abort(c(
          "{.arg data} must carry the polygon backend's
           {.field long}/{.field lat}/{.field iso3c} columns.",
          "x" = "Got a frame with {.field {paste(setdiff(c('long','lat','iso3c'), names(d)), collapse = ', ')}} missing.",
          "i" = 'Subset the map frame itself
                 ({.code geom_country_labels(data = subset(mapdf, iso3c %in% keep))}),
                 or pass a function of the plot data
                 ({.code geom_country_labels(data = ~ subset(.x, continent == "Europe"))}).'
        ), call = verb_env())
      }
      return(d[0, , drop = FALSE])
    }
    # An empty frame reaches range() with nothing to range over, which warns
    # (twice, plus a dplyr deprecation about the row count) before returning
    # Inf/-Inf. There are no labels to place, so stop before that.
    if (!nrow(d)) return(d[0, , drop = FALSE])
    # A map whose vertices the verb projected keeps their degrees alongside:
    # the centroid is geography, so find it there and project it the same way.
    projected <- all(c(".wdj_lon", ".wdj_lat") %in% names(d))
    if (projected) {
      d_proj <- d
      d$long <- d$.wdj_lon
      d$lat <- d$.wdj_lat
    }
    # One antimeridian-safe centroid per country (largest piece), so the US /
    # Fiji / NZ labels don't drift into the wrong ocean.
    out <- if ("group" %in% names(d)) {
      polygon_centroids(d)
    } else {
      # Without `group` there are no piece boundaries, so the largest-piece rule
      # is unavailable and this is an approximation -- see
      # antimeridian_centre(). Keep `group` (the polygon backend always supplies
      # it) for exact placement. Pieces with no code are left out, as
      # polygon_centroids() leaves them: grouped together they were one
      # "NA" country placed at the mean of every uncoded piece.
      d[!is.na(d$iso3c), , drop = FALSE] %>%
        dplyr::group_by(.data$iso3c) %>%
        dplyr::summarise(
          centroid_lon = antimeridian_centre(.data$long),
          centroid_lat = mean(range(.data$lat, na.rm = TRUE)),
          .groups = "drop"
        )
    }
    names(out)[names(out) == "centroid_lon"] <- "long"
    names(out)[names(out) == "centroid_lat"] <- "lat"
    if (projected) {
      xy <- reproject_like(out$long, out$lat, d_proj)
      out$long <- xy$x
      out$lat <- xy$y
    }
    out$flag <- convert_country(out$iso3c, to = "flag", origin = "iso3c",
                                warn = FALSE)
    # The centroid reduction used to return iso3c/long/lat/flag and nothing
    # else, so geom_country_labels(mapping = aes(colour = continent)) died on
    # "object 'continent' not found" -- the ordinary reason to pass a mapping at
    # all. Carry each country's other columns through (first row per country;
    # the polygon backend repeats them down every vertex).
    rest <- setdiff(names(d), c(names(out), "long", "lat", "group", "order",
                                ".wdj_lon", ".wdj_lat"))
    if (length(rest)) {
      keep <- d[!duplicated(d$iso3c), c("iso3c", rest), drop = FALSE]
      out <- dplyr::left_join(out, keep, by = "iso3c", na_matches = "never",
                              relationship = "one-to-one")
    }
    out
  }
  # `data` used to be hard-wired to the centroid function while `...` was
  # documented as "passed to the underlying text geom" and forwarded to the very
  # same call -- so the ordinary ggplot2 idiom for labelling a *subset* of
  # countries, geom_country_labels(data = big_ones), died on R's "formal
  # argument "data" matched by multiple actual arguments". Take `data` as a real
  # argument and compose the centroid step onto whatever the caller supplied,
  # so a frame, a function or nothing all work and the centroid rule still runs.
  label_data <- if (is.null(data)) {
    to_centroids
  } else if (is.function(data) || rlang::is_formula(data)) {
    fn <- rlang::as_function(data)
    function(d) to_centroids(fn(d))
  } else {
    to_centroids(data)
  }

  # Build a self-contained mapping (don't inherit the plot's group/fill aes).
  lab <- if (isTRUE(flag)) ggplot2::aes(label = .data$flag) else
    ggplot2::aes(label = .data$iso3c)
  base_map <- ggplot2::aes(x = .data$long, y = .data$lat)
  # The caller's mapping *adds to* the defaults rather than replacing them.
  # modifyList(base_map, mapping) dropped `label` the moment any mapping was
  # supplied, so geom_country_labels(aes(colour = continent), flag = TRUE) drew
  # no labels at all and silently ignored `flag`.
  full_map <- utils::modifyList(utils::modifyList(base_map, lab),
                                mapping %||% ggplot2::aes())

  if (isTRUE(repel) && has_pkg("ggrepel")) {
    ggrepel::geom_text_repel(mapping = full_map, data = label_data, size = size,
                             inherit.aes = FALSE, ...)
  } else {
    # Asking for repelling and silently not getting it was the one degraded
    # backend the package did not announce (classInt, gganimate and rmapshaper
    # all say so). `repel = TRUE` is the default, so say it once rather than on
    # every call.
    if (isTRUE(repel)) {
      wdj_inform(
        c("i" = "Package {.pkg ggrepel} not installed; drawing plain labels without collision avoidance."),
        .frequency = "once", .frequency_id = "geom_country_labels-no-ggrepel"
      )
    }
    ggplot2::geom_text(mapping = full_map, data = label_data, size = size,
                       inherit.aes = FALSE, ...)
  }
}
