// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

/// @title TradeExecutor — destination contract: the model's decisions land here.
/// @notice Receives callbacks from NeuroTraderReactive (via the Reactive
/// callback proxy) and runs a paper long/flat portfolio against the oracle
/// price: BUY opens a long, SELL closes it and banks realized PnL. This is
/// the auditable on-chain record of every model decision — and the hook
/// where a real strategy (e.g. a DEX swap) would plug in.
contract TradeExecutor is AbstractCallback {
    uint8 public constant BUY = 1;
    uint8 public constant SELL = 2;

    address public immutable oracle;

    uint8 public position; // 0 = flat, 1 = long
    uint256 public entryPrice; // USD x 1e8
    int256 public realizedPnl; // USD x 1e8, signed
    uint256 public tradeCount;
    uint256 public ignoredCount;

    event TradeExecuted(address indexed reactive, uint8 action, uint256 price, int256 score, uint256 tradeIndex);
    event TradeIgnored(address indexed reactive, uint8 action, uint256 price, int256 score, string reason);

    constructor(IPayable callbackProxy_, address callbackSender_, address oracle_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {
        oracle = oracle_;
    }

    /// @notice Settles outstanding debt to the callback proxy from balance.
    function coverDebt() external {
        _coverDebt();
    }

    /// @notice Called by the Reactive callback proxy. The first argument is
    /// overwritten by the proxy with the reactive contract's address.
    function execute(address reactive_, uint8 action_, uint256 price_, int256 score_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        if (action_ == BUY) {
            if (position == 1) {
                ignoredCount++;
                emit TradeIgnored(reactive_, action_, price_, score_, "already long");
                return;
            }
            position = 1;
            entryPrice = price_;
        } else if (action_ == SELL) {
            if (position == 0) {
                ignoredCount++;
                emit TradeIgnored(reactive_, action_, price_, score_, "flat");
                return;
            }
            position = 0;
            realizedPnl += int256(price_) - int256(entryPrice);
            entryPrice = 0;
        } else {
            revert("bad action");
        }
        tradeCount++;
        emit TradeExecuted(reactive_, action_, price_, score_, tradeCount);
    }

    /// @notice Paper value (realized + unrealized) at a given current price.
    function paperValue(uint256 currentPrice) external view returns (int256) {
        if (position == 1) {
            return realizedPnl + int256(currentPrice) - int256(entryPrice);
        }
        return realizedPnl;
    }
}
