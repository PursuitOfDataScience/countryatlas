# Build country_groups_history --------------------------------------------------
#
# country_groups_tbl is a single snapshot, which makes any panel join on group
# membership wrong: an EU panel spanning 2015-2020 either includes the UK
# throughout or excludes it throughout, and neither is true. This table adds
# the dates.
#
# SCOPE, stated plainly because it matters more than the row count: this covers
# the groups whose accession, departure and suspension dates are documented,
# unambiguous and stable, and every date below carries its source. The rule
# stands: a fabricated date is worse than an absent one, so a group is dated
# only where every date is sourced. Not dated, and why:
#   * Commonwealth, OPEC, the African Union, ECOWAS, CARICOM and the Pacific
#     Islands Forum: long histories of suspensions, lapses and readmissions
#     whose dates the sources give unevenly (often to the year, or not at all
#     for the end of a suspension). country_groups(as_of =) falls back to the
#     snapshot for those, with a warning, rather than pretending.
#   * G20: its members are countries plus the EU and the AU, which are not; the
#     table holds countries only, and the 1999 founding has no single
#     accession date.
#
# A row is a spell: `from` is the date it took effect; `to` is the first date
# on which it no longer held (it runs up to the day before), or NA for one
# still in force. `status` is "member" or "suspended"; a country can have
# several spells in a group (Seychelles left SADC in 2004 and rejoined in
# 2008; Syria was suspended from the Arab League from 2011 to 2023).
# country_groups() and in_group() count the "member" spells. Dates are the
# treaty, accession or decision date where one exists; where a source gives
# only the month, the 1st of that month (APEC's accessions, at the November
# ministerial meeting of each year).

library(tibble)
library(dplyr)

m <- function(group, iso3c, from, to = NA_character_, status = "member") {
  tibble(group = group, iso3c = iso3c,
         from = as.Date(from), to = as.Date(to), status = status)
}

eu <- bind_rows(
  m("EU", c("BEL", "FRA", "DEU", "ITA", "LUX", "NLD"), "1958-01-01"),
  m("EU", c("DNK", "IRL"), "1973-01-01"),
  # Brexit: the UK left at 23:00 GMT on 31 January 2020, so 1 February is the
  # first day it was not a member. This was 2020-01-31, the last day it *was*
  # one, which, read as the exclusive end every other row uses, dropped the
  # UK from the EU a day early.
  m("EU", "GBR", "1973-01-01", "2020-02-01"),
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

# Shanghai Cooperation Organisation.
# Source: https://en.wikipedia.org/wiki/Shanghai_Cooperation_Organisation
# (membership table: founding 15 June 2001; India and Pakistan 9 June 2017;
# Iran 4 July 2023; Belarus 4 July 2024).
sco <- bind_rows(
  m("SCO", c("CHN", "KAZ", "KGZ", "RUS", "TJK", "UZB"), "2001-06-15"),
  m("SCO", c("IND", "PAK"), "2017-06-09"),
  m("SCO", "IRN", "2023-07-04"),
  m("SCO", "BLR", "2024-07-04")
)

# CPTPP: the date the agreement entered into force for each party.
# Source: https://en.wikipedia.org/wiki/Comprehensive_and_Progressive_Agreement_for_Trans-Pacific_Partnership
# (entry into force table; the United Kingdom 15 December 2024).
cptpp <- bind_rows(
  m("CPTPP", c("AUS", "CAN", "JPN", "MEX", "NZL", "SGP"), "2018-12-30"),
  m("CPTPP", "VNM", "2019-01-14"),
  m("CPTPP", "PER", "2021-09-19"),
  m("CPTPP", "MYS", "2022-11-29"),
  m("CPTPP", "CHL", "2023-02-21"),
  m("CPTPP", "BRN", "2023-07-12"),
  m("CPTPP", "GBR", "2024-12-15")
)

# RCEP: entry into force for each party. Myanmar ratified in 2021, but the
# ASEAN Secretariat questioned the ratification's legitimacy and the date it
# took effect is disputed, so it is not listed.
# Source: https://en.wikipedia.org/wiki/Regional_Comprehensive_Economic_Partnership
rcep <- bind_rows(
  m("RCEP", c("AUS", "BRN", "KHM", "CHN", "JPN", "LAO", "NZL", "SGP", "THA",
              "VNM"), "2022-01-01"),
  m("RCEP", "KOR", "2022-02-01"),
  m("RCEP", "MYS", "2022-03-18"),
  m("RCEP", "IDN", "2023-01-02"),
  m("RCEP", "PHL", "2023-06-02")
)

# East African Community, re-established by the treaty in force 7 July 2000.
# Sources: https://www.eac.int/eac-history (Rwanda and Burundi full members
# 1 July 2007; South Sudan 5 September 2016; DR Congo 11 July 2022);
# https://www.eac.int/press-releases/3049-somalia-finally-joins-eac-as-the-bloc-s-8th-partner-state
# (Somalia deposited its instrument of ratification on 4 March 2024).
eac <- bind_rows(
  m("EAC", c("KEN", "TZA", "UGA"), "2000-07-07"),
  m("EAC", c("RWA", "BDI"), "2007-07-01"),
  m("EAC", "SSD", "2016-09-05"),
  m("EAC", "COD", "2022-07-11"),
  m("EAC", "SOM", "2024-03-04")
)

# Southern African Development Community, established 17 August 1992 by the
# nine SADCC members and Namibia.
# Sources: https://en.wikipedia.org/wiki/Southern_African_Development_Community
# (member table: South Africa 30 August 1994, Mauritius 28 August 1995, DR
# Congo and Seychelles 8 September 1997, Seychelles until 1 July 2004,
# Madagascar 18 August 2005 and reinstated 30 January 2014);
# https://www.sadc.int/latest-news/union-comoros-becomes-16th-sadc-member-state
# (Comoros admitted at the summit of 20 August 2017);
# https://www.sadc.int/member-states/seychelles (rejoined 17 August 2008);
# https://www.sanews.gov.za/south-africa/sadc-leaders-suspend-madagascar
# (Madagascar suspended at the summit of 30 March 2009).
sadc <- bind_rows(
  m("SADC", c("AGO", "BWA", "LSO", "MWI", "MOZ", "NAM", "SWZ", "TZA", "ZMB",
              "ZWE"), "1992-08-17"),
  m("SADC", "ZAF", "1994-08-30"),
  m("SADC", "MUS", "1995-08-28"),
  m("SADC", "COD", "1997-09-08"),
  m("SADC", "SYC", "1997-09-08", "2004-07-01"),
  m("SADC", "SYC", "2008-08-17"),
  m("SADC", "MDG", "2005-08-18", "2009-03-30"),
  m("SADC", "MDG", "2009-03-30", "2014-01-30", status = "suspended"),
  m("SADC", "MDG", "2014-01-30"),
  m("SADC", "COM", "2017-08-20")
)

# Asia-Pacific Economic Cooperation: member *economies*, including Hong Kong
# and Taiwan (Chinese Taipei). Each joined at the November ministerial meeting
# of its year, and the sources give the month only, so the 1st of November.
# Source: https://en.wikipedia.org/wiki/Asia-Pacific_Economic_Cooperation
# (member economies table).
apec <- bind_rows(
  m("APEC", c("AUS", "BRN", "CAN", "IDN", "JPN", "KOR", "MYS", "NZL", "PHL",
              "SGP", "THA", "USA"), "1989-11-01"),
  m("APEC", c("CHN", "HKG", "TWN"), "1991-11-01"),
  m("APEC", c("MEX", "PNG"), "1993-11-01"),
  m("APEC", "CHL", "1994-11-01"),
  m("APEC", c("PER", "RUS", "VNM"), "1998-11-01")
)

# League of Arab States. Yemen is dated from North Yemen's founding membership,
# which the unified republic continued in 1990.
# Sources: https://en.wikipedia.org/wiki/Member_states_of_the_Arab_League
# (admission dates; Libya suspended 22 February to 27 August 2011; Syria
# suspended 16 November 2011, readmitted 7 May 2023);
# https://unispal.un.org/pdfs/a34160s13243.pdf (the Baghdad resolutions of
# 31 March 1979 suspending Egypt's membership);
# https://www.washingtonpost.com/archive/politics/1989/05/23/egypt-returns-to-fold-as-arabs-open-summit/ad5d0a7c-2c93-49d7-be06-c05db82f6a22/
# (Egypt readmitted at the Casablanca summit, 23 May 1989).
arab <- bind_rows(
  m("ArabLeague", c("IRQ", "JOR", "LBN", "SAU", "YEM"), "1945-03-22"),
  m("ArabLeague", "EGY", "1945-03-22", "1979-03-31"),
  m("ArabLeague", "EGY", "1979-03-31", "1989-05-23", status = "suspended"),
  m("ArabLeague", "EGY", "1989-05-23"),
  m("ArabLeague", "SYR", "1945-03-22", "2011-11-16"),
  m("ArabLeague", "SYR", "2011-11-16", "2023-05-07", status = "suspended"),
  m("ArabLeague", "SYR", "2023-05-07"),
  m("ArabLeague", "LBY", "1953-03-28", "2011-02-22"),
  m("ArabLeague", "LBY", "2011-02-22", "2011-08-27", status = "suspended"),
  m("ArabLeague", "LBY", "2011-08-27"),
  m("ArabLeague", "SDN", "1956-01-19"),
  m("ArabLeague", c("MAR", "TUN"), "1958-10-01"),
  m("ArabLeague", "KWT", "1961-07-20"),
  m("ArabLeague", "DZA", "1962-08-16"),
  m("ArabLeague", c("BHR", "QAT"), "1971-09-11"),
  m("ArabLeague", "OMN", "1971-09-29"),
  m("ArabLeague", "ARE", "1971-12-06"),
  m("ArabLeague", "MRT", "1973-11-26"),
  m("ArabLeague", "SOM", "1974-02-14"),
  m("ArabLeague", "PSE", "1976-09-09"),
  m("ArabLeague", "DJI", "1977-09-04"),
  m("ArabLeague", "COM", "1993-11-20")
)

country_groups_history <- bind_rows(
  eu, eurozone, nato, oecd, asean, efta, gcc, mercosur, nordic, visegrad,
  brics, g7, sco, cptpp, rcep, eac, sadc, apec, arab
) |>
  arrange(group, from, iso3c) |>
  mutate(country = countrycode::countrycode(iso3c, "iso3c", "country.name",
                                            warn = FALSE),
         .after = iso3c)

# No country may have overlapping spells in a group: each spell ends on or
# before the next one begins.
overlaps <- country_groups_history |>
  arrange(group, iso3c, from) |>
  group_by(group, iso3c) |>
  filter(!is.na(lag(to)) & from < lag(to) | is.na(lag(to)) & row_number() > 1) |>
  ungroup()
stopifnot(
  !anyNA(country_groups_history$iso3c),
  !anyNA(country_groups_history$from),
  country_groups_history$status %in% c("member", "suspended"),
  nrow(overlaps) == 0L,
  all(is.na(country_groups_history$to) |
        country_groups_history$to > country_groups_history$from)
)

# Cross-check against country_groups_tbl: the members current *today* must equal
# the snapshot for every group covered here. Note the snapshot is documented as
# 2024-01-01 but in fact carries accessions later than that (Sweden to NATO in
# March 2024, Bolivia to Mercosur in July 2024, Indonesia to BRICS in January
# 2025) -- which is exactly the kind of drift a dated table exists to expose.
#
# This is a *validation*, which is what ?country_groups_history promises: "The
# table is validated at build time against country_groups_tbl". It used to
# message() and then write the .rda anyway, so a mismatch scrolled past in a
# build log and shipped -- and NEWS records that this drift has already bitten
# once. Every other invariant in this file is a hard stopifnot(); so is this
# one now. Mismatches are accumulated first, so one run reports all of them
# rather than stopping at the alphabetically first group.
today <- Sys.Date()
current <- country_groups_history |>
  filter(from <= today, is.na(to) | to > today, status == "member")
# Read the snapshot from the WORKING TREE, not from the installed package.
# This is a validation, and validating against `countryatlas::` compares the
# new history table to whatever snapshot happens to be installed -- which is
# the *previous* release's whenever country_groups_tbl has just been rebuilt
# with a new MEMBERSHIP_AS_OF. The check would then pass or fail on the wrong
# comparison, and it is a hard stop() now. It also drops this script's need
# for an installed countryatlas, matching overrides_snapshot.R's purpose.
snap_env <- new.env()
load("data/country_groups_tbl.rda", envir = snap_env)
groups_tbl <- snap_env$country_groups_tbl
mismatches <- character(0)
for (g in unique(country_groups_history$group)) {
  a <- sort(current$iso3c[current$group == g])
  b <- sort(groups_tbl$iso3c[groups_tbl$group == g])
  if (!identical(a, b)) {
    mismatches <- c(mismatches, paste0(
      "  ", g, ": history-only [", paste(setdiff(a, b), collapse = ", "),
      "], snapshot-only [", paste(setdiff(b, a), collapse = ", "), "]"))
  }
}
if (length(mismatches)) {
  stop("country_groups_history disagrees with country_groups_tbl for ",
       length(mismatches), " group(s):\n", paste(mismatches, collapse = "\n"),
       "\nFix whichever table is wrong -- do not ship the mismatch. ",
       "If country_groups_tbl is the stale one, rebuild it from ",
       "data-raw/build_datasets.R and bump MEMBERSHIP_AS_OF.",
       call. = FALSE)
}

usethis::use_data(country_groups_history, overwrite = TRUE)
