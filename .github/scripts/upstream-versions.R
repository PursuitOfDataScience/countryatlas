# The CRAN versions of the packages countryatlas tracks most closely (T5), set
# against the versions last seen. WDI 2.8.0 and countrycode 1.9.0 reached CRAN
# in August 2026 while development still ran 2.7.10 and 1.8.0; a weekly line in
# the job summary notices the next one first. Update `seen` when a change has
# been checked.
seen <- c(ggsql = "0.5.2", WDI = "2.8.0", countrycode = "1.9.0",
          sf = "1.1-3", ggplot2 = "4.0.3", dplyr = "1.2.1")
ap <- utils::available.packages(repos = "https://cloud.r-project.org")
now <- ap[names(seen), "Version"]
changed <- now != seen
cat("## Upstream versions\n\n| package | last seen | CRAN now | |\n|:-|:-|:-|:-|\n")
cat(sprintf("| %s | %s | %s | %s |\n", names(seen), seen, now,
            ifelse(changed, "**changed**", "")), sep = "")
# world_query() writes ggsql 0.5's grammar, checked against 0.5.2 by
# tests/testthat/test-ggsql.R. A new ggsql release is the cue to run those
# tests (and the ggsql vignette, which renders on the website) against it.
if (utils::compareVersion(now[["ggsql"]], seen[["ggsql"]]) > 0) {
  cat("\nA newer ggsql is on CRAN: run tests/testthat/test-ggsql.R with",
      "NOT_CRAN=true against it before trusting world_query()'s grammar.\n")
}
