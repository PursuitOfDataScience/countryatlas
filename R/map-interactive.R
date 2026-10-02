# Maps: interactive and alternative renderers ---------------------------------
#
# interactive_map()'s engines and the tmap engine of world_map().

#' Web-ready interactive choropleth
#'
#' An interactive choropleth with hover and zoom, for dashboards and
#' R Markdown / Quarto. Engines are all optional `Suggests`.
#'
#' @param data A map-ready frame (polygon or sf). The `"leaflet"` engine will
#'   attach geometry itself if given a country-level table; the others require
#'   it already attached.
#' @param fill The fill column (unquoted).
#' @param tooltip Optional tooltip column (unquoted).
#' @param engine `"plotly"` (default), `"ggiraph"`, `"leaflet"`, `"mapgl"` or
#'   `"ggsql"`. `"mapgl"` renders through MapLibre GL -- vector tiles, smooth
#'   zoom and a genuine interactive globe, which is what turns [globe_map()]
#'   from a static novelty into something you can turn. It needs an `sf` frame
#'   (database-side rendering to a Vega-Lite widget; needs an `sf` frame and
#'   `ggsql` >= 0.4.1, the version that added the `DRAW spatial` clause).
#'   `tooltip` is honoured by the `"ggiraph"` and `"leaflet"` engines (defaults
#'   to `fill` when omitted); `"plotly"`'s hover is controlled by `world_map()`
#'   aesthetics instead, and `"ggsql"` has no hover concept.
#' @param ... Passed to [world_map()] for the `"plotly"` engine, to
#'   [world_query()] for `"ggsql"`, and to [mapgl::maplibre()] for `"mapgl"`.
#'   The `"ggiraph"` engine assembles its own map and takes world_map()'s
#'   classification arguments (`style`, quantile by default, `n_bins`,
#'   `palette`, `breaks`, `midpoint`); `"leaflet"` takes none. Both warn rather
#'   than ignore what they cannot use.
#'
#' @return An interactive widget.
#' @export
#' @examples
#' \dontrun{
#' world_data(2020) |> interactive_map(gdp_per_capita)
#' world_data(2020, geometry = "sf") |>
#'   interactive_map(gdp_per_capita, engine = "ggsql", transform = "log10")
#' }
interactive_map <- function(data, fill, tooltip = NULL,
                            engine = c("plotly", "ggiraph", "leaflet", "ggsql",
                                       "mapgl"),
                            ...) {
  engine <- rlang::arg_match(engine)
  fill_q <- rlang::enquo(fill)
  tooltip_q <- rlang::enquo(tooltip)
  # Cheap checks before the environment gates, as in globe_map()/spin_globe():
  # a non-sf frame used to be told to install ggsql >= 0.4.1 (which has not
  # shipped in the R bindings at all), and would only learn the real problem
  # after chasing a package it did not need.
  if (identical(engine, "ggsql") && !is_sf(data)) {
    wdj_abort(c(
      '{.code engine = "ggsql"} needs an sf frame so {.code DRAW spatial} has geometry.',
      "i" = 'Build one with {.code world_data(..., geometry = "sf")} or {.fn attach_geometry}.'
    ))
  }
  if (identical(engine, "mapgl") && !is_sf(data)) {
    wdj_abort(c(
      '{.code engine = "mapgl"} needs an sf frame: MapLibre draws real geometry,
       not a polygon table.',
      "i" = 'Build one with {.code world_data(..., geometry = "sf")} or {.fn attach_geometry}.'
    ))
  }
  # `DRAW spatial` -- the clause world_query() emits -- arrived in ggsql 0.4.1.
  # Older ggsql accepts the call and then fails inside its own SQL front end on
  # a clause it does not know, so gate on the version, not mere presence.
  need_pkg(engine, sprintf("for interactive_map(engine = \"%s\")", engine),
           version = if (identical(engine, "ggsql")) "0.4.1" else NULL)

  # The three engines below that build their own colour scale meet an
  # infinity without world_map()'s handling: leaflet's colorNumeric() died on
  # "Wasn't able to determine range of domain", and the other two drew it as
  # no data without a word. Say so as world_map() does, and hand them the
  # no-data value it is.
  if (engine %in% c("ggiraph", "leaflet", "mapgl")) {
    fill_name0 <- quo_arg_name(fill_q, "fill")
    if (fill_name0 %in% names(data) && is.numeric(data[[fill_name0]])) {
      warn_infinite_fill(data, fill_name0)
      data[[fill_name0]][is.infinite(data[[fill_name0]])] <- NA
    }
  }

  if (engine == "ggsql") {
    need_pkg(c("sf", "DBI", "duckdb"),
             "for interactive_map(engine = \"ggsql\")")
    q <- world_query(!!fill_q, source = "countryatlas_world", ...)
    # The binding gate above is for DRAW spatial; the projection may need a
    # later engine (Equal Earth arrived in 0.5.0). Checked before anything is
    # registered, so an old ggsql refuses by name instead of failing inside its
    # own SQL front end on a projection it does not know.
    need_pkg("ggsql", 'for the projection in interactive_map(engine = "ggsql")',
             version = attr(q, "countryatlas_ggsql_version"))
    reader <- ggsql::duckdb_reader()
    ggsql::ggsql_register(reader, ggsql_wkb_frame(data), "countryatlas_world")
    return(ggsql::ggsql_execute(reader, unclass(q)))
  }

  if (engine == "mapgl") {
    need_pkg(c("mapgl", "sf"), 'for interactive_map(engine = "mapgl")')
    fill_name <- quo_arg_name(fill_q, "fill")
    check_cols(data, fill_name)
    # MapLibre wants lon/lat; the package's sf frames are projected by default.
    g <- quietly_sf(sf::st_transform(data, 4326L))
    tip <- if (rlang::quo_is_null(tooltip_q)) fill_name else quo_arg_name(tooltip_q, "tooltip")
    check_cols(g, tip)
    m <- mapgl::maplibre(bounds = g, ...)
    m <- mapgl::add_fill_layer(
      m, id = "countryatlas", source = g,
      fill_color = if (is.numeric(g[[fill_name]])) {
        if (!any(is.finite(g[[fill_name]]))) {
          # Nothing to scale: interpolate_palette() refuses an all-missing
          # column outright ("No non-missing values found in data_values"),
          # where the ggplot2 engines draw every country as no-data. So does
          # this, in interpolate_palette()'s own no-data colour.
          "grey"
        } else {
          # Exactly k colours for k breaks. viridis_hex() floors at two, so a
          # column with a single distinct value -- a constant, or one country
          # with data -- got one quantile break and two colours, and mapgl
          # refused the pair ("`values` and `stops` must have the same
          # length"). Its note that the quantiles collapsed describes a
          # legitimate input, and the scale it then builds is right.
          withCallingHandlers(
            mapgl::interpolate_palette(
              data = g, column = fill_name, method = "quantile", n = 5,
              palette = function(k) grDevices::hcl.colors(k, palette = "viridis")
            )$expression,
            warning = function(w) {
              if (grepl("unique quantiles possible", conditionMessage(w),
                        fixed = TRUE)) invokeRestart("muffleWarning")
            })
        }
      } else {
        # The categories and their colour stops are computed *once* and paired
        # by position. They used to be derived independently from the same
        # column, and viridis_hex() floors at two colours, so exactly one
        # distinct category gave 1 value against 2 stops and mapgl rejected the
        # mismatch outright. head() rather than a second count, so the two can
        # never disagree again.
        #
        # method = "radix": plain sort() consults the collation locale, and
        # these values are paired positionally with the stops, so the same
        # categories were drawn in different colours on machines with
        # different locales.
        {
          cats <- unique(as.character(g[[fill_name]]))
          cats <- cats[!is.na(cats)]
          cats <- cats[order(cats, method = "radix")]
          # No category at all builds a `match` with no label/output pair,
          # which MapLibre rejects in the browser; draw the no-data colour,
          # as the numeric branch does.
          if (!length(cats)) "grey" else
            mapgl::match_expr(column = fill_name, values = cats,
                              stops = utils::head(viridis_hex(length(cats)),
                                                  length(cats)))
        }
      },
      fill_opacity = 0.85, fill_outline_color = "#33333366",
      tooltip = tip, hover_options = list(fill_opacity = 1)
    )
    return(m)
  }

  if (engine == "plotly") {
    # plotly's converter cannot take an orthographic view: it fails on the
    # empty geometry of every country beyond the horizon ("number of columns
    # of matrices must match"), and on the visible hemisphere alone as well.
    # That was so before the horizon cut existed too. Say which engines can.
    if (identical(rlang::list2(...)$projection, "orthographic")) {
      wdj_abort(c(
        '{.code engine = "plotly"} cannot draw the orthographic projection.',
        "i" = 'Use {.code engine = "mapgl"}, or {.code globe_map(data, fill,
               interactive = TRUE)} for a globe you can turn.'
      ), class = "countryatlas_engine_projection")
    }
    # plotly draws ordinary layers in their own units and ignores coord_sf(),
    # so the vertices are projected before the plot is built.
    .wdj_state$project_vertices <- TRUE
    on.exit(.wdj_state$project_vertices <- NULL, add = TRUE)
    p <- world_map(data, !!fill_q, ...)
    return(plotly::ggplotly(p))
  }
  if (engine == "ggiraph") {
    need_pkg("ggiraph")
    # This branch assembles its own ggplot rather than calling world_map() (see
    # below), so of world_map()'s arguments it takes the classification ones --
    # `style` (quantile by default, as world_map()), `n_bins`, `palette`,
    # `breaks` and `midpoint` -- and names the rest as unused.
    dots <- rlang::list2(...)
    cls_args <- c("style", "n_bins", "palette", "breaks", "midpoint")
    dot_names <- names(dots) %||% rep("", length(dots))
    warn_dots_unused(dots[!dot_names %in% cls_args], "ggiraph",
                     'engine = "plotly"')
    # This branch assembles its own ggplot instead of calling world_map(), so it
    # needs the same check: without it, a country-level frame reached
    # geom_polygon_interactive() and failed at render time on `.data$long`,
    # while engine = "plotly" reported the problem properly.
    check_map_geometry(data)
    fill_name <- quo_arg_name(fill_q, "fill")
    tooltip_name <- if (!rlang::quo_is_null(tooltip_q)) {
      quo_arg_name(tooltip_q, "tooltip")
    }
    check_cols(data, c(fill_name, tooltip_name))
    # data_id below is `iso3c`, which nothing had checked for: check_cols()
    # covers `fill` and `tooltip`, and check_map_geometry() does not require a
    # key -- so a frame without one failed at render time from inside rlang.
    # Same guard the leaflet branch now carries.
    check_cols(data, "iso3c")
    style <- rlang::arg_match0(dots$style %||% "quantile", MAP_STYLES,
                               arg_nm = "style")
    style <- resolve_style(style, !is.null(dots$style), dots$breaks,
                           dots$midpoint, dots$n_bins %||% 5, data[[fill_name]])
    check_categorical_fill(style, data[[fill_name]], fill_name)
    n_bins <- dots$n_bins %||% 5
    binned <- apply_binned_fill(data, fill_name, style, n_bins,
                                breaks = dots$breaks, midpoint = dots$midpoint)
    data <- binned$data
    fill_mapped <- binned$fill
    # Resolved through quo_col_mapping() rather than spliced raw: the mapgl and
    # leaflet engines below already key off `fill_name`, and this branch is the
    # one that did not.
    tooltip_mapped <- if (is.null(tooltip_name)) {
      quo_col_mapping(fill_name)
    } else {
      quo_col_mapping(tooltip_name)
    }
    scale <- add_fill_scale(style, dots$palette, n_bins, "No data", fill_name,
                            binned = binned)
    if (is_sf(data)) {
      p <- ggplot2::ggplot(data) +
        ggiraph::geom_sf_interactive(
          ggplot2::aes(fill = !!fill_mapped, tooltip = !!tooltip_mapped, data_id = .data$iso3c)
        ) + scale + theme_world_map()
    } else {
      pc <- wdj_polygon_coord()
      p <- ggplot2::ggplot(
        apply_polygon_transform(data, pc),
        ggplot2::aes(.data$long, .data$lat, group = .data$group)) +
        ggiraph::geom_polygon_interactive(
          ggplot2::aes(fill = !!fill_mapped, tooltip = !!tooltip_mapped, data_id = .data$iso3c)
        ) + scale + pc$coord + theme_world_map()
    }
    return(ggiraph::girafe(ggobj = p))
  }
  # leaflet
  need_pkg(c("leaflet", "sf"))
  # This engine builds its own leaflet map, so `...` reaches nothing here
  # either -- and unlike the other four it was not documented at all.
  warn_dots_unused(rlang::list2(...), "leaflet", 'engine = "plotly"')
  check_cols(data, c(
    quo_arg_name(fill_q, "fill"),
    if (!rlang::quo_is_null(tooltip_q)) quo_arg_name(tooltip_q, "tooltip")
  ))
  if (!is_sf(data)) {
    # This branch gates on !is_sf, so `data` may be a *polygon* frame: reduced to
    # one row per country it still carries long/lat/group, which attach_geometry()
    # now (rightly) refuses. Strip them. (globe_map's polygon branch gates on the
    # columns themselves, so it needs no equivalent.)
    data <- attach_geometry(
      drop_map_geometry(
        distinct_countries(tibble::as_tibble(data))),
      geometry = "sf")
  }
  fill_name <- quo_arg_name(fill_q, "fill")
  tooltip_name <- if (rlang::quo_is_null(tooltip_q)) fill_name else quo_arg_name(tooltip_q, "tooltip")
  # A discrete fill used to reach colorNumeric() and die inside leaflet with
  # "Wasn't able to determine range of domain" -- the same defect
  # auto_fill_scale() was written to fix for the ggplot2 engines, and that the
  # mapgl branch above handles with match_expr(). `?interactive_map` documents
  # no per-engine restriction on `fill`, so branch here too.
  #
  # method = "radix" for the level order, as everywhere else in this file:
  # colorFactor() pairs levels with palette stops positionally, and plain
  # sort() consults the collation locale, which would colour the same
  # categories differently on different machines.
  # A fill with nothing to scale -- every value missing, or infinite and so
  # set to NA above -- died inside colorNumeric() on "Wasn't able to determine
  # range of domain", with base R's "no non-missing arguments to min" twice.
  # The ggplot2 engines draw such a map as all no-data, and so does this: any
  # domain will do when every value takes na.color, and there is no legend to
  # draw.
  vals <- data[[fill_name]]
  nothing <- if (is.numeric(vals)) !any(is.finite(vals)) else all(is.na(vals))
  pal <- if (is.numeric(vals)) {
    leaflet::colorNumeric("viridis", domain = if (nothing) c(0, 1) else vals,
                          na.color = "#dddddd")
  } else {
    lv <- unique(as.character(vals))
    lv <- lv[!is.na(lv)]
    leaflet::colorFactor("viridis",
                         levels = if (nothing) "" else lv[order(lv, method = "radix")],
                         na.color = "#dddddd")
  }
  # Values computed here rather than deferred to leaflet's `~` formulas, which
  # it evaluates against the data as an environment. Two problems with that,
  # both fixed by evaluating eagerly:
  #
  #  - `~ pal(get(fill_name))` looked up `pal` in that environment first, so a
  #    column named `pal` shadowed the palette function and leaflet then tried
  #    to call the column. This was the only place in the package reading a
  #    column with get() in a formula rather than [[.
  #  - `~ paste0(iso3c, ...)` read `iso3c` with no check that it is there.
  #    check_cols() covered `fill` and `tooltip`; check_map_geometry() does not
  #    require iso3c, so a frame without one failed at render time from inside
  #    leaflet. The label is the only thing that needs it, so ask for it.
  check_cols(data, "iso3c")
  shapes <- sf::st_transform(data, 4326L)
  m <- leaflet::leaflet(shapes) |>
    leaflet::addPolygons(
      fillColor = pal(shapes[[fill_name]]), weight = 0.5, color = "grey",
      fillOpacity = 0.8,
      label = paste0(shapes$iso3c, ": ", shapes[[tooltip_name]])
    )
  if (nothing) return(m)
  leaflet::addLegend(m, pal = pal, values = shapes[[fill_name]],
                     title = fill_name)
}

# Viridis as plain hex, for the renderers that want colours rather than a
# ggplot2 scale (mapgl, and anything else speaking a web palette).
viridis_hex <- function(n = 5) {
  grDevices::hcl.colors(max(2L, as.integer(n)), palette = "viridis")
}

# The tmap backend. Deliberately thin: tmap has its own mature legend and layout
# machinery, so the job here is to hand it the same curated frame and the same
# classification choice, not to reproduce ggplot2's output through it. The
# package stays ggplot2-native -- this is an alternative renderer for people
# already working in tmap, not a second first-class path.
# The scale constructors this engine uses are the tmap 4 API; tmap 3 configured
# scales through arguments on tm_polygons() and exports none of them.
# DESCRIPTION pins no version on any Suggests package, so need_pkg("tmap") is
# satisfied by *any* tmap -- and an older one then failed on R's own
# "'tm_scale_intervals' is not an exported object from 'namespace:tmap'", which
# names neither the cause nor the cure. Detect the capability rather than a
# version number, exactly as as_ggsql_source() does for duckdb's `shared_home`:
# the capability is the thing actually required, and it stays correct whichever
# release introduced it.
tmap_scale_api <- c("tm_scale_intervals", "tm_scale_continuous",
                    "tm_scale_categorical")

check_tmap_api <- function(have = getNamespaceExports("tmap"),
                           call = rlang::caller_env()) {
  missing_api <- setdiff(tmap_scale_api, have)
  if (!length(missing_api)) return(invisible(TRUE))
  wdj_abort(c(
    "The installed {.pkg tmap} is too old for {.code engine = \"tmap\"}.",
    "x" = "It does not export {.fn {missing_api}}.",
    "i" = "The scale constructors arrived in {.pkg tmap} 4. Upgrade it, or use
           {.code engine = \"ggplot2\"}."
  ), class = "countryatlas_old_tmap", call = call)
}

world_map_tmap <- function(data, fill_name, style, n_bins, palette, title,
                           legend, na_label, borders, sf_mode,
                           projection = "equal_earth", recenter = NULL,
                           breaks = NULL, call = rlang::caller_env()) {
  need_pkg("tmap", 'for world_map(engine = "tmap")')
  check_tmap_api(call = call)
  if (!sf_mode) {
    wdj_abort(c(
      '{.code engine = "tmap"} needs an sf frame.',
      "i" = 'tmap draws sf geometry; build one with
             {.code attach_geometry(data, geometry = "sf")}.',
      "*" = 'The polygon backend is ggplot2-only.'
    ), call = call)
  }
  # tm_scale_intervals() is the *interval* scale, and "cont"/"cat" are not
  # interval styles -- they name different constructors. Passing them through
  # meant the default style could not draw at all ('Invalid style. Style should
  # be one of "fixed", "sd", "equal", "pretty", ...') and a categorical fill
  # warned that an interval scale was being applied to non-numeric data. Each
  # style now reaches the constructor tmap actually has for it.
  # `na_label` arrived here and went nowhere: the ggplot path renames the NA
  # key through discrete_na_labels(), and every tmap scale takes `label.na`,
  # so a caller who set it just got tmap's own default with no sign that their
  # label had been dropped. Omit the argument entirely when the caller meant
  # "leave the default alone", so tmap's own formatting still applies.
  na_lab <- na_label_value(na_label)
  tm_scale <- function(f, ...) {
    args <- list(...)
    if (!is.null(na_lab)) args$label.na <- na_lab
    do.call(f, args)
  }
  fill_scale <- switch(
    style,
    continuous = tm_scale(tmap::tm_scale_continuous,
                          values = palette %||% "viridis"),
    categorical = tm_scale(tmap::tm_scale_categorical,
                           values = palette %||% grDevices::hcl.colors(
                             max(1L, length(unique(stats::na.omit(
                               sf_drop(data)[[fill_name]])))),
                             CATEGORICAL_PALETTE)),
    # "binned" is equal intervals, as on the ggplot2 engine, where n_bins
    # equal-width classes replaced ggplot2's round-number n.breaks. This
    # engine mapped it to tmap's "pretty", so the same call drew different
    # classes depending on `engine`: 0-20k-40k... bins here against five
    # equal ones from the data's own range there.
    # The classInt styles go through by name, as tmap reads them; fixed
    # breaks go as tmap's `breaks`.
    if (identical(style, "fixed")) {
      tm_scale(tmap::tm_scale_intervals, style = "fixed",
               breaks = open_breaks(breaks, sf_drop(data)[[fill_name]], fill_name),
               values = palette %||% "viridis")
    } else {
      tm_scale(tmap::tm_scale_intervals,
        style = switch(style, binned = , equal = "equal", style),
        n = n_bins, values = palette %||% "viridis")
    }
  )
  # `projection` and `recenter` were dropped here: this engine drew in the
  # frame's own CRS while world_map() documents the argument -- and the
  # default, Equal Earth, went unhonoured just as silently as an explicit
  # request. wdj_crs() resolves both and validates the name, and tm_shape()
  # takes the proj4 string it returns.
  #
  # tmap projects with the same PROJ transform coord_sf() does, so an
  # orthographic view needs the same cut at the horizon: without it four of
  # six sampled viewpoints failed in tmap's drawing with "Invalid graphics
  # path". Every row is kept, so the provenance below is unchanged. The CRS is
  # built first so a bad `recenter` is reported as such before the cut uses it.
  crs <- wdj_crs(projection, recenter, call = call)
  data <- clip_for_projection(data, projection, recenter)
  p <- tmap::tm_shape(data, crs = crs) +
    tmap::tm_polygons(
      fill = fill_name,
      fill.scale = fill_scale,
      fill.legend = tmap::tm_legend(title = legend %||% fill_name),
      col = if (borders) "grey30" else NULL,
      lwd = 0.2
    ) +
    (if (is.null(title)) tmap::tm_layout() else tmap::tm_title(title))
  # Provenance travels on the tmap object too. ?map_provenance says `x` is "a
  # plot returned by any of the package's map verbs -- world_map(), ...", and
  # this engine attached nothing, so map_provenance() refused it with an error
  # naming world_map() as the thing that would have worked -- which is what the
  # caller used. The attribute survives a tmap object exactly as it does a
  # ggplot one.
  wdj_provenance(p, data, fill_name, if (sf_mode) "sf" else "polygon",
                 projection = projection, style = style,
                 extra = list(n_bins = n_bins, engine = "tmap"))
}
