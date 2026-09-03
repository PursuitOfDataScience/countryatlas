# Build country_groups_history --------------------------------------------------
#
# country_groups_tbl is a single 2024-01-01 snapshot, which makes any panel join
# on group membership wrong: an EU panel spanning 2015-2020 either includes the
# UK throughout or excludes it throughout, and neither is true. This table adds
# the dates.
#
# SCOPE, stated plainly because it matters more than the row count: this covers
# the twelve groups whose accession and departure dates are documented,
# unambiguous and stable. Commonwealth, G20 and OPEC are deliberately absent --
# their membership histories involve suspensions, readmissions and contested
# dates that would need sourcing case by case, and inventing a date is worse
# than admitting there isn't one. country_groups(as_of =) falls back to the
# snapshot for those, with a warning, rather than pretending.
#
# `from` is the date membership took effect; `to` is the date it ended, or NA
# for a current member. Dates are the treaty/accession date where one exists,
# otherwise 1 January of the accession year.

library(tibble)
library(dplyr)

m <- function(group, iso3c, from, to = NA_character_) {
  tibble(group = group, iso3c = iso3c,
         from = as.Date(from), to = as.Date(to))
}

eu <- bind_rows(
  m("EU", c("BEL", "FRA", "DEU", "ITA", "LUX", "NLD"), "1958-01-01"),
  m("EU", c("DNK", "IRL"), "1973-01-01"),
  m("EU", "GBR", "1973-01-01", "2020-01-31"),          # Brexit
  m("EU", "GRC", "1981-01-01"),
  m("EU", c("ESP", "PRT"), "1986-01-01"),
  m("EU", c("AUT", "FIN", "SWE"), "1995-01-01"),
  m("EU", c("CYP", "CZE", "EST", "HUN", "LVA", "LTU", "MLT", "POL", "SVK",
            "SVN"), "2004-05-01"),
  m("EU", c("BGR", "ROU"), "2007-01-01"),
  m("EU", "HRV", "2013-07-01")
)

eurozone <- bind_rows(
  m("EuroZone", c("AUT", "BEL", "FIN", "FRA", "DEU", "IRL", "ITA", "LUX",
                  "NLD", "PRT", "ESP"), "1999-01-01"),
  m("EuroZone", "GRC", "2001-01-01"),
  m("EuroZone", "SVN", "2007-01-01"),
  m("EuroZone", c("CYP", "MLT"), "2008-01-01"),
  m("EuroZone", "SVK", "2009-01-01"),
  m("EuroZone", "EST", "2011-01-01"),
  m("EuroZone", "LVA", "2014-01-01"),
  m("EuroZone", "LTU", "2015-01-01"),
  m("EuroZone", "HRV", "2023-01-01")
)

nato <- bind_rows(
  m("NATO", c("BEL", "CAN", "DNK", "FRA", "ISL", "ITA", "LUX", "NLD", "NOR",
              "PRT", "GBR", "USA"), "1949-04-04"),
  m("NATO", c("GRC", "TUR"), "1952-02-18"),
  m("NATO", "DEU", "1955-05-09"),
  m("NATO", "ESP", "1982-05-30"),
  m("NATO", c("CZE", "HUN", "POL"), "1999-03-12"),
  m("NATO", c("BGR", "EST", "LVA", "LTU", "ROU", "SVK", "SVN"), "2004-03-29"),
  m("NATO", c("ALB", "HRV"), "2009-04-01"),
  m("NATO", "MNE", "2017-06-05"),
  m("NATO", "MKD", "2020-03-27"),
  m("NATO", "FIN", "2023-04-04"),
  m("NATO", "SWE", "2024-03-07")
)

oecd <- bind_rows(
  m("OECD", c("AUT", "BEL", "CAN", "DNK", "FRA", "DEU", "GRC", "ISL", "IRL",
              "ITA", "LUX", "NLD", "NOR", "PRT", "ESP", "SWE", "CHE", "TUR",
              "GBR", "USA"), "1961-09-30"),
  m("OECD", "JPN", "1964-04-28"),
  m("OECD", "FIN", "1969-01-28"),
  m("OECD", "AUS", "1971-06-07"),
  m("OECD", "NZL", "1973-05-29"),
  m("OECD", "MEX", "1994-05-18"),
  m("OECD", "CZE", "1995-12-21"),
  m("OECD", "HUN", "1996-05-07"),
  m("OECD", "POL", "1996-11-22"),
  m("OECD", "KOR", "1996-12-12"),
  m("OECD", "SVK", "2000-12-14"),
  m("OECD", c("CHL", "SVN", "ISR", "EST"), "2010-01-01"),
  m("OECD", "LVA", "2016-07-01"),
  m("OECD", "LTU", "2018-07-05"),
  m("OECD", "COL", "2020-04-28"),
  m("OECD", "CRI", "2021-05-25")
)

asean <- bind_rows(
  m("ASEAN", c("IDN", "MYS", "PHL", "SGP", "THA"), "1967-08-08"),
  m("ASEAN", "BRN", "1984-01-07"),
  m("ASEAN", "VNM", "1995-07-28"),
  m("ASEAN", c("LAO", "MMR"), "1997-07-23"),
  m("ASEAN", "KHM", "1999-04-30")
)

# EFTA is the instructive one: most of its founders left, for the EU.
efta <- bind_rows(
  m("EFTA", c("NOR", "CHE"), "1960-05-03"),
  m("EFTA", c("AUT", "SWE"), "1960-05-03", "1995-01-01"),
  m("EFTA", "DNK", "1960-05-03", "1973-01-01"),
  m("EFTA", "GBR", "1960-05-03", "1973-01-01"),
  m("EFTA", "PRT", "1960-05-03", "1986-01-01"),
  m("EFTA", "FIN", "1961-06-27", "1995-01-01"),
  m("EFTA", "ISL", "1970-03-01"),
  m("EFTA", "LIE", "1991-09-01")
)

gcc <- m("GCC", c("BHR", "KWT", "OMN", "QAT", "SAU", "ARE"), "1981-05-25")

mercosur <- bind_rows(
  m("Mercosur", c("ARG", "BRA", "PRY", "URY"), "1991-03-26"),
  m("Mercosur", "VEN", "2012-07-31", "2016-12-01"),   # suspended indefinitely
  m("Mercosur", "BOL", "2024-07-08")
)

nordic <- bind_rows(
  m("Nordic", c("DNK", "ISL", "NOR", "SWE"), "1952-03-16"),
  m("Nordic", "FIN", "1955-10-28")
)

# The Visegrad Group was founded by Czechoslovakia, Hungary and Poland; CZE and
# SVK inherit the membership at the dissolution, which is why their `from` is
# 1993 and not 1991.
visegrad <- bind_rows(
  m("Visegrad", c("HUN", "POL"), "1991-02-15"),
  m("Visegrad", c("CZE", "SVK"), "1993-01-01")
)

brics <- bind_rows(
  m("BRICS", c("BRA", "RUS", "IND", "CHN"), "2009-06-16"),
  m("BRICS", "ZAF", "2010-12-24"),
  m("BRICS", c("EGY", "ETH", "IRN", "ARE"), "2024-01-01"),
  m("BRICS", "IDN", "2025-01-06")
)

g7 <- bind_rows(
  m("G7", c("FRA", "DEU", "ITA", "JPN", "GBR", "USA"), "1975-11-15"),
  m("G7", "CAN", "1976-06-27")
)

country_groups_history <- bind_rows(
  eu, eurozone, nato, oecd, asean, efta, gcc, mercosur, nordic, visegrad,
  brics, g7
) |>
  arrange(group, from, iso3c) |>
  mutate(country = countrycode::countrycode(iso3c, "iso3c", "country.name",
                                            warn = FALSE),
         .after = iso3c)

stopifnot(
  !anyNA(country_groups_history$iso3c),
  !anyNA(country_groups_history$from),
  # No country may appear twice in a group with overlapping spans.
  !any(duplicated(country_groups_history[, c("group", "iso3c")])),
  all(is.na(country_groups_history$to) |
        country_groups_history$to > country_groups_history$from)
)

# Cross-check against country_groups_tbl: the members current *today* must equal
# the snapshot for every group covered here. Note the snapshot is documented as
# 2024-01-01 but in fact carries accessions later than that (Sweden to NATO in
# March 2024, Bolivia to Mercosur in July 2024, Indonesia to BRICS in January
# 2025) -- which is exactly the kind of drift a dated table exists to expose.
today <- Sys.Date()
current <- country_groups_history |>
  filter(from <= today, is.na(to) | to > today)
for (g in unique(country_groups_history$group)) {
  a <- sort(current$iso3c[current$group == g])
  b <- sort(countryatlas::country_groups_tbl$iso3c[
    countryatlas::country_groups_tbl$group == g])
  if (!identical(a, b)) {
    message("MISMATCH in ", g, ":\n  history-only: ",
            paste(setdiff(a, b), collapse = ", "),
            "\n  snapshot-only: ", paste(setdiff(b, a), collapse = ", "))
  }
}

usethis::use_data(country_groups_history, overwrite = TRUE)
