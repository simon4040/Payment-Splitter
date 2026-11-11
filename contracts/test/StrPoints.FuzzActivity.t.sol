// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrPointsTestBase} from "./StrPoints.Base.t.sol";
import {StrPoints} from "../StrPoints.sol";
import {SplitFactory} from "../SplitFactory.sol";

/// @dev Random action sequences checked against an independent reference model.
contract StrPointsFuzzActivityTest is StrPointsTestBase {
    struct M {
        uint256 day; // day bucket of activity record
        bool hasTier;
        uint8 tier;
        uint256 earned;
        uint256 total;
        // check-in model
        bool seen;
        uint256 lastDay;
        uint256 streak;
        uint256 checkInTotal;
        uint256 activityTotal;
    }

    M[2] internal m;
    address[2] internal actors;
    uint256[2] internal ids;
    StrPoints internal p;
    uint256 internal dayLen;

    /// @dev Spans sub-1-USDC, every threshold neighbourhood, and large amounts.
    function _pickAmount(uint256 r) internal pure returns (uint256) {
        uint256 k = r % 10;
        uint256 x = r >> 8;
        if (k == 0) return 1 + (x % 999_999); // below 1 USDC
        if (k == 1) return 1_000_000 + (x % 9_000_000);
        if (k == 2) return 10_000_000 + (x % 40_000_000);
        if (k == 3) return 50_000_000 + (x % 50_000_000);
        if (k == 4) return 100_000_000 + (x % 150_000_000);
        if (k == 5) return 250_000_000 + (x % 750_000_000);
        if (k == 6) return 1_000_000_000 + (x % 5_000_000_000);
        // exact thresholds +/- 1
        uint256[12] memory edges = [
            uint256(999_999), 1_000_000, 9_999_999, 10_000_000, 49_999_999, 50_000_000,
            99_999_999, 100_000_000, 249_999_999, 250_000_000, 999_999_999, 1_000_000_000
        ];
        return edges[x % 12];
    }

    function _applyActivity(uint256 a, uint256 amount) internal {
        M storage s = m[a];
        (bool q, uint8 tier, uint256 pts) = _refTier(amount);
        if (!q) return;
        uint256 day = block.timestamp / dayLen + 1;
        if (s.day != day) {
            s.day = day;
            s.hasTier = false;
            s.tier = 0;
            s.earned = 0;
        }
        if (!s.hasTier || tier > s.tier) {
            s.hasTier = true;
            s.tier = tier;
        }
        uint256 cap = _refCap(s.tier);
        uint256 rem = cap > s.earned ? cap - s.earned : 0;
        uint256 got = pts < rem ? pts : rem;
        s.earned += got;
        s.total += got;
        s.activityTotal += got;
    }

    function _applyCheckIn(uint256 a) internal returns (bool ok) {
        M storage s = m[a];
        uint256 day = block.timestamp / dayLen;
        if (s.seen && s.lastDay == day) return false;
        s.streak = (s.seen && s.lastDay + 1 == day && s.streak > 0) ? s.streak + 1 : 1;
        s.seen = true;
        s.lastDay = day;
        s.total += 5;
        s.checkInTotal += 5;
        if (s.streak == 7) {
            s.total += 25;
            s.checkInTotal += 25;
            s.streak = 0;
        }
        return true;
    }

    function _verify(uint256 a) internal view {
        M storage s = m[a];
        address who = actors[a];
        assertEq(p.pointsOf(who), s.total, "total points");
        (uint256 e, uint256 c, uint8 t, bool h) = p.activityStatus(who);
        uint256 day = block.timestamp / dayLen + 1;
        if (s.day == day) {
            assertEq(e, s.earned, "earned");
            assertEq(h, s.hasTier, "hasTier");
            assertEq(t, s.tier, "tier");
            assertEq(c, _refCap(s.tier), "cap");
        } else {
            assertEq(e, 0);
            assertEq(c, 50);
            assertEq(t, 0);
            assertFalse(h);
        }
        assertLe(e, c, "earned <= cap");
        assertEq(s.total, s.activityTotal + s.checkInTotal, "total = awards + checkins");
        assertEq(p.currentStreak(who) <= 6, true);
    }

    function testFuzz_ActivitySequence(uint256 dayLenSeed, uint256 seed, uint8 feeSel) public {
        dayLen = dayLenSeed % 2 == 0 ? 86400 : 300;
        p = _newPoints(dayLen);
        vm.warp(_start(dayLen));
        vm.prank(owner);
        factory.setFeeBps(uint16(feeSel % 3 == 0 ? 0 : (feeSel % 3 == 1 ? 50 : 500)));
        actors[0] = dave;
        actors[1] = eve;
        ids[0] = _createDefault();
        ids[1] = _createDefault();
        for (uint256 i = 0; i < 2; ++i) {
            vm.prank(actors[i]);
            usdc.approve(address(p), type(uint256).max);
        }

        for (uint256 step = 0; step < 60; ++step) {
            uint256 r = uint256(keccak256(abi.encode(seed, step)));
            uint256 a = r % 2;
            uint256 sid = ids[(r >> 1) % 2];
            uint256 op = (r >> 8) % 10;
            uint256 amount = _pickAmount(r >> 16);
            address who = actors[a];

            if (op < 4) {
                usdc.mint(who, amount);
                uint256 v = factory.splitVersion(sid);
                vm.prank(who);
                p.depositToSplit(sid, amount, v);
                _applyActivity(a, amount);
            } else if (op < 7) {
                uint256 bal = factory.splitBalance(sid);
                if (bal == 0) {
                    vm.prank(who);
                    vm.expectRevert(SplitFactory.NoBalance.selector);
                    p.distribute(sid);
                } else {
                    vm.prank(who);
                    p.distribute(sid);
                    assertEq(factory.splitBalance(sid), 0);
                    _applyActivity(a, bal);
                }
            } else if (op == 7) {
                uint256 day = block.timestamp / dayLen;
                if (m[a].seen && m[a].lastDay == day) {
                    vm.prank(who);
                    vm.expectRevert(StrPoints.AlreadyCheckedIn.selector);
                    p.checkIn();
                } else {
                    _applyCheckIn(a);
                    vm.prank(who);
                    p.checkIn();
                }
            } else {
                // warp: stay within bucket, step one bucket, or skip several
                uint256 w = (r >> 40) % 4;
                if (w == 0) vm.warp(block.timestamp + (r >> 50) % dayLen);
                else if (w == 1) vm.warp((block.timestamp / dayLen + 1) * dayLen);
                else vm.warp(block.timestamp + dayLen * (1 + (r >> 50) % 3) + (r >> 60) % dayLen);
            }
            _verify(0);
            _verify(1);
            _assertClean(p);
        }
        assertEq(p.userCount(), (m[0].total > 0 ? 1 : 0) + (m[1].total > 0 ? 1 : 0), "registered iff points > 0");
    }

    /// @dev Single action: awarded == min(tierPoints, cap(tier)) for any amount.
    function testFuzz_SingleActionAward(uint256 amount) public {
        amount = bound(amount, 1, 1e13);
        uint256 sid = _createDefault();
        _mintDep(sp, dave, sid, amount);
        (bool q, uint8 t, uint256 pts) = _refTier(amount);
        assertEq(sp.pointsOf(dave), pts);
        assertEq(sp.userCount(), q ? 1 : 0);
        (uint256 e, uint256 c, uint8 tt, bool h) = sp.activityStatus(dave);
        assertEq(e, pts);
        assertEq(h, q);
        assertEq(tt, q ? t : 0);
        assertEq(c, q ? _refCap(t) : 50);
        (uint256 pp, uint8 pt, bool pq) = sp.pointsForAmount(amount);
        assertEq(pp, pts);
        assertEq(pt, t);
        assertEq(pq, q);
        assertEq(sp.dailyCapForTier(t), _refCap(t));
    }
}
