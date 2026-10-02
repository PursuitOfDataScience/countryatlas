# The CRAN versions of the packages countryatlas tracks most closely (T5), set
# against the versions last seen. WDI 2.8.0 and countrycode 1.9.0 reached CRAN
# in August 2026 while development still ran 2.7.10 and 1.8.0; a weekly line in
# the job summary notices the next one first. Update `seen` when a change has
# been checked.
seen <- c(ggsql = "0.3.3", WDI = "2.8.0", countrycode = "1.9.0",
          sf = "1.1-3", ggplot2 = "4.0.3", dplyr = "1.2.1")
ap <- utils::available.packages(repos = "https://cloud.r-project.org")
now <- ap[names(seen), "Version"]
changed <- now != seen
cat("## Upstream versions\n\n| package | last seen | CRAN now | |\n|:-|:-|:-|:-|\n")
cat(sprintf("| %s | %s | %s | %s |\n", names(seen), seen, now,
            ifelse(changed, "**changed**", "")), sep = "")
# ggsql's R binding at 0.4.1 or later is what lets world_query() run: the
# vignette chunks are eval = FALSE until then.
if (utils::compareVersion(now[["ggsql"]], "0.4.1") >= 0) {
  cat("\nggsql >= 0.4.1 is on CRAN: turn on the ggsql vignette chunks and",
      "re-verify the emitted grammar against the syntax reference.\n")
}
