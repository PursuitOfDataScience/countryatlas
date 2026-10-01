# Run a test everywhere except on CRAN.
#
# CRAN rejected 3.0.0 twice for "Overall checktime 12 min > 10 min" on its
# Windows incoming check. The first time the suite took 503s there; the second,
# with the 125 slowest tests skipped, it still took 358s, because that machine
# ran the remaining tests 2.5 times slower than a Linux workstation does. Load
# on CRAN's machines varies, so only a suite that is small here is safe there.
# Every test that took 0.15s or more in a CRAN-mode profile is marked with this
# (cartograms, sweeps over every map verb or projection, anything that renders
# a world map), which leaves CRAN about 30s of tests here. They still run under
# devtools::test() and on every CI leg, both of which set NOT_CRAN=true, so
# none of them goes unrun. Mark a test for what it costs, measured, not for
# what it covers.
skip_slow_on_cran <- function() testthat::skip_on_cran()
