# Build disputed_territories ------------------------------------------------------
#
# SCOPE AND STANCE, because both matter more than the row count.
#
# This table records *that* a territory is disputed and *who the parties are*.
# It does not adjudicate, rank claims, or imply that any claim is better founded
# than another. Where it uses the phrase "administered by" it means de facto
# control as reported by the mapping sources the package already depends on
# (Natural Earth), not recognition, legitimacy or endorsement. Every row is a
# case where the choice of map convention visibly changes the picture, which is
# the only reason the package needs to know about it at all.
#
# The scope is deliberately a documented subset rather than the ~188 disputed
# areas the EU data-visualisation guide counts. The selection criterion is
# narrow and stated: territories that (a) appear as a distinct unit or a
# contested boundary in Natural Earth at 1:110m or 1:50m, AND (b) have an ISO
# 3166-1 code, a widely-used user-assigned code, or a standard "disputed" label
# in at least one of ISO, the UN statistical division, or the World Bank. That
# criterion is mechanical, checkable, and does not require anyone to judge the
# merits.
#
# `status` values:
#   "un_member"       -- a UN member state whose territory is nonetheless
#                        contested in part
#   "un_observer"     -- UN non-member observer state
#   "partially_recognised" -- recognised by some UN members, not all
#   "administered"    -- administered by one party, claimed by another
#   "claimed"         -- claimed by more than one party, no settled control
#
# Sources for the *existence* of each dispute (not for its merits):
#   Natural Earth disputed-boundaries policy, https://www.naturalearthdata.com
#   UN M49 standard area codes, https://unstats.un.org/unsd/methodology/m49/
#   ISO 3166-1 and its user-assigned range

library(tibble)
library(dplyr)

d <- function(territory, iso3c, administered_by, claimed_by, status, note) {
  tibble(territory = territory, iso3c = iso3c,
         administered_by = administered_by, claimed_by = claimed_by,
         status = status, note = note)
}

disputed_territories <- bind_rows(
  d("Western Sahara", "ESH", "MAR", "MAR;SAH",
    "administered",
    "Non-self-governing territory on the UN list; largely administered by Morocco, claimed by the Sahrawi Arab Democratic Republic."),
  d("Kosovo", "XKX", "XKX", "XKX;SRB",
    "partially_recognised",
    "User-assigned code XKX, used by the World Bank and IMF. Recognised by many but not all UN members."),
  d("Palestine", "PSE", "PSE", "PSE;ISR",
    "un_observer",
    "UN non-member observer state; the West Bank and Gaza are treated differently by different mapping conventions."),
  d("Taiwan", "TWN", "TWN", "TWN;CHN",
    "partially_recognised",
    "ISO 3166-1 assigns TW; treated as a separate reporting economy by the World Bank and IMF."),
  d("Crimea", NA_character_, "RUS", "UKR;RUS",
    "administered",
    "Annexed by Russia in 2014; the UN General Assembly does not recognise the annexation. No ISO 3166-1 code."),
  d("Northern Cyprus", NA_character_, "CYP-N", "CYP;TUR",
    "partially_recognised",
    "Recognised only by Turkiye. Natural Earth carries the ceasefire line."),
  d("Abkhazia", NA_character_, "ABK", "GEO;ABK",
    "partially_recognised",
    "Recognised by a small number of UN members; claimed by Georgia."),
  d("South Ossetia", NA_character_, "OST", "GEO;OST",
    "partially_recognised",
    "Recognised by a small number of UN members; claimed by Georgia."),
  d("Jammu and Kashmir", NA_character_, NA_character_, "IND;PAK;CHN",
    "claimed",
    "Divided by the Line of Control and the Line of Actual Control; claimed in whole or part by three states."),
  d("Aksai Chin", NA_character_, "CHN", "IND;CHN",
    "administered",
    "Administered by China, claimed by India."),
  d("Arunachal Pradesh", NA_character_, "IND", "IND;CHN",
    "administered",
    "Administered by India, claimed by China as South Tibet."),
  d("Falkland Islands", "FLK", "GBR", "GBR;ARG",
    "administered",
    "British overseas territory; claimed by Argentina as the Islas Malvinas."),
  d("Gibraltar", "GIB", "GBR", "GBR;ESP",
    "administered",
    "British overseas territory; claimed by Spain."),
  d("Western New Guinea", NA_character_, "IDN", "IDN",
    "administered",
    "Administered by Indonesia; the 1969 Act of Free Choice is disputed by independence movements."),
  d("Spratly Islands", NA_character_, NA_character_, "CHN;TWN;VNM;PHL;MYS;BRN",
    "claimed",
    "Claimed in whole or part by six parties; no settled control."),
  d("Paracel Islands", NA_character_, "CHN", "CHN;VNM;TWN",
    "administered",
    "Administered by China; claimed by Vietnam and Taiwan."),
  d("Senkaku / Diaoyu Islands", NA_character_, "JPN", "JPN;CHN;TWN",
    "administered",
    "Administered by Japan; claimed by China and Taiwan."),
  d("Kuril Islands", NA_character_, "RUS", "RUS;JPN",
    "administered",
    "Administered by Russia; the southern islands are claimed by Japan as the Northern Territories."),
  d("Nagorno-Karabakh", NA_character_, "AZE", "AZE",
    "administered",
    "Control returned to Azerbaijan in 2023 following the dissolution of the self-declared republic."),
  d("Somaliland", NA_character_, "SOL", "SOM;SOL",
    "partially_recognised",
    "De facto independent since 1991; not recognised by any UN member. Claimed by Somalia."),
  d("Transnistria", NA_character_, "PMR", "MDA;PMR",
    "partially_recognised",
    "De facto separate administration; claimed by Moldova."),
  d("Antarctica", "ATA", NA_character_, NA_character_,
    "claimed",
    "Seven states maintain territorial claims, all held in abeyance by the Antarctic Treaty. Mapped as unclaimed by convention.")
)

stopifnot(
  !any(duplicated(disputed_territories$territory)),
  all(disputed_territories$status %in%
        c("un_member", "un_observer", "partially_recognised", "administered",
          "claimed")),
  !anyNA(disputed_territories$note),
  # Every ISO code present must be one the package recognises.
  all(is.na(disputed_territories$iso3c) |
        disputed_territories$iso3c %in% countryatlas:::wdj_known_iso3c())
)

usethis::use_data(disputed_territories, overwrite = TRUE)
