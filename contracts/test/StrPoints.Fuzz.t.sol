// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrPointsTestBase} from "./StrPoints.Base.t.sol";
import {StrPoints} from "../StrPoints.sol";

contract StrPointsFuzzTest is StrPointsTestBase {
    /// @dev Random sequence of time gaps: points never decrease, stored streak <= 6,
    ///      and points match an independent reference model.
    function testFuzz_CheckInSequence(uint256 dayLen, uint32[] calldata gaps) public {
        dayLen = bound(dayLen, 1, 7 days);
        StrPoints p = _newPoints(dayLen);
        uint256 ts = _start(dayLen);
        vm.warp(ts);

        // reference model
        bool seen;
        uint256 lastDay;
        uint256 streak;
        uint256 expectedPts;
        uint256 prevPts;

        uint256 n = gaps.length > 40 ? 40 : gaps.length;
        for (uint256 i = 0; i < n; ++i) {
            ts += bound(gaps[i], 0, 3 * dayLen);
            vm.warp(ts);
            uint256 day = ts / dayLen;

            if (seen && lastDay == day) {
                vm.expectRevert(StrPoints.AlreadyCheckedIn.selector);
                _checkIn(p, alice);
                (, , bool can,) = p.checkInStatus(alice);
                assertFalse(can);
            } else {
                streak = (seen && lastDay + 1 == day && streak > 0) ? streak + 1 : 1;
                seen = true;
                lastDay = day;
                expectedPts += 5;
                if (streak == 7) {
                    expectedPts += 25;
                    streak = 0;
                }
                (, , bool can,) = p.checkInStatus(alice);
                assertTrue(can);
                _checkIn(p, alice);
            }

            uint256 pts = p.pointsOf(alice);
            assertGe(pts, prevPts, "points decreased");
            assertEq(pts, expectedPts, "model mismatch");
            assertLe(p.currentStreak(alice), 6, "stored streak > 6");
            assertEq(p.currentStreak(alice), streak, "streak mismatch");
            prevPts = pts;
        }
    }

    /// @dev A perfect streak of N consecutive days yields 5N + 25*floor(N/7).
    function testFuzz_ConsecutiveDaysTotal(uint256 dayLen, uint8 nDays) public {
        dayLen = bound(dayLen, 1, 7 days);
        uint256 n = bound(nDays, 1, 100);
        StrPoints p = _newPoints(dayLen);
        for (uint256 d = 0; d < n; ++d) {
            vm.warp(_start(dayLen) + d * dayLen + (d % dayLen));
            _checkIn(p, alice);
        }
        assertEq(p.pointsOf(alice), 5 * n + 25 * (n / 7));
        assertEq(p.currentStreak(alice), n % 7);
    }

    /// @dev Fee + net == amount, StrPoints holds nothing, fuzzed amount and fee rate.
    function testFuzz_DepositConservesFunds(uint256 amount, uint16 feeBps) public {
        amount = bound(amount, 1, 1e15 * UNIT);
        feeBps = uint16(bound(feeBps, 0, 500));
        vm.prank(owner);
        factory.setFeeBps(feeBps);

        uint256 id = _createDefault();
        _fund(dave, amount, address(sp));

        _depViaPoints(sp, dave, id, amount);

        uint256 fee = usdc.balanceOf(feeRecipient);
        uint256 net = factory.splitBalance(id);
        assertEq(fee, amount * feeBps / 10_000, "fee");
        assertEq(fee + net, amount, "fee+net");
        assertEq(usdc.balanceOf(address(factory)), net, "factory holds net");
        assertEq(usdc.balanceOf(dave), 0, "depositor drained exactly amount");
        assertEq(usdc.balanceOf(address(sp)), 0, "sp balance");
        assertEq(usdc.allowance(address(sp), address(factory)), 0, "allowance");
        (bool q,, uint256 pts) = _refTier(amount);
        assertEq(sp.pointsOf(dave), pts, "points follow gross tier");
        assertEq(sp.userCount(), q ? 1 : 0);
    }

    /// @dev Deposit then distribute pays out everything; nothing stuck in StrPoints.
    function testFuzz_DepositDistributeConserves(uint256 amount) public {
        amount = bound(amount, 1, 1e15 * UNIT);
        uint256 id = _createDefault();
        _fund(dave, amount, address(sp));
        _depViaPoints(sp, dave, id, amount);

        uint256 net = factory.splitBalance(id);
        if (net == 0) return;
        vm.prank(eve);
        sp.distribute(id);

        uint256 fee = usdc.balanceOf(feeRecipient);
        uint256 paid = usdc.balanceOf(bob) + usdc.balanceOf(carol) + usdc.balanceOf(alice); // alice = creator (dust)
        assertEq(fee + paid, amount, "all funds accounted");
        assertEq(usdc.balanceOf(address(sp)), 0);
        assertEq(usdc.balanceOf(address(factory)), 0);
        // distribute points depend on the pre-distribution (net-of-fee) balance
        (, , uint256 pts) = _refTier(net);
        assertEq(sp.pointsOf(eve), pts, "distribute points follow NET balance tier");
    }

    /// @dev Pagination always returns min(limit, max(0,len-offset)) users.
    function testFuzz_GetUsersPagination(uint8 count, uint256 offset, uint256 limit) public {
        count = uint8(bound(count, 0, 40));
        for (uint256 i = 0; i < count; ++i) {
            _checkIn(sp, address(uint160(0x5000 + i)));
        }
        offset = bound(offset, 0, 100);
        limit = bound(limit, 0, 100);
        (address[] memory us, uint256[] memory pts) = sp.getUsers(offset, limit);
        uint256 expected = offset >= count ? 0 : (limit < count - offset ? limit : count - offset);
        assertEq(us.length, expected);
        assertEq(pts.length, expected);
        for (uint256 i = 0; i < us.length; ++i) {
            assertEq(us[i], address(uint160(0x5000 + offset + i)));
            assertEq(pts[i], 5);
        }
    }
}
