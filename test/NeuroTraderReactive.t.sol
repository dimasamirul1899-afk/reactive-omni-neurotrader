// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { NeuroTraderReactive } from "../src/NeuroTraderReactive.sol";

/// @notice Minimal stand-in for the Reactive system contract, etched at the
/// real SYSTEM address (0x8888...8888) so we can observe subscriptions and
/// callback requests without a live network.
contract MockSystem {
    uint256 public subscribeCalls;
    uint256 public callbackCalls;
    uint256 public lastChainId;
    address public lastRecipient;
    bytes public lastPayload;
    uint64 public lastGasLimit;

    function subscribe(uint256, address, uint256, uint256, uint256, uint256) external {
        subscribeCalls++;
    }

    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external {}

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config) external {
        callbackCalls++;
        lastChainId = config.chainId;
        lastRecipient = config.recipient;
        lastGasLimit = config.gasLimit;
        lastPayload = config.payload;
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }
}

contract NeuroTraderReactiveTest is Test {
    address internal constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 internal constant BASE_SEPOLIA = 84532;
    address internal constant ORACLE = address(0x1234);
    address internal constant EXECUTOR = address(0xABCD);

    uint256 internal priceTopic0;
    MockSystem internal mock;
    MockSystem internal system; // same code, read at the etched SYSTEM address
    NeuroTraderReactive internal trader;

    function setUp() public {
        priceTopic0 = uint256(keccak256("PriceUpdate(uint256,uint256)"));
        mock = new MockSystem();
        vm.etch(SYSTEM_ADDR, address(mock).code);
        system = MockSystem(SYSTEM_ADDR);
        trader = new NeuroTraderReactive(BASE_SEPOLIA, ORACLE, BASE_SEPOLIA);
        trader.setExecutor(EXECUTOR);
    }

    function _log(uint256 price) internal view returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord({
            chainId: BASE_SEPOLIA,
            contractAddress: ORACLE,
            topic0: priceTopic0,
            topic1: 0,
            topic2: 0,
            topic3: 0,
            data: abi.encode(price, uint256(1_700_000_000)),
            blockNumber: 1,
            opCode: 1,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
    }

    function _feed(uint256[] memory prices) internal {
        vm.startPrank(SYSTEM_ADDR);
        for (uint256 i = 0; i < prices.length; i++) {
            trader.react(_log(prices[i]));
        }
        vm.stopPrank();
    }

    function _uptrend() internal pure returns (uint256[] memory p) {
        // Oldest -> newest, +0.5%/step (matches the UP test vector).
        p = new uint256[](8);
        p[0] = 300000000000;
        p[1] = 301500000000;
        p[2] = 303007500000;
        p[3] = 304522537500;
        p[4] = 306045150187;
        p[5] = 307575375937;
        p[6] = 309113252816;
        p[7] = 310658819080;
    }

    function _downtrend() internal pure returns (uint256[] memory p) {
        p = new uint256[](8);
        p[0] = 300000000000;
        p[1] = 298500000000;
        p[2] = 297007500000;
        p[3] = 295522462500;
        p[4] = 294044850187;
        p[5] = 292574625936;
        p[6] = 291111752806;
        p[7] = 289656194041;
    }

    function testSubscribesOnDeploy() public view {
        assertEq(system.subscribeCalls(), 1);
    }

    function testUptrendBuysAndCallbacks() public {
        _feed(_uptrend());
        assertEq(trader.decisions(), 1);
        assertEq(trader.lastAction(), 1);
        assertEq(trader.callbacksSent(), 1);
        assertEq(system.callbackCalls(), 1);
        assertEq(system.lastChainId(), BASE_SEPOLIA);
        assertEq(system.lastRecipient(), EXECUTOR);
        // Payload = execute(address,uint8,uint256,int256); decode past the
        // 4-byte selector and check every argument.
        bytes memory pl = system.lastPayload();
        bytes memory body = new bytes(pl.length - 4);
        for (uint256 i = 0; i < body.length; i++) body[i] = pl[i + 4];
        (address senderArg, uint8 action, uint256 price, int256 score) =
            abi.decode(body, (address, uint8, uint256, int256));
        assertEq(senderArg, address(0)); // proxy overwrites this at delivery
        assertEq(action, 1);
        assertEq(price, 310658819080);
        assertEq(score, 343201963862963120);
    }

    function testDowntrendSellsAndCallbacks() public {
        _feed(_downtrend());
        assertEq(trader.decisions(), 1);
        assertEq(trader.lastAction(), 2);
        assertEq(system.callbackCalls(), 1);
    }

    function testFlatHoldsNoCallback() public {
        uint256[] memory p = new uint256[](8);
        for (uint256 i = 0; i < 8; i++) p[i] = 300000000000 + (i % 2) * 1000000;
        _feed(p);
        assertEq(trader.decisions(), 0);
        assertEq(system.callbackCalls(), 0);
    }

    function testWrongTopicIgnored() public {
        IReactive.LogRecord memory log = _log(310658819080);
        log.topic0 = uint256(keccak256("Transfer(address,address,uint256)"));
        vm.prank(SYSTEM_ADDR);
        trader.react(log);
        assertEq(trader.windowCount(), 0);
        assertEq(system.callbackCalls(), 0);
    }

    function testOnlySystemCanReact() public {
        vm.expectRevert();
        trader.react(_log(300000000000));
    }

    function testOnlyOwnerSetsExecutor() public {
        vm.prank(address(0x9999));
        vm.expectRevert();
        trader.setExecutor(address(0x1111));
    }

    function testNoRepeatSameSide() public {
        _feed(_uptrend());
        assertEq(system.callbackCalls(), 1);
        // Feed 3 more uptrend prices: same side + cooldown -> no 2nd callback.
        uint256[] memory more = new uint256[](3);
        more[0] = 312211614177;
        more[1] = 313772672276;
        more[2] = 315341535638;
        _feed(more);
        assertEq(system.callbackCalls(), 1);
    }
}
