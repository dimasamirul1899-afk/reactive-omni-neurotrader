// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { TradeExecutor } from "../src/TradeExecutor.sol";

contract TradeExecutorTest is Test {
    address payable internal constant PROXY = payable(address(0xBEEF));
    address internal constant REACTIVE = address(0xCAFE);
    address internal constant ORACLE = address(0x1234);

    TradeExecutor internal ex;

    function setUp() public {
        ex = new TradeExecutor(IPayable(PROXY), REACTIVE, ORACLE);
    }

    function _exec(uint8 action, uint256 price, int256 score) internal {
        vm.prank(PROXY);
        ex.execute(REACTIVE, action, price, score);
    }

    function testBuyOpensLong() public {
        _exec(1, 300000000000, 500000000000000000);
        assertEq(ex.position(), 1);
        assertEq(ex.entryPrice(), 300000000000);
        assertEq(ex.tradeCount(), 1);
    }

    function testSecondBuyIgnored() public {
        _exec(1, 300000000000, 500000000000000000);
        _exec(1, 310000000000, 600000000000000000);
        assertEq(ex.tradeCount(), 1);
        assertEq(ex.ignoredCount(), 1);
        assertEq(ex.entryPrice(), 300000000000);
    }

    function testSellClosesWithPnl() public {
        _exec(1, 300000000000, 500000000000000000);
        _exec(2, 315000000000, -500000000000000000);
        assertEq(ex.position(), 0);
        assertEq(ex.tradeCount(), 2);
        assertEq(ex.realizedPnl(), 15000000000); // +$150 x 1e8
    }

    function testSellWhenFlatIgnored() public {
        _exec(2, 300000000000, -500000000000000000);
        assertEq(ex.tradeCount(), 0);
        assertEq(ex.ignoredCount(), 1);
    }

    function testPaperValue() public {
        _exec(1, 300000000000, 500000000000000000);
        assertEq(ex.paperValue(310000000000), 10000000000);
        assertEq(ex.paperValue(290000000000), -10000000000);
    }

    function testOnlyProxyCanCall() public {
        vm.expectRevert();
        ex.execute(REACTIVE, 1, 300000000000, 0);
    }

    function testWrongReactiveReverts() public {
        vm.prank(PROXY);
        vm.expectRevert();
        ex.execute(address(0xDEAD), 1, 300000000000, 0);
    }

    function testBadActionReverts() public {
        vm.prank(PROXY);
        vm.expectRevert();
        ex.execute(REACTIVE, 9, 300000000000, 0);
    }
}
