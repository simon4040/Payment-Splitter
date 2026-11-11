// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrPointsTestBase} from "./StrPoints.Base.t.sol";
import {StrPoints} from "../StrPoints.sol";

/// @dev Tier boundaries for pointsForAmount, depositToSplit (gross) and distribute (pre-distribution net balance).
contract StrPointsTiersTest is StrPointsTestBase {
    uint256[12] internal AMTS =
        [uint256(999_999), 1_000_000, 9_999_999, 10_000_000, 49_999_999, 50_000_000, 99_999_999, 100_000_000, 249_999_999, 250_000_000, 999_999_999, 1_000_000_000];
    // expected: qualifies, tier, points
    bool[12] internal EQ = [false, true, true, true, true, true, true, true, true, true, true, true];
    uint8[12] internal ET = [0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5];
    uint256[12] internal EP = [uint256(0), 5, 5, 25, 25, 50, 50, 75, 75, 100, 100, 150];

    uint256 internal id;

    function setUp() public override {
        super.setUp();
        id = _createDefault();
    }

    // ───────────── pointsForAmount ─────────────

    function test_PointsForAmount_AllBoundaries() public view {
        for (uint256 i = 0; i < 12; ++i) {
            (uint256 p, uint8 t, bool q) = sp.pointsForAmount(AMTS[i]);
            assertEq(p, EP[i], "points");
            assertEq(t, ET[i], "tier");
            assertEq(q, EQ[i], "qualifies");
        }
    }

    function test_PointsForAmount_Extremes() public view {
        (uint256 p, uint8 t, bool q) = sp.pointsForAmount(0);
        assertEq(p, 0);
        assertEq(t, 0);
        assertFalse(q);
        (p, t, q) = sp.pointsForAmount(type(uint256).max);
        assertEq(p, 150);
        assertEq(t, 5);
        assertTrue(q);
    }

    function test_DailyCapForTier_Table() public view {
        assertEq(sp.dailyCapForTier(0), 50);
        assertEq(sp.dailyCapForTier(1), 75);
        assertEq(sp.dailyCapForTier(2), 100);
        assertEq(sp.dailyCapForTier(3), 150);
        assertEq(sp.dailyCapForTier(4), 200);
        assertEq(sp.dailyCapForTier(5), 600);
        assertEq(sp.dailyCapForTier(6), 600, "clamps");
        assertEq(sp.dailyCapForTier(255), 600, "clamps");
    }

    // ───────────── depositToSplit (gross amount) ─────────────

    function test_Deposit_EveryBoundary() public {
        for (uint256 i = 0; i < 12; ++i) {
            StrPoints p = _newPoints(DAY); // fresh state per boundary
            uint256 amt = AMTS[i];
            _fund(dave, amt, address(p));
            uint256 v = factory.splitVersion(id);
            vm.expectEmit(true, false, false, true, address(p));
            if (EQ[i]) emit StrPoints.PointsAwarded(dave, EP[i], 1);
            else emit StrPoints.PointsSkipped(dave, 1, 1);
            vm.prank(dave);
            p.depositToSplit(id, amt, v);
            assertEq(p.pointsOf(dave), EP[i], "points");
            assertEq(p.userCount(), EQ[i] ? 1 : 0, "registration iff points>0");
            _assertStatus(p, dave, EP[i], _refCap(ET[i]), ET[i], EQ[i]);
            _assertClean(p);
        }
    }

    function test_Deposit_BelowOneUsdc_NoRegistrationNoTier() public {
        _mintDep(sp, dave, id, 999_999);
        assertEq(sp.pointsOf(dave), 0);
        assertEq(sp.userCount(), 0);
        _assertStatus(sp, dave, 0, 50, 0, false);
        (address[] memory us,) = sp.getUsers(0, 10);
        assertEq(us.length, 0);
    }

    function test_Deposit_BelowOneUsdc_DoesNotChangeExistingTier() public {
        _mintDep(sp, dave, id, A3); // tier 3
        _assertStatus(sp, dave, 75, 150, 3, true);
        _mintDep(sp, dave, id, 999_999);
        _assertStatus(sp, dave, 75, 150, 3, true);
        assertEq(sp.pointsOf(dave), 75);
    }

    function test_Deposit_BelowOneUsdc_DoesNotCountAsTierZero() public {
        _mintDep(sp, dave, id, 500_000);
        (,, uint8 t, bool h) = sp.activityStatus(dave);
        assertEq(t, 0);
        assertFalse(h, "no tier recorded");
        // A later 1-USDC action is the first to set the tier
        _mintDep(sp, dave, id, A0);
        _assertStatus(sp, dave, 5, 50, 0, true);
    }

    // ───────────── distribute (pre-distribution split balance) ─────────────

    function test_Distribute_EveryBoundary() public {
        vm.prank(owner);
        factory.setFeeBps(0); // net == gross so the balance hits the exact threshold
        for (uint256 i = 0; i < 12; ++i) {
            StrPoints p = _newPoints(DAY);
            uint256 sid = _createDefault();
            _directDeposit(sid, AMTS[i]);
            assertEq(factory.splitBalance(sid), AMTS[i]);
            vm.expectEmit(true, false, false, true, address(p));
            if (EQ[i]) emit StrPoints.PointsAwarded(eve, EP[i], 2);
            else emit StrPoints.PointsSkipped(eve, 2, 1);
            _distViaPoints(p, eve, sid);
            assertEq(factory.splitBalance(sid), 0, "distributed");
            assertEq(p.pointsOf(eve), EP[i], "points");
            assertEq(p.userCount(), EQ[i] ? 1 : 0, "registration iff points>0");
            _assertStatus(p, eve, EP[i], _refCap(ET[i]), ET[i], EQ[i]);
            _assertClean(p);
        }
    }

    function test_Distribute_UsesNetBalance_LowerTierThanGross() public {
        // gross 100 USDC (tier 3) -> fee 0.5 -> net 99.5 USDC (tier 2)
        _mintDep(sp, dave, id, A3);
        assertEq(sp.pointsOf(dave), 75, "deposit uses gross");
        assertEq(factory.splitBalance(id), 99_500_000);
        _distViaPoints(sp, eve, id);
        assertEq(sp.pointsOf(eve), 50, "distribute uses net");
        _assertStatus(sp, eve, 50, 100, 2, true);
    }

    function test_Distribute_NetBelowOneUsdc_GrossAbove_Skipped() public {
        // gross exactly 1 USDC (tier 0) -> net 995_000 (< 1 USDC)
        _mintDep(sp, dave, id, A0);
        assertEq(sp.pointsOf(dave), 5);
        assertEq(factory.splitBalance(id), 995_000);
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.PointsSkipped(eve, 2, 1);
        _distViaPoints(sp, eve, id);
        assertEq(sp.pointsOf(eve), 0);
        assertEq(sp.userCount(), 1, "eve not registered");
        _assertStatus(sp, eve, 0, 50, 0, false);
        assertEq(factory.splitBalance(id), 0, "distribution still succeeded");
        assertGt(usdc.balanceOf(bob), 0);
    }

    function test_Distribute_NetLandsInLowerTier_AcrossEachBoundary() public {
        // gross at each threshold -> net (fee 0.5%) falls in the tier below
        uint256[5] memory gross = [A1, A2, A3, A4, A5];
        uint256[5] memory expPts = [uint256(5), 25, 50, 75, 100];
        for (uint256 i = 0; i < 5; ++i) {
            StrPoints p = _newPoints(DAY);
            uint256 sid = _createDefault();
            _mintDep(p, dave, sid, gross[i]);
            _distViaPoints(p, eve, sid);
            assertEq(p.pointsOf(eve), expPts[i], "net tier");
        }
    }

    function test_Distribute_NetAboveThreshold_SameTier() public {
        // gross 101 USDC -> net 100.495 USDC, still tier 3
        _mintDep(sp, dave, id, 101e6);
        _distViaPoints(sp, eve, id);
        assertEq(sp.pointsOf(eve), 75);
    }

    function test_Distribute_AggregatesMultipleDeposits() public {
        vm.prank(owner);
        factory.setFeeBps(0);
        _directDeposit(id, 600_000);
        _directDeposit(id, 600_000);
        _distViaPoints(sp, eve, id); // balance 1.2 USDC
        assertEq(sp.pointsOf(eve), 5);
    }

    function test_Distribute_BelowOne_DoesNotChangeTier() public {
        _mintDep(sp, dave, id, A4); // dave: tier 4
        _distViaPoints(sp, dave, id); // net 248.75 -> tier 3 (75) ; tier stays 4
        _assertStatus(sp, dave, 175, 200, 4, true);
        _directDeposit(id, 500_000);
        _distViaPoints(sp, dave, id); // below 1 USDC
        _assertStatus(sp, dave, 175, 200, 4, true);
        assertEq(sp.pointsOf(dave), 175);
    }

    function test_FailedActions_AwardNothing() public {
        // distribute with no balance
        vm.expectRevert(bytes4(keccak256("NoBalance()")));
        _distViaPoints(sp, eve, id);
        // stale-version deposit
        usdc.mint(dave, A5);
        vm.prank(dave);
        usdc.approve(address(sp), type(uint256).max);
        vm.expectRevert(bytes4(keccak256("ConfigChanged()")));
        vm.prank(dave);
        sp.depositToSplit(id, A5, 99);
        assertEq(sp.userCount(), 0);
        _assertStatus(sp, dave, 0, 50, 0, false);
        _assertStatus(sp, eve, 0, 50, 0, false);
        assertEq(usdc.balanceOf(dave), A5);
        _assertClean(sp);
    }

    function test_FailedAction_DoesNotRaiseTier() public {
        _mintDep(sp, dave, id, A0);
        usdc.mint(dave, A5);
        vm.expectRevert(bytes4(keccak256("ConfigChanged()")));
        vm.prank(dave);
        sp.depositToSplit(id, A5, 99); // would be tier 5
        _assertStatus(sp, dave, 5, 50, 0, true);
    }
}
