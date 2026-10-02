# Disputed territories ---------------------------------------------------------
#
# Every world map takes a political position, including the ones that think they
# do not. Natural Earth documents an explicit de facto policy; the EU's
# data-visualisation guidance counts roughly 188 disputed areas and notes that
# official publications must reflect an official position.
#
# This package's position is that it has none, and that pretending otherwise is
# the failure mode. So: [disputed_territories] records *that* a dispute exists
# and *who the parties are*, [dispute_policy()] lets the user state which
# convention they are using, and nothing here adjudicates. What the package can
# usefully do is stop a disputed area passing unremarked.

#' State which map convention you are using
#'
#' Disputed territories are drawn differently by different conventions, and a
#' map that does not say which one it used is making a choice silently. This
#' sets the session's convention so [world_map()] can record it and
#' [map_provenance()] can report it.
#'
#' @param policy One of:
#'   * `"none"` (default) -- no convention stated. Maps carry no dispute
#'     annotation, exactly as before.
#'   * `"de_facto"` -- boundaries as administered on the ground, which is what
#'     Natural Earth (and therefore this package's geometry) uses.
#'   * `"de_jure"` -- boundaries as claimed. The package does **not** ship de
#'     jure geometry; selecting this records the intent and warns that the
#'     shapes drawn are still de facto.
#'   * `"neutral"` -- disputed areas marked as disputed rather than assigned.
#'
#'   Called with no argument, returns the current policy.
#' @param worldview Optional point of view to draw: the viewing country's ISO
#'   alpha-3 code (`"IND"`) or `"ISO"`, one of Natural Earth's 31 published
#'   worldviews (see [world_geometry()]). Once set, geometry attached on the
#'   `sf` backend draws that country's boundaries, and the provenance records
#'   it. `NA` clears it.
#'
#' @return When called with no argument, the policy currently in effect. When
#'   setting, the policy that was in effect *before* the call, invisibly -- R's
#'   convention for a setter, so
#'   `on.exit(dispute_policy(dispute_policy("neutral")))` restores it.
#'
#' @section What this does and does not do:
#' On its own it records a choice and makes it visible. It does not redraw any
#' boundary, and selecting `"de_jure"` gives no claimed-boundary geometry, so
#' it warns. With a `worldview` it does change the shapes: the `sf` backend
#' draws that country's published view. The package ships no worldview of its
#' own beyond Natural Earth's default, and anyone publishing under an
#' institutional convention should still verify the shapes against that
#' institution's own basemap rather than trusting a setting.
#'
#' @seealso [disputed_territories], [check_dispute_coverage()], [world_map()]
#' @export
#' @examples
#' old <- dispute_policy("neutral")   # sets, and returns what it replaced
#' dispute_policy()                   # "neutral"
#' dispute_policy(old)                # put it back
dispute_policy <- function(policy = NULL, worldview = NULL) {
  valid <- c("none", "de_facto", "de_jure", "neutral")
  if (!is.null(worldview)) {
    if (length(worldview) == 1L && is.na(worldview)) {
      options(countryatlas.worldview = NULL)
    } else {
      options(countryatlas.worldview = check_worldview(worldview))
    }
  }
  if (is.null(policy)) {
    if (!is.null(worldview)) return(invisible(getOption("countryatlas.dispute_policy", "none")))
    # Validate on *read*, not only on write. Setting the option directly is
    # documented as discouraged but perfectly possible, and every other option
    # the package reads is checked when it is read. It matters more here than
    # elsewhere: this option's whole job is to state a convention truthfully on
    # a published map, and an unchecked typo printed "Convention: nonsense".
    got <- getOption("countryatlas.dispute_policy", "none")
    if (length(got) != 1L || !is.character(got) || !got %in% valid) {
      wdj_warn(c(
        "{.code countryatlas.dispute_policy} is set to an unrecognised value;
         using {.val none}.",
        "x" = "Got {.val {got}}.",
        "i" = "Valid values are {.val {valid}}. Set it with
               {.fn dispute_policy} rather than {.fn options}."
      ), .frequency = "once", .frequency_id = "dispute-policy-invalid")
      return("none")
    }
    return(got)
  }
  policy <- rlang::arg_match(policy, valid)
  if (identical(policy, "de_jure") && is.null(getOption("countryatlas.worldview"))) {
    wdj_warn(c(
      "The geometry is still de facto.",
      "!" = "{.pkg countryatlas} ships Natural Earth's administered boundaries
             and no claimed-boundary layer, so this records your intent but does
             not change a single shape.",
      "i" = "Pass {.arg worldview} to draw a country's published boundaries,
             and verify against your institution's own basemap before
             publishing."
    ))
  }
  # The PREVIOUS policy, not the new one. R's convention for a setter is to
  # hand back what it replaced -- options(), par(), sf::sf_use_s2() all do --
  # which is what makes the one-liner
  # `on.exit(dispute_policy(dispute_policy("neutral")))` work. Returning the
  # new value made that a no-op, and the example below had to take a separate
  # reading first to work around it.
  old <- getOption("countryatlas.dispute_policy", "none")
  options(countryatlas.dispute_policy = policy)
  invisible(old)
}

#' Which disputed territories does your data touch?
#'
#' Cross-references your data against [disputed_territories] so a contested area
#' does not pass unremarked. Reports both directions: the disputed territories
#' your data covers, and those it is silent about.
#'
#' @param data A frame with `iso3c`, or a character vector of codes.
#' @param quiet Suppress the console summary.
#'
#' @return A tibble of every disputed territory the package knows about, with
#'   `in_data` saying whether your data covers it. The scope caveat in
#'   [disputed_territories] applies: this is a documented subset, not every
#'   dispute in the world.
#'
#' @seealso [disputed_territories], [dispute_policy()], [audit_coverage()]
#' @export
#' @examples
#' check_dispute_coverage(countryatlas::world_snapshot$countries)
check_dispute_coverage <- function(data, quiet = FALSE) {
  check_bool(quiet, "quiet")
  iso <- if (is.character(data)) {
    # Missing and repeated values out first, as the data-frame branch below
    # does: a vector with an NA reported "NA" among the values that are "not
    # an ISO code", and a repeated bad value was listed, and counted, twice.
    unique(stats::na.omit(data))
  } else if (is.data.frame(data)) {
    if (!"iso3c" %in% names(data)) {
      wdj_abort("{.arg data} must contain an {.field iso3c} column.")
    }
    unique(stats::na.omit(sf_drop(data)$iso3c))
  } else {
    wdj_abort("{.arg data} must be a data frame with {.field iso3c}, or a character vector.")
  }
  # Through wdj_to_iso3c(), which uppercases and strips Unicode whitespace, so a
  # lowercase or padded code matches. Taken verbatim, check_dispute_coverage(
  # c("esh","xkx","pse")) reported "0 tracked disputed territories appear in
  # the data" -- a key problem presented as a coverage finding, which is the
  # failure the five verbs beside it were fixed for.
  iso_raw <- iso
  iso <- suppressWarnings(wdj_to_iso3c(iso, origin = "iso3c"))
  iso <- unique(stats::na.omit(iso))
  dt <- countryatlas::disputed_territories
  out <- dt
  out$in_data <- !is.na(dt$iso3c) & dt$iso3c %in% iso
  # Only when the keys themselves failed to resolve. Zero matches is the normal
  # answer here -- most countries have no disputed territory -- so warning on
  # `!any(in_data)` alone turned every ordinary call into a false alarm. What is
  # worth reporting is a key that resolved to nothing, which is what made
  # lowercase input read as a coverage finding rather than a key problem.
  unresolved <- iso_raw[is.na(suppressWarnings(
    wdj_to_iso3c(iso_raw, origin = "iso3c")))]
  if (length(unresolved)) {
    wdj_warn(c(
      "{length(unresolved)} value{?s} in {.arg data} {?is/are} not an ISO
       3166-1 alpha-3 code and {?was/were} ignored:",
      "*" = "{.val {utils::head(unresolved, 6)}}",
      "i" = "{.fn standardize_country} normalises names and case."
    ), class = "countryatlas_unresolved_keys")
  }
  if (!quiet) {
    n_cov <- sum(out$in_data)
    n_uncodeable <- sum(is.na(dt$iso3c))
    wdj_inform(c(
      # Agreements sit against their own count: "1 have no ISO code" and
      # "1 ... territories appear" are both wrong, and both are reachable --
      # the bundled table has 22 rows, of which a caller's data may cover one.
      "i" = "{n_cov} tracked disputed territor{?y/ies} {?appears/appear} in the
             data, of {nrow(dt)} tracked.",
      "*" = "{n_uncodeable} {?has/have} no ISO code at all and cannot appear in
             any iso3c-keyed dataset.",
      " " = "Set a convention with {.fn dispute_policy} so the map says which
             one it used."
    ))
  }
  out
}

# The layer world_map(disputes = "mark") adds: an outline over the disputed
# territories that are actually present, so a reader can see which shapes are
# contested without the package deciding anything about them.
dispute_layer <- function(data, sf_mode) {
  dt <- countryatlas::disputed_territories
  codes <- stats::na.omit(dt$iso3c)
  if (!"iso3c" %in% names(data)) return(NULL)
  hit <- data[data$iso3c %in% codes, , drop = FALSE]
  if (!nrow(hit)) return(NULL)
  if (sf_mode) {
    ggplot2::geom_sf(data = hit, fill = NA, colour = "#B2182B",
                     linewidth = 0.45, linetype = "21", inherit.aes = FALSE)
  } else {
    ggplot2::geom_polygon(
      data = hit,
      mapping = ggplot2::aes(x = .data$long, y = .data$lat, group = .data$group),
      fill = NA, colour = "#B2182B", linewidth = 0.45, linetype = "21",
      inherit.aes = FALSE
    )
  }
}

# The caption fragment describing the dispute treatment, appended to whatever
# footnote the caller asked for.
dispute_note <- function(disputes, data) {
  if (identical(disputes, "ignore")) return(NULL)
  dt <- countryatlas::disputed_territories
  n_marked <- if ("iso3c" %in% names(data)) {
    length(intersect(unique(data$iso3c), stats::na.omit(dt$iso3c)))
  } else 0L
  pol <- dispute_policy()
  paste0(
    "Disputed territories: ", n_marked, " marked, ",
    sum(is.na(dt$iso3c)), " untracked (no ISO code). Convention: ", pol, "."
  )
}
