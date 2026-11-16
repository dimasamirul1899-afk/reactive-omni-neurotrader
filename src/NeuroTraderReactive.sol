// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";
import { NeuroNet } from "./NeuroNet.sol";

/// @title NeuroTraderReactive — the AI lives in this contract.
/// @notice Subscribes to PriceUpdate events on the origin chain. On every
/// event it updates an 8-price window, runs the frozen 3->4->1 MLP
/// (NeuroNet) on-chain, and when the model is confident (score >= +0.25
/// BUY, <= -0.25 SELL) it requests a callback to the TradeExecutor on the
/// destination chain. No off-chain bot, no paid API: the model executes
/// inside react(), deterministically, on Reactive Lasna.
contract NeuroTraderReactive is AbstractReactive {
    uint256 public constant WINDOW = 8;
    uint256 public constant COOLDOWN_UPDATES = 3;
    uint64 public constant CALLBACK_GAS_LIMIT = 500_000;

    uint256 public immutable originChainId;
    address public immutable oracle;
    uint256 public immutable priceTopic0;
    uint256 public destinationChainId;
    address public owner;
    address public executor;

    uint256[8] public priceWindow;
    uint256 public windowCount;
    uint8 public lastAction; // 0 = none, 1 = BUY, 2 = SELL
    uint256 public updatesSinceAction;
    uint256 public decisions;
    uint256 public callbacksSent;

    event Decision(uint256 indexed price, int256 score, uint8 action, uint256 timestamp);
    event CallbackRequested(uint256 indexed price, uint8 action, int256 score);
    event ExecutorSet(address indexed executor);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    /// @param originChainId_ Chain the price oracle lives on (Base Sepolia: 84532).
    /// @param oracle_ PriceOracle contract emitting PriceUpdate.
    /// @param destinationChainId_ Chain the TradeExecutor lives on (Base Sepolia: 84532).
    constructor(uint256 originChainId_, address oracle_, uint256 destinationChainId_) payable {
        owner = msg.sender;
        originChainId = originChainId_;
        oracle = oracle_;
        destinationChainId = destinationChainId_;
        priceTopic0 = uint256(keccak256("PriceUpdate(uint256,uint256)"));
        SYSTEM.subscribe(
            originChainId_, oracle_, priceTopic0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
    }

    /// @notice Set the callback recipient (deploy order: reactive first, then
    /// executor, then wire it here). Owner-only.
    function setExecutor(address executor_) external onlyOwner {
        executor = executor_;
        emit ExecutorSet(executor_);
    }

    /// @notice Settles outstanding debt to the system contract from balance.
    function coverDebt() external {
        _coverDebt();
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        if (log_.topic0 != priceTopic0 || log_.opCode != 1) return;
        (uint256 price, ) = abi.decode(log_.data, (uint256, uint256));
        if (price == 0) return;

        for (uint256 i = WINDOW - 1; i > 0; i--) {
            priceWindow[i] = priceWindow[i - 1];
        }
        priceWindow[0] = price;
        if (windowCount < WINDOW) windowCount++;
        updatesSinceAction++;

        if (windowCount < WINDOW) return;

        int256 score = NeuroNet.predict(NeuroNet.features(priceWindow));
        uint8 action = NeuroNet.decide(score);

        // No trade: not confident, same side as last time, or cooling down.
        if (action == 0 || action == lastAction) {
            emit Decision(price, score, 0, block.timestamp);
            return;
        }
        if (lastAction != 0 && updatesSinceAction < COOLDOWN_UPDATES) {
            emit Decision(price, score, 0, block.timestamp);
            return;
        }

        lastAction = action;
        updatesSinceAction = 0;
        decisions++;
        emit Decision(price, score, action, block.timestamp);
        if (executor == address(0)) return;

        bytes memory payload =
            abi.encodeWithSignature("execute(address,uint8,uint256,int256)", address(0), action, price, score);
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destinationChainId,
                recipient: executor,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
        callbacksSent++;
        emit CallbackRequested(price, action, score);
    }
}
