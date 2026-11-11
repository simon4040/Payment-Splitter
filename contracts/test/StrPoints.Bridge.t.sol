// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {StrPointsTestBase} from "./StrPoints.Base.t.sol";
import {StrPoints} from "../StrPoints.sol";
import {MockTokenMessengerV2} from "../test-helpers/MockTokenMessengerV2.sol";

contract StrPointsBridgeTest is StrPointsTestBase {
    bytes internal constant HOOK = hex"636374702d666f72776172640000000000000000000000000000000000000000";
    uint256 internal constant START_BAL = 10_000_000 * UNIT;

    function setUp() public override {
        super.setUp();
        _fundBridge(sp, dave, START_BAL);
    }

    function _bridge(uint256 amt, uint256 maxFee, uint32 fin, address rcpt, uint16 maxBps) internal {
        vm.prank(dave);
        sp.bridge(amt, maxFee, fin, rcpt, maxBps);
    }

    function _assertNothingMoved() internal view {
        assertEq(usdc.balanceOf(dave), START_BAL, "dave moved");
        assertEq(usdc.balanceOf(address(sp)), 0, "sp holds");
        assertEq(usdc.balanceOf(feeRecipient), 0, "fee paid");
        assertEq(usdc.balanceOf(address(messenger)), 0, "messenger got");
        assertEq(messenger.callCount(), 0, "messenger called");
        assertEq(sp.pointsOf(dave), 0, "points");
        assertEq(sp.userCount(), 0, "registered");
    }

    // ───────────── getters ─────────────

    function test_Getters_Bridge() public view {
        assertEq(sp.tokenMessenger(), address(messenger));
        assertEq(sp.destinationDomain(), DOMAIN);
        assertEq(sp.FORWARD_HOOK(), HOOK);
        assertEq(sp.FORWARD_HOOK().length, 32);
        assertEq(sp.REASON_BRIDGE(), 5);
    }

    // ───────────── happy path ─────────────

    function test_Bridge_HappyPath_RecordsEveryMessengerArg() public {
        uint256 amt = 1000 * UNIT;
        uint256 fee = amt * FEE_BPS / 10_000; // 5 USDC
        uint256 burn = amt - fee;
        _bridge(amt, 100_000, 2000, bob, 50);

        assertEq(messenger.callCount(), 1);
        assertEq(messenger.lastCaller(), address(sp));
        assertEq(messenger.lastAmount(), burn);
        assertEq(messenger.lastDestinationDomain(), DOMAIN);
        assertEq(messenger.lastMintRecipient(), bytes32(uint256(uint160(bob))));
        assertEq(messenger.lastBurnToken(), address(usdc));
        assertEq(messenger.lastDestinationCaller(), bytes32(0));
        assertEq(messenger.lastMaxFee(), 100_000);
        assertEq(messenger.lastMinFinalityThreshold(), 2000);
        assertEq(messenger.lastHookData(), HOOK);

        assertEq(usdc.balanceOf(feeRecipient), fee);
        assertEq(usdc.balanceOf(address(messenger)), burn);
        assertEq(usdc.balanceOf(dave), START_BAL - amt);
        assertEq(usdc.balanceOf(address(sp)), 0);
        assertEq(usdc.allowance(address(sp), address(messenger)), 0);
        assertEq(usdc.allowance(address(sp), address(factory)), 0);
        assertEq(sp.pointsOf(dave), 150);
    }

    function test_Bridge_FastFinality1000() public {
        _bridge(100 * UNIT, 0, 1000, bob, 500);
        assertEq(messenger.lastMinFinalityThreshold(), 1000);
    }

    function test_Bridge_RecipientDiffersFromCaller_PointsToCaller() public {
        _bridge(10 * UNIT, 0, 1000, eve, 500);
        assertEq(messenger.lastMintRecipient(), bytes32(uint256(uint160(eve))));
        assertEq(sp.pointsOf(dave), 25);
        assertEq(sp.pointsOf(eve), 0);
    }

    function test_Bridge_CustomDestinationDomain() public {
        StrPoints p = new StrPoints(address(factory), address(usdc), DAY, address(messenger), 26);
        _fundBridge(p, dave, 10 * UNIT);
        vm.prank(dave);
        p.bridge(10 * UNIT, 0, 1000, bob, 500);
        assertEq(messenger.lastDestinationDomain(), 26);
    }

    function test_Bridge_MaxFeeJustBelowBurnAccepted() public {
        uint256 amt = 100 * UNIT;
        uint256 burn = amt - amt * FEE_BPS / 10_000;
        _bridge(amt, burn - 1, 1000, bob, 500);
        assertEq(messenger.lastMaxFee(), burn - 1);
    }

    function test_Bridge_MaxPlatformFeeEqualToCurrentAccepted() public {
        _bridge(100 * UNIT, 0, 1000, bob, FEE_BPS);
        assertEq(messenger.callCount(), 1);
    }

    function test_Bridge_TinyAmountNoFeeRoundsToZero() public {
        _bridge(1, 0, 1000, bob, 500); // fee = 1*50/10000 = 0, burn = 1
        assertEq(messenger.lastAmount(), 1);
        assertEq(usdc.balanceOf(feeRecipient), 0);
        assertEq(sp.pointsOf(dave), 0);
    }

    function test_Bridge_EmitsBridgedAndPoints() public {
        uint256 amt = 250 * UNIT;
        uint256 fee = amt * FEE_BPS / 10_000;
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.PointsAwarded(dave, 100, 5);
        vm.expectEmit(true, true, false, true, address(sp));
        emit StrPoints.Bridged(dave, bob, amt, fee, amt - fee, 7);
        _bridge(amt, 7, 2000, bob, 100);
    }

    // ───────────── live factory fee values ─────────────

    function test_Bridge_UsesLiveFeeBpsAndRecipient() public {
        address newRecipient = makeAddr("newRecipient");
        vm.startPrank(owner);
        factory.setFeeBps(200);
        factory.setFeeRecipient(newRecipient);
        vm.stopPrank();

        uint256 amt = 500 * UNIT;
        uint256 fee = amt * 200 / 10_000; // 10 USDC
        _bridge(amt, 0, 1000, bob, 200);

        assertEq(usdc.balanceOf(newRecipient), fee);
        assertEq(usdc.balanceOf(feeRecipient), 0);
        assertEq(messenger.lastAmount(), amt - fee);
        assertEq(usdc.balanceOf(address(sp)), 0);
    }

    function test_Bridge_FeeZero_NoFeeTransfer() public {
        vm.prank(owner);
        factory.setFeeBps(0);
        vm.recordLogs();
        _bridge(100 * UNIT, 0, 1000, bob, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("Transfer(address,address,uint256)");
        uint256 transfers;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig) {
                transfers++;
                assertTrue(logs[i].topics[2] != bytes32(uint256(uint160(feeRecipient))), "fee transfer");
            }
        }
        assertEq(transfers, 2); // user->sp, sp->messenger
        assertEq(usdc.balanceOf(feeRecipient), 0);
        assertEq(messenger.lastAmount(), 100 * UNIT);
    }

    function test_Bridge_FeeMax500Bps() public {
        vm.prank(owner);
        factory.setFeeBps(500);
        uint256 amt = 1000 * UNIT;
        _bridge(amt, 0, 1000, bob, 500);
        assertEq(usdc.balanceOf(feeRecipient), 50 * UNIT);
        assertEq(messenger.lastAmount(), 950 * UNIT);
    }

    function test_Bridge_FeeIncreaseAboveUserCapReverts() public {
        // user signed with maxPlatformFeeBps = 50; owner raises fee before inclusion
        vm.prank(owner);
        factory.setFeeBps(51);
        vm.expectRevert(StrPoints.FeeTooHigh.selector);
        _bridge(100 * UNIT, 0, 1000, bob, 50);
        _assertNothingMoved();
    }

    // ───────────── previewBridge ─────────────

    function test_PreviewBridge_MatchesFactoryFee() public view {
        (uint256 fee, uint256 burn, uint16 bps) = sp.previewBridge(1000 * UNIT);
        assertEq(bps, FEE_BPS);
        assertEq(fee, 5 * UNIT);
        assertEq(burn, 995 * UNIT);
    }

    function test_PreviewBridge_TracksLiveFee() public {
        vm.prank(owner);
        factory.setFeeBps(500);
        (uint256 fee, uint256 burn, uint16 bps) = sp.previewBridge(200 * UNIT);
        assertEq(bps, 500);
        assertEq(fee, 10 * UNIT);
        assertEq(burn, 190 * UNIT);
        vm.prank(owner);
        factory.setFeeBps(0);
        (fee, burn, bps) = sp.previewBridge(200 * UNIT);
        assertEq(bps, 0);
        assertEq(fee, 0);
        assertEq(burn, 200 * UNIT);
    }

    function test_PreviewBridge_ZeroAmount() public view {
        (uint256 fee, uint256 burn, uint16 bps) = sp.previewBridge(0);
        assertEq(fee, 0);
        assertEq(burn, 0);
        assertEq(bps, FEE_BPS);
    }

    function test_PreviewBridge_MatchesActualBridge() public {
        uint256 amt = 123_456_789;
        (uint256 fee, uint256 burn,) = sp.previewBridge(amt);
        _bridge(amt, 0, 1000, bob, 500);
        assertEq(usdc.balanceOf(feeRecipient), fee);
        assertEq(messenger.lastAmount(), burn);
    }

    // ───────────── reverts ─────────────

    function test_Revert_ZeroAmount() public {
        vm.expectRevert(StrPoints.ZeroAmount.selector);
        _bridge(0, 0, 1000, bob, 500);
        _assertNothingMoved();
    }

    function test_Revert_ZeroRecipient() public {
        vm.expectRevert(StrPoints.ZeroAddress.selector);
        _bridge(100 * UNIT, 0, 1000, address(0), 500);
        _assertNothingMoved();
    }

    function test_Revert_InvalidFinality() public {
        uint32[6] memory bad = [uint32(0), 1, 999, 1001, 1999, 2001];
        for (uint256 i = 0; i < bad.length; ++i) {
            vm.expectRevert(StrPoints.InvalidFinality.selector);
            _bridge(100 * UNIT, 0, bad[i], bob, 500);
        }
        vm.expectRevert(StrPoints.InvalidFinality.selector);
        _bridge(100 * UNIT, 0, type(uint32).max, bob, 500);
        _assertNothingMoved();
    }

    function test_Revert_FeeTooHigh() public {
        vm.expectRevert(StrPoints.FeeTooHigh.selector);
        _bridge(100 * UNIT, 0, 1000, bob, FEE_BPS - 1);
        vm.expectRevert(StrPoints.FeeTooHigh.selector);
        _bridge(100 * UNIT, 0, 1000, bob, 0);
        _assertNothingMoved();
    }

    function test_Revert_InvalidMaxFee_EqualToBurn() public {
        uint256 amt = 100 * UNIT;
        uint256 burn = amt - amt * FEE_BPS / 10_000;
        vm.expectRevert(StrPoints.InvalidMaxFee.selector);
        _bridge(amt, burn, 1000, bob, 500);
        _assertNothingMoved();
    }

    function test_Revert_InvalidMaxFee_AboveBurn() public {
        vm.expectRevert(StrPoints.InvalidMaxFee.selector);
        _bridge(100 * UNIT, type(uint256).max, 1000, bob, 500);
        _assertNothingMoved();
    }

    function test_Revert_InvalidMaxFee_GrossAmountButNotNet() public {
        // maxFee == amount (< ... would pass a gross check) but >= burn -> reverts
        uint256 amt = 100 * UNIT;
        vm.expectRevert(StrPoints.InvalidMaxFee.selector);
        _bridge(amt, amt - 1, 1000, bob, 500);
        _assertNothingMoved();
    }

    function test_Revert_MessengerReverts_NothingMoved() public {
        messenger.setShouldRevert(true);
        vm.expectRevert(MockTokenMessengerV2.MockMessengerReverted.selector);
        _bridge(1000 * UNIT, 0, 1000, bob, 500);
        _assertNothingMoved();
        assertEq(usdc.allowance(address(sp), address(messenger)), 0);
    }

    function test_Revert_NoAllowance() public {
        address frank = makeAddr("frank");
        usdc.mint(frank, 100 * UNIT);
        vm.prank(frank);
        vm.expectRevert();
        sp.bridge(100 * UNIT, 0, 1000, bob, 500);
        assertEq(usdc.balanceOf(frank), 100 * UNIT);
        assertEq(usdc.balanceOf(feeRecipient), 0);
        assertEq(messenger.callCount(), 0);
        assertEq(sp.pointsOf(frank), 0);
        assertEq(sp.userCount(), 0);
    }

    function test_Revert_InsufficientBalance() public {
        address frank = makeAddr("frank");
        _fundBridge(sp, frank, 10 * UNIT);
        vm.prank(frank);
        vm.expectRevert();
        sp.bridge(100 * UNIT, 0, 1000, bob, 500);
        assertEq(usdc.balanceOf(frank), 10 * UNIT);
        assertEq(usdc.balanceOf(feeRecipient), 0);
        assertEq(messenger.callCount(), 0);
        assertEq(sp.pointsOf(frank), 0);
    }

    function test_Revert_PartialAllowance() public {
        address frank = makeAddr("frank");
        usdc.mint(frank, 100 * UNIT);
        vm.startPrank(frank);
        usdc.approve(address(sp), 100 * UNIT - 1);
        vm.expectRevert();
        sp.bridge(100 * UNIT, 0, 1000, bob, 500);
        vm.stopPrank();
        assertEq(usdc.balanceOf(frank), 100 * UNIT);
        assertEq(messenger.callCount(), 0);
    }

    // ───────────── check-in / streak independence ─────────────

    function test_Bridge_DoesNotAffectCheckInOrStreak() public {
        _bridge(100 * UNIT, 0, 1000, bob, 500); // points: 75
        (, uint8 streak, bool can, ) = sp.checkInStatus(dave);
        assertEq(streak, 0);
        assertTrue(can);

        _checkIn(sp, dave);
        assertEq(sp.pointsOf(dave), 75 + 5);
        assertEq(sp.currentStreak(dave), 1);

        _bridge(100 * UNIT, 0, 1000, bob, 500); // capped: 75 already earned vs cap 150 -> +75
        assertEq(sp.currentStreak(dave), 1);
        (, , bool canAgain, ) = sp.checkInStatus(dave);
        assertFalse(canAgain); // still checked in today, bridge did not change it

        vm.warp(block.timestamp + DAY);
        _checkIn(sp, dave);
        assertEq(sp.currentStreak(dave), 2);
    }

    function test_Bridge_DoesNotCountAsCheckIn() public {
        _bridge(1000 * UNIT, 0, 1000, bob, 500);
        _checkIn(sp, dave); // should still be allowed
        assertEq(sp.currentStreak(dave), 1);
    }
}
