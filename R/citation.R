# Citations for a map -------------------------------------------------------------

# The references behind the package's methods, by key: what map_citation()
# picks from, and what inst/CITATION lists in full.
method_refs <- function() {
  list(
    natural_earth = utils::bibentry(
      bibtype = "Manual", title = "Natural Earth: Free vector and raster map data",
      author = utils::person("Natural Earth"), organization = "Natural Earth",
      year = "2024", note = "Version 5.1.1, 1:50m admin-0 countries; public domain",
      url = "https://www.naturalearthdata.com/"),
    equal_earth = utils::bibentry(
      bibtype = "Article", title = "The Equal Earth map projection",
      author = c(utils::person("Bojan", "Savric"), utils::person("Tom", "Patterson"),
                 utils::person("Bernhard", "Jenny")),
      journal = "International Journal of Geographical Information Science",
      volume = "33", number = "3", pages = "454--465", year = "2019",
      doi = "10.1080/13658816.2018.1504949"),
    quantile = utils::bibentry(
      bibtype = "Article",
      title = "Evaluation of methods for classifying epidemiological data on choropleth maps in series",
      author = c(utils::person("Cynthia A.", "Brewer"), utils::person("Linda", "Pickle")),
      journal = "Annals of the Association of American Geographers",
      volume = "92", number = "4", pages = "662--681", year = "2002",
      doi = "10.1111/1467-8306.00310"),
    jenks = utils::bibentry(
      bibtype = "Article",
      title = "Error on choroplethic maps: definition, measurement, reduction",
      author = c(utils::person("George F.", "Jenks"), utils::person("Fred C.", "Caspall")),
      journal = "Annals of the Association of American Geographers",
      volume = "61", number = "2", pages = "217--244", year = "1971",
      doi = "10.1111/j.1467-8306.1971.tb00779.x"),
    fisher = utils::bibentry(
      bibtype = "Article", title = "On grouping for maximum homogeneity",
      author = utils::person("Walter D.", "Fisher"),
      journal = "Journal of the American Statistical Association",
      volume = "53", number = "284", pages = "789--798", year = "1958",
      doi = "10.1080/01621459.1958.10501479"),
    headtails = utils::bibentry(
      bibtype = "Article",
      title = "Head/tail breaks: a new classification scheme for data with a heavy-tailed distribution",
      author = utils::person("Bin", "Jiang"), journal = "The Professional Geographer",
      volume = "65", number = "3", pages = "482--494", year = "2013",
      doi = "10.1080/00330124.2012.700499"),
    vsup = utils::bibentry(
      bibtype = "InProceedings", title = "Value-suppressing uncertainty palettes",
      author = c(utils::person("Michael", "Correll"), utils::person("Dominik", "Moritz"),
                 utils::person("Jeffrey", "Heer")),
      booktitle = "Proceedings of the 2018 CHI Conference on Human Factors in Computing Systems",
      pages = "1--11", year = "2018", doi = "10.1145/3173574.3174216"),
    value_by_alpha = utils::bibentry(
      bibtype = "Article",
      title = "Value-by-alpha maps: an alternative technique to the cartogram",
      author = c(utils::person("Robert E.", "Roth"), utils::person("Andrew W.", "Woodruff"),
                 utils::person("Zachary F.", "Johnson")),
      journal = "The Cartographic Journal", volume = "47", number = "2",
      pages = "130--140", year = "2010", doi = "10.1179/000870409X12488753453372"),
    cshapes = utils::bibentry(
      bibtype = "Article",
      title = "Mapping the international system, 1886-2019: the CShapes 2.0 dataset",
      author = c(utils::person("Guy", "Schvitz"), utils::person("Seraina", "R\u00fcegger"),
                 utils::person("Luc", "Girardin"), utils::person("Lars-Erik", "Cederman"),
                 utils::person("Nils", "Weidmann"), utils::person("Kristian Skrede", "Gleditsch")),
      journal = "Journal of Conflict Resolution", volume = "66", number = "1",
      pages = "144--161", year = "2022", doi = "10.1177/00220027211013563"),
    fdr_lisa = utils::bibentry(
      bibtype = "Article",
      title = "Controlling the false discovery rate: a new application to account for multiple and dependent tests in local statistics of spatial association",
      author = c(utils::person("Marcia", "Caldas de Castro"), utils::person("Burton H.", "Singer")),
      journal = "Geographical Analysis", volume = "38", number = "2",
      pages = "180--208", year = "2006", doi = "10.1111/j.0016-7363.2006.00682.x"),
    ternary = utils::bibentry(
      bibtype = "Article",
      title = "The centered ternary balance scheme: a technique to visualize surfaces of unbalanced three-part compositions",
      author = utils::person("Jonas", "Sch\u00f6ley"), journal = "Demographic Research",
      volume = "44", number = "19", pages = "443--458", year = "2021",
      doi = "10.4054/DemRes.2021.44.19"),
    lisa = utils::bibentry(
      bibtype = "Article", title = "Local indicators of spatial association -- LISA",
      author = utils::person("Luc", "Anselin"), journal = "Geographical Analysis",
      volume = "27", number = "2", pages = "93--115", year = "1995",
      doi = "10.1111/j.1538-4632.1995.tb00338.x")
  )
}

# A data source's record as a reference: the provider, the series, the release
# and when it was fetched, and the licence.
source_ref <- function(row) {
  who <- source_display(row$source %||% NA_character_)
  title <- row$label
  if (is.na(title) || !nzchar(title)) title <- row$indicator %||% row$column
  # A bare $ opens LaTeX math in the formatter ("constant 2015 US$").
  title <- gsub("$", "\\$", title, fixed = TRUE)
  note <- paste(stats::na.omit(c(
    if (!is.na(row$indicator)) paste("Series", row$indicator),
    if (!is.na(row$vintage)) paste("release", row$vintage),
    if (!is.na(row$fetched_at)) paste("accessed", row$fetched_at),
    if (!is.na(row$licence)) paste("licence", row$licence))), collapse = "; ")
  yr <- substr(row$provider_updated %|% row$fetched_at %|% format(Sys.Date()), 1, 4)
  utils::bibentry(bibtype = "Misc", title = title,
                  author = utils::person(who %|% "Unknown provider"),
                  year = if (is.na(yr)) "n.d." else yr,
                  note = if (nzchar(note)) note else NULL)
}

#' Cite exactly what a map used
#'
#' The references for the sources and methods behind one map: the data, from
#' its [source_info()] record; the geometry; the projection; the
#' classification; and the method behind a value-suppressing palette, a
#' value-by-alpha map, a ternary map, historical borders or a
#' false-discovery-rate LISA map.
#' Cite these alongside the package itself (`citation("countryatlas")`).
#'
#' @param p A map from one of the package's map verbs.
#' @param format `"text"` (default), formatted references, or `"bibtex"`.
#'
#' @return For `"text"`, a character vector, one reference per element; for
#'   `"bibtex"`, a `Bibtex` object for a `.bib` file.
#' @seealso [map_provenance()], [source_info()]
#' @export
#' @examples
#' \donttest{
#' snap <- countryatlas::world_snapshot$countries
#' p <- world_map(attach_geometry(snap), gdp_per_capita)
#' map_citation(p)
#' }
map_citation <- function(p, format = c("text", "bibtex")) {
  format <- rlang::arg_match(format)
  if (!inherits(p, "ggplot")) {
    wdj_abort(c("{.arg p} must be a map from one of the package's map verbs.",
                "x" = "Got {.obj_type_friendly {p}}."))
  }
  prov <- attr(p, "countryatlas_provenance")
  if (is.null(prov)) {
    wdj_abort("{.arg p} carries no countryatlas provenance to cite from.")
  }
  refs <- method_refs()
  keys <- character(0)
  data <- gg_plot_data(p)
  historical <- !is.null(data) && "gwcode" %in% names(data)
  if (historical) keys <- c(keys, "cshapes") else
    if ((prov$backend %||% "") %in% c("polygon", "sf", "tile-grid", "grid")) keys <- c(keys, "natural_earth")
  if (startsWith(current_projection(p, prov$projection %||% NA_character_) %||% "", "equal_earth")) {
    keys <- c(keys, "equal_earth")
  }
  st <- prov$style %||% ""
  keys <- c(keys,
            if (st %in% c("quantile") || grepl("^value-by-alpha \\(quantile", st)) "quantile",
            if (st == "jenks") "jenks", if (st == "fisher") "fisher",
            if (st == "headtails") "headtails", if (st == "vsup") "vsup",
            if (startsWith(st, "value-by-alpha")) "value_by_alpha",
            if (startsWith(st, "ternary")) "ternary",
            if (!is.null(prov$p_adjust)) "lisa",
            if (identical(prov$p_adjust, "fdr")) "fdr_lisa")
  bib <- do.call(c, unname(refs[unique(keys)]))
  src <- prov$sources
  if (!is.null(src) && nrow(src)) {
    src <- src[!duplicated(src[, c("source", "indicator", "vintage")]), , drop = FALSE]
    data_refs <- lapply(seq_len(nrow(src)), function(i) source_ref(src[i, ]))
    bib <- do.call(c, c(data_refs, if (length(bib)) list(bib)))
  }
  if (!length(bib)) return(character(0))
  if (identical(format, "bibtex")) return(utils::toBibtex(bib))
  gsub("\\$", "$", format(bib, style = "text"), fixed = TRUE)
}
