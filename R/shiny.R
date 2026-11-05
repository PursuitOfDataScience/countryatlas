# A Shiny module for world_map() ----------------------------------------------
#
# Deferred since 2.0.0 as a [could] item (V4 in the 4.0.0 plan). shiny stays in
# Suggests: both functions check for it at call time, so nothing here loads it
# for anyone who does not build an app.

#' A Shiny module that draws a world map
#'
#' `world_map_ui()` and `world_map_server()` put [world_map()] in a Shiny app:
#' a fill column, a classification, the number of classes and a projection to
#' choose from, and the map with its coverage caption and its alt text, which
#' a screen reader announces. The server returns the map as a reactive, so the
#' app can reuse it (a download button, a second view).
#'
#' @param id The module id, the same string in both calls.
#' @param style,projection,n_bins The initial classification, projection and
#'   number of classes; the user can change all three.
#' @param height The map's height, any CSS unit (default `"480px"`).
#' @param data The data to map: a frame with map geometry (see
#'   [attach_geometry()]), or one row per country with an `iso3c` column, which
#'   gets the bundled polygons attached once. A reactive returning either also
#'   works, for data the app filters.
#' @param fill The column selected first, as a string. `NULL` (the default)
#'   selects the first numeric column.
#' @param ... Passed to [world_map()], for example `palette`, `title` or
#'   `footnote`. The four arguments the inputs control (`fill`, `style`,
#'   `projection` and `n_bins`) are not accepted here.
#'
#' @return `world_map_ui()` returns a [shiny::tagList()] of the inputs and the
#'   plot output. `world_map_server()` returns a [shiny::reactive()] holding the
#'   current map, a ggplot.
#' @seealso [world_map()], [map_alt_text()]
#' @export
#' @examples
#' if (interactive() && requireNamespace("shiny", quietly = TRUE)) {
#'   ui <- shiny::fluidPage(world_map_ui("map"))
#'   server <- function(input, output, session) {
#'     world_map_server("map", world_snapshot$countries, fill = "gdp_per_capita")
#'   }
#'   shiny::shinyApp(ui, server)
#' }
world_map_ui <- function(id, style = "quantile", projection = "equal_earth",
                         n_bins = 5, height = "480px") {
  need_pkg("shiny", "for world_map_ui()", version = "1.6.0")
  check_string(id, "id")
  style <- check_choice(style, "style", shiny_map_styles())
  projection <- check_choice(projection, "projection",
                             c(wdj_projections(), "none"))
  check_number(n_bins, "n_bins", lo = 2, hi = 9)
  check_string(height, "height")
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::fluidRow(
      shiny::column(3, shiny::selectInput(ns("fill"), "Fill", choices = NULL)),
      shiny::column(3, shiny::selectInput(ns("style"), "Classes",
                                          choices = shiny_map_styles(),
                                          selected = style)),
      shiny::column(3, shiny::sliderInput(ns("n_bins"), "Number of classes",
                                          min = 2, max = 9, step = 1,
                                          value = as.integer(n_bins))),
      shiny::column(3, shiny::selectInput(ns("projection"), "Projection",
                                          choices = c(wdj_projections(), "none"),
                                          selected = projection))
    ),
    shiny::plotOutput(ns("map"), height = height)
  )
}

#' @rdname world_map_ui
#' @export
world_map_server <- function(id, data, fill = NULL, ...) {
  need_pkg("shiny", "for world_map_server()", version = "1.6.0")
  check_string(id, "id")
  if (!is.null(fill)) check_string(fill, "fill")
  dots <- list(...)
  taken <- intersect(names(dots), c("fill", "style", "projection", "n_bins"))
  if (length(taken)) {
    wdj_abort(c(
      "{.arg {taken}} {?is/are} set by the module's inputs, not through {.arg ...}.",
      "i" = "Set the starting value in {.fn world_map_ui} instead."
    ))
  }
  # A static frame is checked and prepared once, here, so one that cannot be
  # mapped fails when the app starts rather than inside the first render.
  static <- !shiny::is.reactive(data)
  if (static) data <- shiny_map_frame(data)
  shiny::moduleServer(id, function(input, output, session) {
    frame <- if (static) shiny::reactive(data)
             else shiny::reactive(shiny_map_frame(data()))
    shiny::observeEvent(frame(), {
      cols <- shiny_fill_columns(frame())
      current <- input$fill
      selected <- if (!is.null(current) && current %in% cols) current
                  else if (!is.null(fill) && fill %in% cols) fill
                  else cols[1]
      shiny::updateSelectInput(session, "fill", choices = cols,
                               selected = selected)
    })
    map <- shiny::reactive({
      d <- frame()
      shiny::req(input$fill, input$fill %in% names(d))
      rlang::inject(world_map(
        d, !!input$fill,
        style = !!(input$style %||% "quantile"),
        projection = !!(input$projection %||% "equal_earth"),
        n_bins = !!(input$n_bins %||% 5),
        !!!dots
      ))
    })
    output$map <- shiny::renderPlot(map(), res = 96,
                                    alt = function() map_alt_text(map()))
    map
  })
}

# The styles a numeric fill can take, in the order the select lists them.
shiny_map_styles <- function() {
  c("quantile", "continuous", "equal", "jenks", "fisher", "headtails", "sd")
}

# The frame the module maps: map geometry as given, or attached once to a
# country-level table.
shiny_map_frame <- function(data, call = rlang::caller_env()) {
  if (!is.data.frame(data)) {
    wdj_abort("{.arg data} must be a data frame, not {.obj_type_friendly {data}}.",
              call = call)
  }
  if (has_map_geometry(data)) return(data)
  if (!"iso3c" %in% names(data)) {
    wdj_abort(c(
      "{.arg data} has no map geometry and no {.field iso3c} column.",
      "i" = "Pass a frame from {.fn attach_geometry}, or one keyed on
             {.field iso3c}, which the module attaches itself."
    ), call = call)
  }
  attach_geometry(data)
}

# The columns offered as fills: numeric, and not a key or a coordinate.
shiny_fill_columns <- function(data) {
  d <- sf_drop(data)
  keep <- vapply(d, is.numeric, logical(1)) &
    !names(d) %in% c("long", "lat", "group", "order", "year") &
    !startsWith(names(d), ".")
  names(d)[keep]
}
