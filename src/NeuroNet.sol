// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title NeuroNet — a tiny 3 -> 4 -> 1 MLP that runs fully on-chain.
/// @notice Fixed-point math, scale 1e18. Activation phi(x) = x / (1 + |x|).
/// Weights were trained offline (train_model.py, pure Python, synthetic
/// momentum-regime price paths, seed 1337) and frozen here. On fresh
/// synthetic data (seed 999, 25,200 windows) at |score| >= 0.25: 77.3%
/// accuracy (vs 50% random), 48.8% coverage; raw sign accuracy 71.2%.
/// Features are computed from the last 8 prices (p0 = newest, USD x 1e8):
///   f1 = 10 * (p0 - p1) / p1                       (1-step return)
///   f2 = 10 * (p0 - p4) / p4                       (5-step return)
///   f3 = 10 * (max - min) / mean over the window   (volatility)
library NeuroNet {
    int256 internal constant SCALE = 1e18;
    int256 internal constant BUY_THRESHOLD = 250000000000000000; // +0.25
    int256 internal constant SELL_THRESHOLD = -250000000000000000; // -0.25

    // Trained weights (x1e18). See model-weights.json / MODEL.md.
    int256 private constant W1_00 = -414742126877598464;
    int256 private constant W1_01 = -345943257349593856;
    int256 private constant W1_02 = -719179605000871168;
    int256 private constant W1_10 = 168868152620823776;
    int256 private constant W1_11 = -197634148319973728;
    int256 private constant W1_12 = -793939866610911232;
    int256 private constant W1_20 = 385344431955193216;
    int256 private constant W1_21 = -1337024450908922112;
    int256 private constant W1_22 = -396787589984056384;
    int256 private constant W1_30 = 346384572712548032;
    int256 private constant W1_31 = -1206410045058986496;
    int256 private constant W1_32 = -15604900799742624;
    int256 private constant B1_0 = -289612289081566;
    int256 private constant B1_1 = -180347767765144512;
    int256 private constant B1_2 = 104465541226820784;
    int256 private constant B1_3 = -8909020327705132;
    int256 private constant W2_0 = -359427052381787584;
    int256 private constant W2_1 = 151175768689875200;
    int256 private constant W2_2 = -1301855387523353344;
    int256 private constant W2_3 = -977046712566446976;
    int256 private constant B2 = 3309466415263426;

    /// @notice Smooth bounded activation: phi(x) = x / (1 + |x|), in 1e18 scale.
    function phi(int256 x) internal pure returns (int256) {
        int256 ax = x >= 0 ? x : -x;
        return (x * SCALE) / (SCALE + ax);
    }

    /// @notice Features from an 8-price window (newest first), 1e18 scale.
    function features(uint256[8] memory prices) internal pure returns (int256[3] memory f) {
        int256 p0 = int256(prices[0]);
        int256 p1 = int256(prices[1]);
        int256 p4 = int256(prices[4]);
        // f1 = 10 * (p0 - p1) / p1
        f[0] = ((p0 - p1) * 10 * SCALE) / p1;
        // f2 = 10 * (p0 - p4) / p4
        f[1] = ((p0 - p4) * 10 * SCALE) / p4;
        // f3 = 10 * (max - min) / mean
        uint256 lo = prices[0];
        uint256 hi = prices[0];
        uint256 sum = 0;
        for (uint256 i = 0; i < 8; i++) {
            if (prices[i] < lo) lo = prices[i];
            if (prices[i] > hi) hi = prices[i];
            sum += prices[i];
        }
        int256 mean = int256(sum / 8);
        f[2] = (int256(hi - lo) * 10 * SCALE) / mean;
    }

    /// @notice Forward pass. Returns the score in (-1e18, 1e18).
    function predict(int256[3] memory f) internal pure returns (int256 score) {
        int256 h0 = phi((W1_00 * f[0] + W1_01 * f[1] + W1_02 * f[2]) / SCALE + B1_0);
        int256 h1 = phi((W1_10 * f[0] + W1_11 * f[1] + W1_12 * f[2]) / SCALE + B1_1);
        int256 h2 = phi((W1_20 * f[0] + W1_21 * f[1] + W1_22 * f[2]) / SCALE + B1_2);
        int256 h3 = phi((W1_30 * f[0] + W1_31 * f[1] + W1_32 * f[2]) / SCALE + B1_3);
        int256 pre = (W2_0 * h0 + W2_1 * h1 + W2_2 * h2 + W2_3 * h3) / SCALE + B2;
        score = phi(pre);
    }

    /// @notice 1 = BUY, 2 = SELL, 0 = HOLD.
    function decide(int256 score) internal pure returns (uint8) {
        if (score >= BUY_THRESHOLD) return 1;
        if (score <= SELL_THRESHOLD) return 2;
        return 0;
    }
}
