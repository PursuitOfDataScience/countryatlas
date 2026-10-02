# Build country_lifespans: when each country was an independent state.
#
# audit_time_coverage() knew the dissolutions in historical_codes and assumed
# every other country "existed throughout", so a panel with Namibia in 1985 or
# Timor-Leste in 1995 came back clean. This table dates independence for every
# state in the international system since 1816.
#
# Source: Gleditsch & Ward's list of independent states (Gleditsch, K. S. &
# Ward, M. D. 1999, "A revised list of independent states since the congress
# of Vienna", International Interactions 25(4), 393-413), as distributed in the
# `states` package (Beger 2026; MIT licence). The dates are facts and are cited.
# GW codes are mapped to ISO 3166-1 alpha-3 through countrycode, plus the
# crosswalk below for the codes countrycode does not carry (the microstates,
# and modern Germany, Yemen, Vietnam and Kosovo). A territory with no GW entry
# is "assumed" to have existed throughout, as before.
#
# Run from the package root:  Rscript data-raw/country_lifespans.R

suppressPackageStartupMessages(library(dplyr))

gw <- states::gwstates
gw_extra <- c(`255` = "DEU", `678` = "YEM", `816` = "VNM", `347` = "XKX",
              # Yugoslavia continues as Serbia in the GW list.
              `345` = "SRB",
              `54` = "DMA", `55` = "GRD", `56` = "LCA", `57` = "VCT", `58` = "ATG",
              `60` = "KNA", `221` = "MCO", `223` = "LIE", `331` = "SMR",
              `232` = "AND", `403` = "STP", `591` = "SYC", `935` = "VUT",
              `970` = "KIR", `971` = "NRU", `972` = "TON", `973` = "TUV",
              `983` = "MHL", `986` = "PLW", `987` = "FSM", `990` = "WSM")
gw$iso3c <- suppressWarnings(countrycode::countrycode(gw$gwcode, "gwn", "iso3c",
                                                      warn = FALSE))
fill <- is.na(gw$iso3c) & as.character(gw$gwcode) %in% names(gw_extra)
gw$iso3c[fill] <- unname(gw_extra[as.character(gw$gwcode[fill])])
gw <- gw[!is.na(gw$iso3c), , drop = FALSE]

# The system's first day is not an independence date: 1816-01-01 means "an
# independent state when the list begins", so leave it open.
gw$from <- as.Date(gw$start)
gw$from[gw$from <= as.Date("1816-01-01")] <- NA
gw$to <- as.Date(gw$end)
gw$to[gw$to >= as.Date("9999-01-01")] <- NA

# One row per spell, adjacent or overlapping spells merged (modern Germany is
# GW 260 to 1990 and 255 after it, with no gap).
spells <- gw |>
  arrange(iso3c, !is.na(from), from) |>
  group_by(iso3c) |>
  group_modify(function(d, k) {
    out <- d[1, c("from", "to")]
    for (i in seq_len(nrow(d))[-1]) {
      last <- nrow(out)
      prev_to <- out$to[last]
      if (is.na(prev_to) || (!is.na(d$from[i]) && d$from[i] <= prev_to + 1)) {
        out$to[last] <- if (is.na(prev_to) || is.na(d$to[i])) as.Date(NA) else
          max(prev_to, d$to[i])
      } else {
        out <- rbind(out, d[i, c("from", "to")])
      }
    }
    out
  }) |>
  ungroup() |>
  mutate(basis = "gleditsch_ward")

meta <- countryatlas::country_meta$iso3c
assumed <- tibble(iso3c = setdiff(meta, spells$iso3c), from = as.Date(NA),
                  to = as.Date(NA), basis = "assumed")
country_lifespans <- bind_rows(spells, assumed) |> arrange(iso3c, from)

# The cases the plan names, and the gap that makes spells necessary.
yr <- function(x) as.integer(format(x, "%Y"))
first_from <- function(cc) yr(min(country_lifespans$from[country_lifespans$iso3c == cc]))
stopifnot(first_from("NAM") == 1990L, first_from("ERI") == 1993L,
          first_from("TLS") == 2002L, first_from("SSD") == 2011L,
          sum(country_lifespans$iso3c == "EST") == 2L,
          is.na(country_lifespans$from[country_lifespans$iso3c == "FRA"]),
          !anyNA(country_lifespans$basis))

# Internal data, alongside the bundled polygons.
sys <- new.env()
if (file.exists("R/sysdata.rda")) load("R/sysdata.rda", envir = sys)
assign("country_lifespans", country_lifespans, envir = sys)
save(list = ls(sys), envir = sys, file = "R/sysdata.rda", compress = "xz")
cat("country_lifespans:", nrow(country_lifespans), "rows,",
    sum(country_lifespans$basis == "gleditsch_ward"), "GW spells for",
    length(unique(spells$iso3c)), "countries\n")
