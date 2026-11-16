// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title PriceOracle — demo price feed (origin chain).
/// @notice Emits PriceUpdate on every report. Anyone may report a price.
/// This is a stand-in for a production feed (Chainlink / Uniswap TWAP):
/// the reactive contract subscribes by event signature, so pointing it at a
/// real feed is a one-line constructor change. Prices are USD x 1e8.
contract PriceOracle {
    event PriceUpdate(uint256 price, uint256 timestamp);

    uint256 public latestPrice;
    uint256 public updatedAt;
    uint256 public updateCount;

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function reportPrice(uint256 price) external {
        require(price > 0, "price is zero");
        latestPrice = price;
        updatedAt = block.timestamp;
        updateCount++;
        emit PriceUpdate(price, block.timestamp);
    }
}
