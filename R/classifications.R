# Dated classifications -------------------------------------------------------------
#
# A country's income group and region are facts about a date, not about a
# country: Viet Nam was lower middle income until 30 June 2026 and upper middle
# income from 1 July, and Pakistan was in South Asia until 30 June 2025. The
# package used to read both from whichever WDI release was installed, so the
# same call gave different answers on two machines and a panel was classified
# by today's list in every year. country_classifications dates them, and this
# reads it.

# Friendly scheme names, and the table's own.
CLASSIFICATION_SCHEMES <- c(income = "wb_income", region = "wb_region",
                            lending = "wb_lending")

# The date the "current" classification is read at: today, or the last day the
# bundled table covers when today is past it, so an old installation keeps its
# newest classification rather than returning NA for everyone.
classification_now <- function() {
  tab <- countryatlas::country_classifications
  last <- max(tab$to[tab$scheme == "wb_income"], na.rm = TRUE) - 1L
  min(Sys.Date(), last)
}

# The World Bank fiscal year a date falls in: FY t runs 1 July t-1 to 30 June t.
fiscal_year <- function(date) {
  y <- as.integer(format(date, "%Y"))
  y + (as.integer(format(date, "%m")) >= 7L)
}

# One value per element of `iso` for one scheme, at the dates `when`: a single
# interval join, as in_group() does, so a long panel is one pass.
classify_lookup <- function(iso, when, scheme) {
  tab <- countryatlas::country_classifications
  tab <- tab[tab$scheme == scheme, c("iso3c", "value", "from", "to"), drop = FALSE]
  rows <- tibble::tibble(.i = seq_along(iso), iso3c = iso, when = when)
  hit <- dplyr::inner_join(rows[!is.na(rows$when), , drop = FALSE], tab,
                           by = "iso3c", na_matches = "never",
                           relationship = "many-to-many")
  hit <- hit[(is.na(hit$from) | hit$from <= hit$when) &
               (is.na(hit$to) | hit$to > hit$when), , drop = FALSE]
  out <- rep(NA_character_, length(iso))
  out[hit$.i] <- hit$value
  out
}

#' Classify countries as they were classified at the time
#'
#' Add the World Bank's income group, region or lending category to a frame,
#' as in force on a date -- each row's own `year`, by default -- from the
#' bundled [country_classifications]. A panel spanning 2000 to 2026 gets the
#' income group each country had in each year, not today's list painted
#' across every year, and the July 2025 move of Afghanistan and Pakistan from
#' South Asia into the Middle East and North Africa region falls where it
#' happened.
#'
#' @param data A frame with an `iso3c` column, and a `year` column for a panel.
#' @param schemes Which classifications to add: any of `"income"`, `"region"`
#'   and `"lending"`. Each becomes a column of that name.
#' @param as_of `NULL` (default) classifies each row as of its `year`, or as of
#'   today when there is no `year` column. Otherwise one date or year for every
#'   row, or one per row; a bare year means 1 January of that year, as in
#'   [in_group()].
#' @param basis For income: `"in_effect"` (default) gives the class in force on
#'   the date; `"data_year"` gives the class *computed from* that year's income,
#'   which is published two fiscal years later. See below.
#'
#' @section The fiscal-year rule:
#' The World Bank classifies each economy once a year, on 1 July, and the
#' class holds for its fiscal year: fiscal year *t* runs from 1 July *t*-1 to
#' 30 June *t*, and its classification is set from GNI per capita (Atlas
#' method) for calendar year *t*-2.
#'
#' So for a row dated 2020, `basis = "in_effect"` reads 1 January 2020, which
#' falls in fiscal year 2020 (1 July 2019 to 30 June 2020), whose classes were
#' computed from 2018 incomes. `basis = "data_year"` reads the class computed
#' from 2020 incomes instead, which is fiscal year 2022's (in force from 1 July
#' 2021). The first answers "how was this country treated at the time"; the
#' second "where did this year's income put it". Regions and lending
#' categories have no data year and are always read as in force on the date.
#'
#' @return `data` with the requested columns -- `income` a factor in income
#'   order, `region` and `lending` character -- `NA` where the table has no
#'   classification for that country on that date (a country not yet a
#'   member, or a date before the table begins). Each added column carries a
#'   [source_info()] record naming the World Bank source and the fiscal years
#'   used.
#' @seealso [country_classifications], [in_group()], [world_data()]
#' @export
#' @examples
#' pan <- data.frame(iso3c = c("VNM", "VNM", "PAK", "PAK"),
#'                   year = c(2026, 2027, 2025, 2026))
#' classify_countries(pan, c("income", "region"))
#'
#' # The class computed from a year's income, two fiscal years on:
#' classify_countries(data.frame(iso3c = "VNM", year = 2024), "income",
#'                    basis = "data_year")
classify_countries <- function(data, schemes = c("income", "region"),
                               as_of = NULL,
                               basis = c("in_effect", "data_year")) {
  basis <- rlang::arg_match(basis)
  check_cols(data, "iso3c")
  if (!is.character(schemes) || !length(schemes) || anyNA(schemes)) {
    wdj_abort(c("{.arg schemes} must name at least one classification.",
                "i" = "Choose from {.val {names(CLASSIFICATION_SCHEMES)}}."))
  }
  schemes <- rlang::arg_match(schemes, names(CLASSIFICATION_SCHEMES),
                              multiple = TRUE)
  n <- nrow(data)
  raw <- ascii_upper(trimws(as.character(data$iso3c), whitespace = "[\\h\\v]"))
  iso <- suppressWarnings(wdj_to_iso3c(as.character(data$iso3c), origin = "iso3c"))
  # The table also classifies economies that no longer exist (YUG, CSK, SUN,
  # SCG, ANT), whose codes ISO 3166-1 has retired: read those as written.
  former <- is.na(iso) & raw %in% countryatlas::country_classifications$iso3c
  iso[former] <- raw[former]
  when <- if (!is.null(as_of)) {
    as_of_dates(as_of, n)
  } else if ("year" %in% names(data)) {
    check_numeric_col(data, "year")
    as_of_dates(data$year, n)
  } else {
    rep(classification_now(), n)
  }
  # "data_year": the class computed from year Y's income is fiscal year Y+2's,
  # in force from 1 July Y+1.
  income_when <- if (identical(basis, "data_year")) {
    y <- as.integer(format(when, "%Y"))
    as.Date(ifelse(is.na(y), NA_character_, sprintf("%d-07-01", y + 1L)))
  } else when
  warn_overwrite(data, schemes)
  info <- list()
  for (sc in schemes) {
    at <- if (identical(sc, "income")) income_when else when
    v <- classify_lookup(iso, at, CLASSIFICATION_SCHEMES[[sc]])
    data[[sc]] <- if (identical(sc, "income")) factor(v, levels = income_levels()) else v
    fys <- sort(unique(fiscal_year(at[!is.na(at)])))
    info[[sc]] <- source_info_rows(
      sc, source = "World Bank classification",
      indicator = CLASSIFICATION_SCHEMES[[sc]],
      label = switch(sc, income = "Income group (GNI per capita, Atlas method)",
                     region = "World Bank region",
                     lending = "Lending category (IDA, IBRD, Blend)"),
      vintage = if (length(fys) == 1L) sprintf("FY%d", fys) else if (length(fys))
        sprintf("FY%d-FY%d", min(fys), max(fys)) else NA_character_,
      licence = "CC BY 4.0",
      citation = "World Bank. World Bank Country and Lending Groups; Historical classification by income (OGHIST).")
  }
  data <- set_source_info(data, carry_existing(data, dplyr::bind_rows(info)))
  data
}
