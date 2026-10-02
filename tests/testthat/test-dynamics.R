# Distribution dynamics (R/dynamics.R).

test_that("a two-state chain has its known steady state and passage times", {
  # P = [[0.9, 0.1], [0.2, 0.8]]: pi = (2/3, 1/3); first passage 1 -> 2 takes
  # 1 / 0.1 = 10 steps and 2 -> 1 takes 1 / 0.2 = 5; recurrence is 1 / pi.
  p <- matrix(c(0.9, 0.2, 0.1, 0.8), 2)
  pi <- countryatlas:::ergodic_distribution(p)
  expect_equal(pi, c(2, 1) / 3)
  m <- countryatlas:::first_passage(p, pi)
  expect_equal(m, matrix(c(1.5, 5, 10, 3), 2))
})

test_that("transition_matrix() counts a deterministic permutation panel", {
  # Four countries trade places each year in a fixed cycle, so with two
  # classes every country alternates between them: P is the swap.
  iso <- c("AAA", "BBB", "CCC", "DDD")
  pan <- do.call(rbind, lapply(0:5, function(t) {
    data.frame(iso3c = iso, year = 2000 + t,
               v = c(1, 2, 3, 4)[((seq_along(iso) + 2 * t - 1) %% 4) + 1])
  }))
  tm <- transition_matrix(pan, v, n_classes = 2)
  expect_named(tm, c("from", "to", "n", "p"))
  expect_equal(tm$p, c(0, 1, 1, 0))
  expect_equal(sum(tm$n), 4L * 5L)
  expect_equal(attr(tm, "ergodic"), c(0.5, 0.5))
  # step = 2 sees the cycle come back: everyone stays in their class.
  tm2 <- transition_matrix(pan, v, n_classes = 2, step = 2)
  expect_equal(tm2$p, c(1, 0, 0, 1))
  # A gap gives no transition rather than a longer one.
  gap <- pan[pan$year != 2002, ]
  expect_equal(sum(transition_matrix(gap, v, n_classes = 2)$n), 4L * 3L)
  expect_error(transition_matrix(rbind(pan, pan), v), "more than one row")
})

test_that("relative classes are fixed across years", {
  # Everyone doubles every year: relative to the mean nothing moves.
  pan <- expand.grid(iso3c = c("AAA", "BBB", "CCC", "DDD"), year = 2000:2004,
                     stringsAsFactors = FALSE)
  base <- c(AAA = 1, BBB = 2, CCC = 4, DDD = 8)
  pan$v <- base[pan$iso3c] * 2^(pan$year - 2000)
  tm <- transition_matrix(pan, v, n_classes = 2, classes = "relative")
  expect_equal(tm$p, c(1, 0, 0, 1))
  expect_length(attr(tm, "breaks"), 3L)
})

test_that("spatial_markov() conditions on the neighbours and tests homogeneity", {
  skip_slow_on_cran()
  set.seed(11)
  iso <- countryatlas::world_snapshot$countries$iso3c
  pan <- expand.grid(iso3c = iso, year = 2010:2014, stringsAsFactors = FALSE)
  pan$v <- exp(stats::rnorm(nrow(pan)))
  sm <- spatial_markov(pan, v, n_classes = 3)
  expect_named(sm, c("lag_class", "from", "to", "n", "p"))
  expect_setequal(unique(sm$lag_class), 1:3)
  test <- attr(sm, "test")
  expect_identical(test$statistic, c("LR", "Q"))
  expect_true(all(test$df > 0))
  # Values drawn independently of the neighbours: no evidence against
  # homogeneity at the usual level.
  expect_true(all(test$p_value > 0.01))
  # The conditional counts add up to the pooled ones.
  pooled <- attr(sm, "pooled")
  agg <- stats::aggregate(n ~ from + to, data = sm, FUN = sum)
  agg <- agg[order(agg$to, agg$from), ]
  expect_equal(agg$n, pooled$n[order(pooled$to, pooled$from)])
})

test_that("rank_mobility() reads an unchanged and a reversed ranking", {
  pan <- data.frame(iso3c = rep(c("AAA", "BBB", "CCC", "DDD", "EEE"), 2),
                    year = rep(c(2000, 2010), each = 5),
                    v = c(1:5, 1:5))
  same <- rank_mobility(pan, v, 2000, 2010, k = 1)
  expect_equal(same$tau, 1)
  expect_equal(same$share_moved, 0)
  pan$v[6:10] <- 5:1
  flip <- rank_mobility(pan, v, 2000, 2010, k = 1)
  expect_equal(flip$tau, -1)
  expect_equal(flip$share_moved, 0.8)   # the middle country stays put
  expect_error(rank_mobility(pan[1:4, ], v, 2000, 2010), "both years")
})
