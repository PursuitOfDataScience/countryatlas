# Run a heavy test everywhere except on CRAN.
#
# CRAN rejected the first 3.0.0 upload for its check time: 12 minutes on the
# Windows incoming check against a 10-minute limit, 503s of it the test suite.
# The tests marked with this each took 0.75s or more (cartograms, sweeps over
# every map verb or projection, full-world renders), and together they were
# about three quarters of the suite's time. They still run under
# devtools::test() and on every CI leg, both of which set NOT_CRAN=true, so
# none of them goes unrun; CRAN runs the rest. Mark a test for what it costs,
# measured, not for what it covers.
skip_slow_on_cran <- function() testthat::skip_on_cran()
