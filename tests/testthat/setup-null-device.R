# Keep the test run from writing a plot file into the source tree.
#
# Printing a plot with no device open makes R open the default one, which in a
# non-interactive session is `pdf()` writing `Rplots.pdf` into the working
# directory -- for testthat, `tests/testthat`. `.Rbuildignore` carries
# `^Rplots\.pdf$`, which is anchored at the package root and so does not match
# the nested copy: the 60 KB artifact was therefore included in the source
# tarball by `R CMD build`. (Both are handled now, the pattern as well as this,
# because the two protect different things -- the pattern keeps a stray file out
# of the tarball however it got there, and this keeps it from being written at
# all, including on a developer's working tree.)
#
# Set the *default device* rather than opening a null one here: nothing is left
# current, so a test that opens and closes its own device -- test-features-3.0.0.R
# does -- cannot close ours out from under the rest of the run. Every plot still
# renders, so a drawing error still surfaces as a failure; it just renders
# nowhere.
withr::local_options(
  device = function(...) grDevices::pdf(NULL),
  .local_envir = testthat::teardown_env()
)
