// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrPointsTestBase} from "./StrPoints.Base.t.sol";
import {StrPoints} from "../StrPoints.sol";

contract StrPointsCheckInTest is StrPointsTestBase {
    uint256 internal T0;

    function setUp() public override {
        super.setUp();
        T0 = _start(DAY);
    }

    function _warpDay(StrPoints p, uint256 dayOffset) internal {
        vm.warp(_start(p.dayLength()) + dayOffset * p.dayLength());
    }

    // ───────────── basic ─────────────

    function test_CheckIn_FirstAwardsFive() public {
        _checkIn(sp, alice);
        assertEq(sp.pointsOf(alice), 5);
        assertEq(sp.currentStreak(alice), 1);
        assertEq(sp.userCount(), 1);
    }

    function test_CheckIn_EmitsEvents() public {
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.PointsAwarded(alice, 5, 3);
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.CheckedIn(alice, 1, false);
        _checkIn(sp, alice);
    }

    function test_CheckIn_RevertsSameDay() public {
        _checkIn(sp, alice);
        vm.expectRevert(StrPoints.AlreadyCheckedIn.selector);
        _checkIn(sp, alice);
        vm.warp(T0 + DAY - 1); // last second of same day
        vm.expectRevert(StrPoints.AlreadyCheckedIn.selector);
        _checkIn(sp, alice);
        assertEq(sp.pointsOf(alice), 5);
        // next day boundary OK
        vm.warp(T0 + DAY);
        _checkIn(sp, alice);
        assertEq(sp.pointsOf(alice), 10);
    }

    function test_CheckIn_UsersIndependent() public {
        _checkIn(sp, alice);
        _checkIn(sp, bob);
        assertEq(sp.pointsOf(alice), 5);
        assertEq(sp.pointsOf(bob), 5);
    }

    function test_CheckIn_MidDayTimestampsSameBucket() public {
        vm.warp(T0 + 100);
        _checkIn(sp, alice);
        vm.warp(T0 + 80_000);
        vm.expectRevert(StrPoints.AlreadyCheckedIn.selector);
        _checkIn(sp, alice);
        // next bucket even though < 24h since previous check-in
        vm.warp(T0 + DAY + 5);
        _checkIn(sp, alice);
        assertEq(sp.currentStreak(alice), 2);
    }

    function test_CheckIn_ConsecutiveDaysIncrementStreak() public {
        for (uint256 d = 0; d < 5; ++d) {
            _warpDay(sp, d);
            _checkIn(sp, alice);
            assertEq(sp.currentStreak(alice), d + 1);
        }
        assertEq(sp.pointsOf(alice), 25);
    }

    // ───────────── 7-day run (parametrised by dayLength) ─────────────

    function _fullRun(StrPoints p, address who) internal {
        for (uint256 d = 0; d < 6; ++d) {
            _warpDay(p, d);
            _checkIn(p, who);
            assertEq(p.pointsOf(who), (d + 1) * 5);
            assertEq(p.currentStreak(who), d + 1);
        }
        _warpDay(p, 6);
        vm.expectEmit(true, false, false, true, address(p));
        emit StrPoints.PointsAwarded(who, 5, 3);
        vm.expectEmit(true, false, false, true, address(p));
        emit StrPoints.PointsAwarded(who, 25, 4);
        vm.expectEmit(true, false, false, true, address(p));
        emit StrPoints.CheckedIn(who, 7, true);
        _checkIn(p, who);
        assertEq(p.pointsOf(who), 60);
        assertEq(p.currentStreak(who), 0, "stored streak reset");
    }

    function test_SevenDayRun_Bonus() public {
        _fullRun(sp, alice);
    }

    function test_SevenDayRun_Bonus_ShortDay() public {
        StrPoints p = _newPoints(300);
        _fullRun(p, alice);
    }

    function test_SevenDayRun_SecondCheckInOnBonusDayReverts() public {
        _fullRun(sp, alice);
        vm.expectRevert(StrPoints.AlreadyCheckedIn.selector);
        _checkIn(sp, alice);
        assertEq(sp.pointsOf(alice), 60);
    }

    function test_AfterBonus_NextDayStartsAtOne() public {
        _fullRun(sp, alice);
        _warpDay(sp, 7);
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.CheckedIn(alice, 1, false);
        _checkIn(sp, alice);
        assertEq(sp.pointsOf(alice), 65);
        assertEq(sp.currentStreak(alice), 1);
    }

    function test_TwoFullCycles_FourteenDays() public {
        for (uint256 d = 0; d < 14; ++d) {
            _warpDay(sp, d);
            _checkIn(sp, alice);
        }
        assertEq(sp.pointsOf(alice), 120);
        assertEq(sp.currentStreak(alice), 0);
    }

    // ───────────── misses ─────────────

    function test_Miss_AtDay2_ResetsToOne() public {
        _warpDay(sp, 0);
        _checkIn(sp, alice); // streak 1
        _warpDay(sp, 2); // skipped day 1
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.CheckedIn(alice, 1, false);
        _checkIn(sp, alice);
        assertEq(sp.currentStreak(alice), 1);
        assertEq(sp.pointsOf(alice), 10);
    }

    function test_Miss_AtDay6_NoBonusOnDay7() public {
        for (uint256 d = 0; d < 6; ++d) {
            _warpDay(sp, d);
            _checkIn(sp, alice);
        }
        assertEq(sp.currentStreak(alice), 6);
        // skip day 6, return day 7 -> would have been 7th check-in in a row
        _warpDay(sp, 7);
        assertEq(sp.currentStreak(alice), 0);
        vm.expectEmit(true, false, false, true, address(sp));
        emit StrPoints.CheckedIn(alice, 1, false);
        _checkIn(sp, alice);
        assertEq(sp.pointsOf(alice), 35); // 7 check-ins x 5, no bonus
        assertEq(sp.currentStreak(alice), 1);
    }

    function test_Miss_AfterBonusDay_StartsAtOne() public {
        _fullRun(sp, alice);
        _warpDay(sp, 8); // skipped day 7
        _checkIn(sp, alice);
        assertEq(sp.pointsOf(alice), 65);
        assertEq(sp.currentStreak(alice), 1);
        // continue 6 more days -> bonus on the 7th of the new run
        for (uint256 d = 9; d < 15; ++d) {
            _warpDay(sp, d);
            _checkIn(sp, alice);
        }
        assertEq(sp.pointsOf(alice), 65 + 6 * 5 + 25);
        assertEq(sp.currentStreak(alice), 0);
    }

    function test_Miss_LongGap_ResetsToOne() public {
        _warpDay(sp, 0);
        _checkIn(sp, alice);
        _warpDay(sp, 500);
        _checkIn(sp, alice);
        assertEq(sp.currentStreak(alice), 1);
        assertEq(sp.pointsOf(alice), 10);
    }

    function test_Miss_ShortDay() public {
        StrPoints p = _newPoints(300);
        _warpDay(p, 0);
        _checkIn(p, alice);
        vm.warp(block.timestamp + 600); // two buckets later
        _checkIn(p, alice);
        assertEq(p.currentStreak(alice), 1);
        vm.warp(block.timestamp + 300); // next bucket
        _checkIn(p, alice);
        assertEq(p.currentStreak(alice), 2);
    }

    // ───────────── status views ─────────────

    function test_Status_Fresh() public view {
        (uint256 pts, uint8 streak, bool can, uint256 wait) = sp.checkInStatus(alice);
        assertEq(pts, 0);
        assertEq(streak, 0);
        assertTrue(can);
        assertEq(wait, 0);
        assertEq(sp.currentStreak(alice), 0);
    }

    function test_Status_AfterCheckIn() public {
        vm.warp(T0 + 100);
        _checkIn(sp, alice);
        (uint256 pts, uint8 streak, bool can, uint256 wait) = sp.checkInStatus(alice);
        assertEq(pts, 5);
        assertEq(streak, 1);
        assertFalse(can);
        assertEq(wait, DAY - 100);

        vm.warp(T0 + DAY - 1);
        (,, can, wait) = sp.checkInStatus(alice);
        assertFalse(can);
        assertEq(wait, 1);
    }

    function test_Status_NextDayAliveThenDead() public {
        _checkIn(sp, alice);
        vm.warp(T0 + DAY); // yesterday check-in: streak alive, can check in
        (, uint8 streak, bool can, uint256 wait) = sp.checkInStatus(alice);
        assertEq(streak, 1);
        assertTrue(can);
        assertEq(wait, 0);
        assertEq(sp.currentStreak(alice), 1);

        vm.warp(T0 + DAY * 2); // missed a whole day
        (, streak, can, wait) = sp.checkInStatus(alice);
        assertEq(streak, 0);
        assertTrue(can);
        assertEq(wait, 0);
        assertEq(sp.currentStreak(alice), 0);
    }

    function test_Status_AfterBonusDay() public {
        _fullRun(sp, alice);
        (uint256 pts, uint8 streak, bool can, uint256 wait) = sp.checkInStatus(alice);
        assertEq(pts, 60);
        assertEq(streak, 0);
        assertFalse(can);
        assertEq(wait, DAY);
    }

    function test_Status_ShortDay() public {
        StrPoints p = _newPoints(300);
        vm.warp(_start(300) + 120);
        _checkIn(p, alice);
        (,, bool can, uint256 wait) = p.checkInStatus(alice);
        assertFalse(can);
        assertEq(wait, 180);
    }

    function test_Status_PointsFromOtherActions() public {
        // points accrued via deposit show in status
        vm.prank(alice);
        uint256 id = factory.createSplit(_a2(bob, carol), _b2(6000, 4000));
        _fund(dave, 10 * UNIT, address(sp));
        _depViaPoints(sp, dave, id, 10 * UNIT);
        (uint256 pts, uint8 streak, bool can,) = sp.checkInStatus(dave);
        assertEq(pts, 25); // 10 USDC deposit -> tier 1
        assertEq(streak, 0);
        assertTrue(can);
    }

    // ───────────── day 0 edge (timestamp < dayLength) ─────────────

    function test_CheckIn_AtDayZero() public {
        vm.warp(1);
        _checkIn(sp, alice);
        assertEq(sp.pointsOf(alice), 5);
        vm.expectRevert(StrPoints.AlreadyCheckedIn.selector);
        _checkIn(sp, alice);
        vm.warp(DAY); // day 1
        _checkIn(sp, alice);
        assertEq(sp.currentStreak(alice), 2);
    }
}
