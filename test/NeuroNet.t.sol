// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { NeuroNet } from "../src/NeuroNet.sol";

/// @notice Exact vectors from ref_vectors.py (integer reference, same math).
contract NeuroNetTest is Test {
    uint256 internal constant E8 = 1e8;

    function upWindow() internal pure returns (uint256[8] memory w) {
        w = [
            uint256(310658819080),
            uint256(309113252816),
            uint256(307575375937),
            uint256(306045150187),
            uint256(304522537500),
            uint256(303007500000),
            uint256(301500000000),
            uint256(300000000000)
        ];
    }

    function downWindow() internal pure returns (uint256[8] memory w) {
        w = [
            uint256(289656194041),
            uint256(291111752806),
            uint256(292574625936),
            uint256(294044850187),
            uint256(295522462500),
            uint256(297007500000),
            uint256(298500000000),
            uint256(300000000000)
        ];
    }

    function flatWindow() internal pure returns (uint256[8] memory w) {
        w = [
            uint256(300002000000),
            uint256(300000000000),
            uint256(299998000000),
            uint256(300001000000),
            uint256(299999000000),
            uint256(300002000000),
            uint256(300000000000),
            uint256(299998000000)
        ];
    }

    function testPhi() public pure {
        assertEq(NeuroNet.phi(0), 0);
        assertEq(NeuroNet.phi(1e18), 0.5e18);
        assertEq(NeuroNet.phi(-1e18), -0.5e18);
        assertEq(NeuroNet.phi(9e18), 0.9e18);
    }

    function testFeaturesUp() public pure {
        int256[3] memory f = NeuroNet.features(upWindow());
        assertEq(f[0], 49999999997411951);
        assertEq(f[1], 201505006177087960);
        assertEq(f[2], 349122839757197109);
    }

    function testFeaturesDown() public pure {
        int256[3] memory f = NeuroNet.features(downWindow());
        assertEq(f[0], -50000000033320537);
        assertEq(f[1], -198504993812441583);
        assertEq(f[2], 350872785207693432);
    }

    function testFeaturesFlat() public pure {
        int256[3] memory f = NeuroNet.features(flatWindow());
        assertEq(f[0], 66666666666666);
        assertEq(f[1], 100000333334444);
        assertEq(f[2], 133333333333333);
    }

    function testPredictUpIsBuy() public pure {
        int256 score = NeuroNet.predict(NeuroNet.features(upWindow()));
        assertEq(score, 343201963862963120);
        assertEq(NeuroNet.decide(score), 1); // BUY
    }

    function testPredictDownIsSell() public pure {
        int256 score = NeuroNet.predict(NeuroNet.features(downWindow()));
        assertEq(score, -278930280135969516);
        assertEq(NeuroNet.decide(score), 2); // SELL
    }

    function testPredictFlatIsHold() public pure {
        int256 score = NeuroNet.predict(NeuroNet.features(flatWindow()));
        assertEq(score, -118073307254332881);
        assertEq(NeuroNet.decide(score), 0); // HOLD
    }
}
