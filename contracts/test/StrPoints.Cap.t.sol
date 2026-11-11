// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrPointsTestBase} from "./StrPoints.Base.t.sol";
import {StrPoints} from "../StrPoints.sol";

/// @dev Tier-dependent shared daily cap for deposits + distributions; check-ins are outside the cap.
contract StrPointsCapTest is StrPointsTestBase {
    uint256 internal id;

    function setUp() public override {
        super.setUp();
        id = _createDefault();
    }

    function _amt(uint8 t) internal pure returns (uint256) {
        uint256[6] memory a = [A0, A1, A2, A3, A4, A5];
        return a[t];
    }

    function _d(address who, uint8 tier) internal {
        _mintDep(sp, who, id, _amt(tier));
    }

    /// @dev Deposit that is expected to be skipped due to the cap (cause 2) yet still succeed.
    function _depositExpectCapSkip(StrPoints p, address who, uint256 sid, uint256 amount) internal {
        usdc.mint(who, amount);
        vm.prank(who);
        usdc.approve(address(p), type(uint256).max);
        uint256 v = factory.splitVersion(sid);
        uint256 balBefore = factory.splitBalance(sid);
        uint256 ptsBefore = p.pointsOf(who);
        vm.expectEmit(true, false, false, true, address(p));
        emit StrPoints.PointsSkipped(who, 1, 2);
        vm.prank(who);
        p.depositToSplit(sid, amount, v);
        assertEq(p.pointsOf(who), ptsBefore, "no points at cap");
        assertGt(factory.splitBalance(sid), balBefore, "deposit still succeeded");
    }

    // ───────────── fresh / status ─────────────

    function test_ActivityStatus_Fresh() public view {
        _assertStatus(sp, dave, 0, 50, 0, false);
    }

    function test_ActivityStatus_AfterActivity() public {
        _d(dave, 2);
        _assertStatus(sp, dave, 50, 100, 2, true);
        // other wallets unaffected
        _assertStatus(sp, eve, 0, 50, 0, false);
    }

    function test_ActivityStatus_AfterTier0Action() public {
        _d(dave, 0);
        _assertStatus(sp, dave, 5, 50, 0, true);
    }

    // ───────────── reaching the cap at each tier ─────────────

    function test_Deposit_ReachCapAtEachTier() public {
        uint16[6] memory caps = [uint16(50), 75, 100, 150, 200, 600];
        uint16[6] memory pts = [uint16(5), 25, 50, 75, 100, 150];
        for (uint8 k = 0; k < 6; ++k) {
            StrPoints p = _newPoints(DAY);
            uint256 sid = _createDefault();
            for (uint256 n = 0; n < caps[k] / pts[k]; ++n) {
                _mintDep(p, dave, sid, _amt(k));
            }
            assertEq(p.pointsOf(dave), caps[k], "reached cap");
            _assertStatus(p, dave, caps[k], caps[k], k, true);
            _depositExpectCapSkip(p, dave, sid, _amt(k));
            _assertStatus(p, dave, caps[k], caps[k], k, true);
            assertEq(p.userCount(), 1);
            _assertClean(p);
        }
    }

    function test_Distribute_ReachCapAtEachTier() public {
        vm.prank(owner);
        factory.setFeeBps(0);
        uint16[6] memory caps = [uint16(50), 75, 100, 150, 200, 600];
        uint16[6] memory pts = [uint16(5), 25, 50, 75, 100, 150];
        for (uint8 k = 0; k < 6; ++k) {
            StrPoints p = _newPoints(DAY);
            uint256 sid = _createDefault();
            for (uint256 n = 0; n < caps[k] / pts[k]; ++n) {
                _directDeposit(sid, _amt(k));
                _distViaPoints(p, eve, sid);
            }
            assertEq(p.pointsOf(eve), caps[k], "reached cap");
            _assertStatus(p, eve, caps[k], caps[k], k, true);
            _directDeposit(sid, _amt(k));
            vm.expectEmit(true, false, false, true, address(p));
            emit StrPoints.PointsSkipped(eve, 2, 2);
            _distViaPoints(p, eve, sid);
            assertEq(factory.splitBalance(sid), 0, "distribution still succeeded");
            assertEq(p.pointsOf(eve), caps[k]);
            _assertClean(p);
        }
    }

    function test_Tier5_EarnsUpTo600() public {
        for (uint256 n = 0; n < 4; ++n) {
            _d(dave, 5);
        }
        assertEq(sp.pointsOf(dave), 600);
        _assertStatus(sp, dave, 600, 600, 5, true);
        _depositExpectCapSkip(sp, dave, id, A5);
        assertEq(sp.pointsOf(dave), 600);
    }

    function test_BigTransactionRaisesOwnCap() public {
        // a single 150-point action exceeds the base cap of 50 because the tier is raised first
        _d(dave, 5);
        assertEq(sp.pointsOf(dave), 150);
        _assertStatus(sp, dave, 150, 600, 5, true);
    }

    // ───────────── partial awards ─────────────

    function test_Partial_Tier1_Awards5Of25() public {
        _d(dave, 1); // 25
        for (uint256 i = 0; i < 9; ++i) {
            _d(dave, 0); // +45 -> 70
        }
        assertEq(sp.pointsOf(dave), 70);
        uint256 v = factory.splitVersion(id);
        _fund(dave, A1, address(sp));
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.PointsAwarded(dave, 5, 1);
        vm.prank(dave);
        sp.depositToSplit(id, A1, v);
        assertEq(sp.pointsOf(dave), 75);
        _assertStatus(sp, dave, 75, 75, 1, true);
        _depositExpectCapSkip(sp, dave, id, A1);
    }

    function test_Partial_Tier3_Awards5Of25() public {
        _d(dave, 3); // 75
        _d(dave, 2); // 125
        for (uint256 i = 0; i < 4; ++i) {
            _d(dave, 0); // 145
        }
        assertEq(sp.pointsOf(dave), 145);
        uint256 v = factory.splitVersion(id);
        _fund(dave, A1, address(sp));
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.PointsAwarded(dave, 5, 1);
        vm.prank(dave);
        sp.depositToSplit(id, A1, v);
        assertEq(sp.pointsOf(dave), 150);
        _assertStatus(sp, dave, 150, 150, 3, true);
    }

    function test_Partial_Tier4_Awards50Of100() public {
        _d(dave, 5); // 150, cap 600
        _d(dave, 5);
        _d(dave, 5); // 450
        _d(dave, 4); // 550
        assertEq(sp.pointsOf(dave), 550);
        uint256 v = factory.splitVersion(id);
        _fund(dave, A4, address(sp));
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.PointsAwarded(dave, 50, 1);
        vm.prank(dave);
        sp.depositToSplit(id, A4, v);
        assertEq(sp.pointsOf(dave), 600);
    }

    function test_Partial_OnDistribution() public {
        _d(dave, 3); // 75
        _d(dave, 2); // 125
        for (uint256 i = 0; i < 4; ++i) {
            _d(dave, 0); // 145
        }
        _distViaPoints(sp, eve, id); // drain: eve gets points for big net balance
        uint256 sid = _createDefault();
        _directDeposit(sid, 20e6); // net 19.9e6 -> tier 1 -> 25 pts
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.PointsAwarded(dave, 5, 2);
        _distViaPoints(sp, dave, sid);
        assertEq(sp.pointsOf(dave), 150);
        _assertStatus(sp, dave, 150, 150, 3, true);
    }

    // ───────────── tier transitions ─────────────

    function test_TierUpgradeMidDay_RaisesCap() public {
        for (uint256 i = 0; i < 10; ++i) {
            _d(dave, 0);
        }
        assertEq(sp.pointsOf(dave), 50);
        _depositExpectCapSkip(sp, dave, id, A0);

        _d(dave, 1); // tier 1 -> cap 75, awards full 25
        assertEq(sp.pointsOf(dave), 75);
        _assertStatus(sp, dave, 75, 75, 1, true);
        _depositExpectCapSkip(sp, dave, id, A0);

        _d(dave, 3); // tier 3 -> cap 150, awards full 75
        assertEq(sp.pointsOf(dave), 150);
        _assertStatus(sp, dave, 150, 150, 3, true);

        _d(dave, 5); // tier 5 -> cap 600, awards full 150
        assertEq(sp.pointsOf(dave), 300);
        _assertStatus(sp, dave, 300, 600, 5, true);
    }

    function test_TierUpgrade_FromPartialEarned_NoPartialNeeded() public {
        for (uint256 i = 0; i < 9; ++i) {
            _d(dave, 0); // 45
        }
        _d(dave, 1); // would exceed 50 but tier raised first -> full 25
        assertEq(sp.pointsOf(dave), 70);
        _assertStatus(sp, dave, 70, 75, 1, true);
    }

    function test_LowerTierAfterHigher_KeepsHigherCap() public {
        _d(dave, 4); // 100, cap 200
        _d(dave, 0); // +5
        _assertStatus(sp, dave, 105, 200, 4, true);
        _d(dave, 1);
        _assertStatus(sp, dave, 130, 200, 4, true);
    }

    function test_DepositsAndDistributionsShareCap() public {
        _d(dave, 2); // 50, tier 2 (cap 100)
        _distViaPoints(sp, dave, id); // net 49.75e6 -> tier 1 -> 25
        assertEq(sp.pointsOf(dave), 75);
        _d(dave, 2); // partial: 25 of 50
        assertEq(sp.pointsOf(dave), 100);
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.PointsSkipped(dave, 2, 2);
        _distViaPoints(sp, dave, id);
        assertEq(sp.pointsOf(dave), 100);
        assertEq(factory.splitBalance(id), 0);
        _assertStatus(sp, dave, 100, 100, 2, true);
    }

    function test_CapIsPerWallet() public {
        for (uint256 i = 0; i < 10; ++i) {
            _d(dave, 0);
        }
        _d(eve, 0);
        assertEq(sp.pointsOf(dave), 50);
        assertEq(sp.pointsOf(eve), 5);
    }

    // ───────────── day bucket reset ─────────────

    function _resetScenario(uint256 dayLen) internal {
        StrPoints p = _newPoints(dayLen);
        uint256 sid = _createDefault();
        uint256 t0 = _start(dayLen);
        vm.warp(t0);
        _mintDep(p, dave, sid, A2);
        _mintDep(p, dave, sid, A2);
        _assertStatus(p, dave, 100, 100, 2, true);

        vm.warp(t0 + dayLen - 1); // same bucket
        _assertStatus(p, dave, 100, 100, 2, true);
        _depositExpectCapSkip(p, dave, sid, A0);

        vm.warp(t0 + dayLen); // next bucket: all reset
        _assertStatus(p, dave, 0, 50, 0, false);
        _mintDep(p, dave, sid, A0);
        _assertStatus(p, dave, 5, 50, 0, true); // tier reset to 0
        assertEq(p.pointsOf(dave), 105);

        vm.warp(t0 + 5 * dayLen + 7); // skip several buckets
        _assertStatus(p, dave, 0, 50, 0, false);
        _mintDep(p, dave, sid, A3);
        _assertStatus(p, dave, 75, 150, 3, true);
        assertEq(p.pointsOf(dave), 180);

        // returning to a tier-0 action the next bucket must use the base cap again
        vm.warp(t0 + 6 * dayLen);
        for (uint256 i = 0; i < 10; ++i) {
            _mintDep(p, dave, sid, A0);
        }
        _assertStatus(p, dave, 50, 50, 0, true);
        _depositExpectCapSkip(p, dave, sid, A0);
        assertEq(p.pointsOf(dave), 230);
    }

    function test_DayReset_Day86400() public {
        _resetScenario(86400);
    }

    function test_DayReset_Day300() public {
        _resetScenario(300);
    }

    function test_DayReset_DistributionAlsoResets() public {
        vm.prank(owner);
        factory.setFeeBps(0);
        _directDeposit(id, A4);
        _distViaPoints(sp, eve, id); // 100
        _directDeposit(id, A4);
        _distViaPoints(sp, eve, id); // 200 at cap
        _directDeposit(id, A0);
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.PointsSkipped(eve, 2, 2);
        _distViaPoints(sp, eve, id);
        vm.warp(block.timestamp + DAY);
        _directDeposit(id, A0);
        _distViaPoints(sp, eve, id);
        assertEq(sp.pointsOf(eve), 205);
        _assertStatus(sp, eve, 5, 50, 0, true);
    }

    // ───────────── check-ins are outside the cap ─────────────

    function test_CheckIn_WorksAtCap_AndDoesNotTouchActivity() public {
        for (uint256 i = 0; i < 10; ++i) {
            _d(dave, 0);
        }
        _assertStatus(sp, dave, 50, 50, 0, true);
        _checkIn(sp, dave);
        assertEq(sp.pointsOf(dave), 55);
        _assertStatus(sp, dave, 50, 50, 0, true);
    }

    function test_CheckIn_DoesNotConsumeActivityBudget() public {
        _checkIn(sp, dave);
        for (uint256 i = 0; i < 10; ++i) {
            _d(dave, 0);
        }
        assertEq(sp.pointsOf(dave), 55, "5 checkin + full 50 activity");
    }

    function test_SevenDays_CheckInsAlone_6x5Plus5Plus25() public {
        for (uint256 d = 0; d < 7; ++d) {
            vm.warp(_start(DAY) + d * DAY);
            _checkIn(sp, dave);
        }
        assertEq(sp.pointsOf(dave), 6 * 5 + 5 + 25);
        _assertStatus(sp, dave, 0, 50, 0, false);
    }

    function test_SevenDays_AtCapEveryDay_StillGetsFullCheckInRewards() public {
        for (uint256 d = 0; d < 7; ++d) {
            vm.warp(_start(DAY) + d * DAY);
            for (uint256 i = 0; i < 10; ++i) {
                _d(dave, 0);
            }
            _depositExpectCapSkip(sp, dave, id, A0);
            _checkIn(sp, dave);
        }
        assertEq(sp.pointsOf(dave), 7 * 50 + 6 * 5 + 5 + 25);
        assertEq(sp.currentStreak(dave), 0);
    }
}
