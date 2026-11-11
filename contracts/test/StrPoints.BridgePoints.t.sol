// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrPointsTestBase} from "./StrPoints.Base.t.sol";
import {StrPoints} from "../StrPoints.sol";

contract StrPointsBridgePointsTest is StrPointsTestBase {
    uint256 internal id;
    uint8 internal constant REASON_BRIDGE = 5;

    function setUp() public override {
        super.setUp();
        id = _createDefault();
        _fundBridge(sp, dave, 100_000_000 * UNIT);
    }

    function _bridgeAmt(uint256 amt) internal {
        _bridgeAs(sp, dave, amt);
    }

    function _deposit(uint256 amt) internal {
        usdc.mint(dave, amt);
        _depViaPoints(sp, dave, id, amt);
    }

    // ───────────── tier table on gross amount ─────────────

    function _assertTier(uint256 amt, uint256 pts) internal {
        // fresh user per call so caps never interfere
        address u = makeAddr(string(abi.encodePacked("u", vm.toString(amt))));
        _fundBridge(sp, u, amt);
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.PointsAwarded(u, pts, REASON_BRIDGE);
        _bridgeAs(sp, u, amt);
        assertEq(sp.pointsOf(u), pts);
    }

    function test_Tier_1e6_5() public {
        _assertTier(1e6, 5);
    }

    function test_Tier_10e6_25() public {
        _assertTier(10e6, 25);
    }

    function test_Tier_50e6_50() public {
        _assertTier(50e6, 50);
    }

    function test_Tier_100e6_75() public {
        _assertTier(100e6, 75);
    }

    function test_Tier_250e6_100() public {
        _assertTier(250e6, 100);
    }

    function test_Tier_1000e6_150() public {
        _assertTier(1000e6, 150);
    }

    function test_Tier_UpperEdgesStayInLowerTier() public {
        _assertTier(10e6 - 1, 5);
        _assertTier(50e6 - 1, 25);
        _assertTier(100e6 - 1, 50);
        _assertTier(250e6 - 1, 75);
        _assertTier(1000e6 - 1, 100);
    }

    function test_Tier_HugeAmount() public {
        _assertTier(5_000_000e6, 150);
    }

    function test_BelowMin_999999_SkippedNoRegistration() public {
        _bridgeAmt(999_999);
        // fee on 999_999 = 4999 -> burn 995000; gross decides tier, not net
        assertEq(sp.pointsOf(dave), 0);
        assertEq(sp.userCount(), 0);
        (uint256 e,, , bool h) = sp.activityStatus(dave);
        assertEq(e, 0);
        assertFalse(h);
    }

    function test_BelowMin_EmitsPointsSkippedCause1() public {
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.PointsSkipped(dave, REASON_BRIDGE, 1);
        _bridgeAmt(999_999);
    }

    function test_GrossAmountDecidesTier_NetBelowThreshold() public {
        // gross 1e6 -> net 995_000 (< 1e6) but still qualifies on gross
        _bridgeAmt(1e6);
        assertEq(messenger.lastAmount(), 995_000);
        assertEq(sp.pointsOf(dave), 5);
        assertEq(sp.userCount(), 1);
    }

    function test_FirstBridgeRegistersUser() public {
        _bridgeAmt(1e6);
        assertEq(sp.userCount(), 1);
        (address[] memory us, uint256[] memory pts) = sp.getUsers(0, 10);
        assertEq(us[0], dave);
        assertEq(pts[0], 5);
    }

    // ───────────── shared cap with deposits / distributions ─────────────

    function test_Cap_TierZeroBridgesCapAt50() public {
        for (uint256 i = 0; i < 10; ++i) {
            _bridgeAmt(1e6);
        }
        assertEq(sp.pointsOf(dave), 50);
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.PointsSkipped(dave, REASON_BRIDGE, 2);
        _bridgeAmt(1e6);
        assertEq(sp.pointsOf(dave), 50);
        _assertStatus(sp, dave, 50, 50, 0, true);
        // the bridge itself still moved funds
        assertEq(messenger.callCount(), 11);
    }

    function test_Cap_BridgesAndDepositsShareCap() public {
        for (uint256 i = 0; i < 5; ++i) {
            _deposit(1e6); // 25
        }
        for (uint256 i = 0; i < 5; ++i) {
            _bridgeAmt(1e6); // 25
        }
        assertEq(sp.pointsOf(dave), 50);
        _deposit(1e6); // capped
        _bridgeAmt(1e6); // capped
        assertEq(sp.pointsOf(dave), 50);
    }

    function test_Cap_BridgesAndDistributionsShareCap() public {
        for (uint256 i = 0; i < 9; ++i) {
            _bridgeAmt(1e6); // 45
        }
        _directDeposit(id, 10e6);
        // distribution balance 10e6 - fee(0.5% of 10e6 = 50_000) = 9_950_000 -> tier 0 -> 5 pts
        vm.prank(dave);
        sp.distribute(id);
        assertEq(sp.pointsOf(dave), 50);
        _bridgeAmt(1e6);
        assertEq(sp.pointsOf(dave), 50);
    }

    function test_Cap_HighestTierRaisesCapAcrossActions() public {
        for (uint256 i = 0; i < 10; ++i) {
            _bridgeAmt(1e6); // 50, capped
        }
        _bridgeAmt(10e6); // tier 1 -> cap 75, +25 -> 75
        assertEq(sp.pointsOf(dave), 75);
        _assertStatus(sp, dave, 75, 75, 1, true);
        _deposit(1e6); // cap reached
        assertEq(sp.pointsOf(dave), 75);
        _bridgeAmt(50e6); // tier 2: cap 100, remaining 25 < 50 -> partial 25
        assertEq(sp.pointsOf(dave), 100);
        _assertStatus(sp, dave, 100, 100, 2, true);
    }

    function test_Cap_PartialAwardThenSkipped() public {
        _bridgeAmt(100e6); // 75 (tier 3 cap 150)
        _bridgeAmt(100e6); // 75 -> 150
        assertEq(sp.pointsOf(dave), 150);
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.PointsSkipped(dave, REASON_BRIDGE, 2);
        _bridgeAmt(100e6);
        assertEq(sp.pointsOf(dave), 150);
    }

    function test_Cap_TopTierBridgeEmitsPartial() public {
        // tier 5 cap 600: 4 bridges * 150 = 600
        for (uint256 i = 0; i < 4; ++i) {
            _bridgeAmt(1000e6);
        }
        assertEq(sp.pointsOf(dave), 600);
        _bridgeAmt(1000e6);
        assertEq(sp.pointsOf(dave), 600);
    }

    function test_Cap_BridgeFirstThenLowerTierDoesNotLowerCap() public {
        _bridgeAmt(250e6); // tier 4: 100 pts, cap 200
        _deposit(1e6); // tier 0 +5
        _assertStatus(sp, dave, 105, 200, 4, true);
    }

    function test_Cap_ResetsNextDayBucket() public {
        for (uint256 i = 0; i < 11; ++i) {
            _bridgeAmt(1e6);
        }
        assertEq(sp.pointsOf(dave), 50);
        vm.warp(block.timestamp + DAY);
        _assertStatus(sp, dave, 0, 50, 0, false);
        _bridgeAmt(1e6);
        assertEq(sp.pointsOf(dave), 55);
        _assertStatus(sp, dave, 5, 50, 0, true);
    }

    function test_Cap_PerUserIndependent() public {
        for (uint256 i = 0; i < 11; ++i) {
            _bridgeAmt(1e6);
        }
        _fundAndBridge(sp, eve, 1e6);
        assertEq(sp.pointsOf(eve), 5);
        assertEq(sp.pointsOf(dave), 50);
    }

    function test_Cap_CheckInDoesNotConsumeActivityCap() public {
        _checkIn(sp, dave);
        for (uint256 i = 0; i < 10; ++i) {
            _bridgeAmt(1e6);
        }
        assertEq(sp.pointsOf(dave), 55); // 5 check-in + 50 activity
    }

    function test_Bridge_BelowMinDoesNotRaiseTierOrConsumeCap() public {
        _bridgeAmt(999_999);
        _assertStatus(sp, dave, 0, 50, 0, false);
    }

    function test_Bridge_ShortDayInstanceBucketsByDayLength() public {
        StrPoints p = _newPoints(600);
        _fundBridge(p, eve, 100e6);
        for (uint256 i = 0; i < 11; ++i) {
            _bridgeAs(p, eve, 1e6);
        }
        assertEq(p.pointsOf(eve), 50);
        vm.warp(block.timestamp + 600);
        _bridgeAs(p, eve, 1e6);
        assertEq(p.pointsOf(eve), 55);
    }
}
