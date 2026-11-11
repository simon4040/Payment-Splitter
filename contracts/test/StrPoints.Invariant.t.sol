// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrPointsTestBase, StrPointsRef} from "./StrPoints.Base.t.sol";
import {StrPoints} from "../StrPoints.sol";
import {SplitFactory} from "../SplitFactory.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";
import {MockTokenMessengerV2} from "../test-helpers/MockTokenMessengerV2.sol";

contract StrPointsHandler is StrPointsRef {
    StrPoints public sp;
    SplitFactory public factory;
    MockERC20 public usdc;

    address[] public actors;
    uint256 public splitCount;
    uint256 public successfulDeposits;
    uint256 public successfulDistributes;
    uint256 public successfulCheckIns;
    uint256 public ghostDeposited;
    uint256 public successfulBridges;
    uint256 public ghostBridged;
    uint256 public ghostBurned;
    uint256 public violations; // incremented on any per-action mismatch

    uint256 public activityAwarded; // ghost: total activity points awarded
    uint256 public checkInAwarded; // ghost: total check-in points (incl. streak bonus)
    uint256 public skippedBelowMin;
    uint256 public skippedCap;
    mapping(address => mapping(uint256 => uint256)) public dayActivity;
    mapping(address => mapping(uint256 => uint256)) public dayTierEnc; // highest tier + 1

    constructor(StrPoints _sp, SplitFactory _f, MockERC20 _u, uint256 _splitCount) {
        sp = _sp;
        factory = _f;
        usdc = _u;
        splitCount = _splitCount;
        for (uint256 i = 0; i < 5; ++i) {
            address a = makeAddr(string(abi.encodePacked("actor", vm.toString(i))));
            actors.push(a);
            vm.prank(a);
            usdc.approve(address(sp), type(uint256).max);
        }
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }

    function _amount(uint256 r) internal pure returns (uint256) {
        uint256 k = r % 8;
        uint256 x = r >> 8;
        if (k == 0) return 1 + x % 999_999;
        if (k == 1) return 1_000_000 + x % 9_000_000;
        if (k == 2) return 10_000_000 + x % 40_000_000;
        if (k == 3) return 50_000_000 + x % 50_000_000;
        if (k == 4) return 100_000_000 + x % 150_000_000;
        if (k == 5) return 250_000_000 + x % 750_000_000;
        if (k == 6) return 1_000_000_000 + x % 3_000_000_000;
        return (x % 2 == 0) ? 999_999_999 : 1_000_000;
    }

    /// @dev Reference-check an activity action and record ghosts.
    function _record(address a, uint256 base, uint256 gained, uint256 beforeEarned) internal {
        (bool q, uint8 tier, uint256 pts) = _refTier(base);
        uint256 day = block.timestamp / sp.dayLength();
        uint256 expected;
        if (!q) {
            skippedBelowMin++;
        } else {
            if (tier + 1 > dayTierEnc[a][day]) dayTierEnc[a][day] = tier + 1;
            uint256 cap = _refCap(uint8(dayTierEnc[a][day] - 1));
            uint256 rem = cap > dayActivity[a][day] ? cap - dayActivity[a][day] : 0;
            expected = pts < rem ? pts : rem;
            if (expected == 0) skippedCap++;
        }
        if (gained != expected) violations++;
        dayActivity[a][day] += gained;
        activityAwarded += gained;
        if (q && dayActivity[a][day] > _refCap(uint8(dayTierEnc[a][day] - 1))) violations++;
        (uint256 e,,,) = sp.activityStatus(a);
        if (e != beforeEarned + gained && e != gained) violations++;
    }

    function deposit(uint256 actorSeed, uint256 splitSeed, uint256 amountSeed, bool stale) external {
        address a = actors[actorSeed % 2]; // few active wallets so caps are actually reached
        uint256 id = (splitSeed % splitCount) + 1;
        uint256 amount = _amount(amountSeed);
        usdc.mint(a, amount);
        uint256 v = factory.splitVersion(id) + (stale ? 1 : 0);
        uint256 before = sp.pointsOf(a);
        (uint256 earned,,,) = sp.activityStatus(a);
        vm.prank(a);
        try sp.depositToSplit(id, amount, v) {
            successfulDeposits++;
            ghostDeposited += amount;
            _record(a, amount, sp.pointsOf(a) - before, earned);
        } catch {
            if (sp.pointsOf(a) != before) violations++;
        }
    }

    function distribute(uint256 actorSeed, uint256 splitSeed) external {
        address a = actors[actorSeed % 2];
        uint256 id = (splitSeed % splitCount) + 1;
        uint256 before = sp.pointsOf(a);
        uint256 bal = factory.splitBalance(id);
        (uint256 earned,,,) = sp.activityStatus(a);
        vm.prank(a);
        try sp.distribute(id) {
            successfulDistributes++;
            if (factory.splitBalance(id) != 0) violations++;
            _record(a, bal, sp.pointsOf(a) - before, earned);
        } catch {
            if (sp.pointsOf(a) != before) violations++;
        }
    }

    function bridge(uint256 actorSeed, uint256 amountSeed, uint256 maxFeeSeed, bool fast, bool badFinality)
        external
    {
        address a = actors[actorSeed % 2];
        uint256 amount = _amount(amountSeed);
        (, uint256 burn,) = sp.previewBridge(amount);
        uint256 maxFee = maxFeeSeed % burn; // always < burn (burn >= 1)
        uint32 fin = badFinality ? 1500 : (fast ? 1000 : 2000);
        usdc.mint(a, amount);
        uint256 before = sp.pointsOf(a);
        (uint256 earned,,,) = sp.activityStatus(a);
        vm.prank(a);
        try sp.bridge(amount, maxFee, fin, a, 500) {
            if (badFinality) violations++;
            successfulBridges++;
            ghostBridged += amount;
            ghostBurned += burn;
            _record(a, amount, sp.pointsOf(a) - before, earned);
        } catch {
            if (!badFinality) violations++;
            if (sp.pointsOf(a) != before) violations++;
        }
    }

    function checkIn(uint256 actorSeed) external {
        address a = actors[actorSeed % actors.length];
        uint256 before = sp.pointsOf(a);
        (uint256 earnedBefore,,,) = sp.activityStatus(a);
        vm.prank(a);
        try sp.checkIn() {
            successfulCheckIns++;
            uint256 gained = sp.pointsOf(a) - before;
            if (gained != 5 && gained != 30) violations++;
            checkInAwarded += gained;
            (uint256 earnedAfter,,,) = sp.activityStatus(a);
            if (earnedAfter != earnedBefore) violations++;
        } catch {
            if (sp.pointsOf(a) != before) violations++;
        }
        if (sp.currentStreak(a) > 6) violations++;
    }

    function warp(uint256 secs) external {
        if (secs % 8 != 0) return; // warp rarely so many actions land in one day bucket
        secs = bound(secs, 0, 3 * sp.dayLength());
        vm.warp(block.timestamp + secs);
    }

    function totalPoints() external view returns (uint256 t) {
        for (uint256 i = 0; i < actors.length; ++i) {
            t += sp.pointsOf(actors[i]);
        }
    }
}

contract StrPointsInvariantTest is StrPointsTestBase {
    StrPointsHandler internal handler;
    StrPoints internal short;
    uint256 internal constant SPLITS = 3;

    function setUp() public override {
        super.setUp();
        // short day buckets so the fuzzer crosses day boundaries frequently
        short = _newPoints(600);
        for (uint256 i = 0; i < SPLITS; ++i) {
            _createDefault();
        }
        handler = new StrPointsHandler(short, factory, usdc, SPLITS);
        targetContract(address(handler));
    }

    /// @dev StrPoints never custodies USDC.
    function invariant_StrPointsUsdcBalanceZero() public view {
        assertEq(usdc.balanceOf(address(short)), 0);
    }

    /// @dev StrPoints never leaves a lingering allowance to the factory.
    function invariant_NoLingeringAllowance() public view {
        assertEq(usdc.allowance(address(short), address(factory)), 0);
    }

    /// @dev StrPoints never leaves a lingering allowance to the CCTP messenger (bridges are in the handler).
    function invariant_NoLingeringMessengerAllowance() public view {
        assertEq(usdc.allowance(address(short), address(messenger)), 0);
    }

    /// @dev Everything the messenger burned equals the sum of successful burn amounts.
    function invariant_MessengerBurnedEqualsGhost() public view {
        assertEq(messenger.totalBurned(), handler.ghostBurned());
        assertEq(usdc.balanceOf(address(messenger)), handler.ghostBurned());
        assertLe(handler.ghostBurned(), handler.ghostBridged());
    }

    /// @dev Factory's USDC equals the sum of credited split balances (no leaks via the wrapper).
    function invariant_FactoryBalanceEqualsSplitBalances() public view {
        uint256 sum;
        for (uint256 i = 1; i <= SPLITS; ++i) {
            sum += factory.splitBalance(i);
        }
        assertEq(usdc.balanceOf(address(factory)), sum);
    }

    /// @dev For every wallet earnedToday <= capToday (cap from highest tier reached) and the ghost model never mismatched.
    function invariant_DailyActivityNeverAboveCap() public view {
        assertEq(handler.violations(), 0, "per-action reference mismatch");
        for (uint256 i = 0; i < handler.actorsLength(); ++i) {
            address a = handler.actors(i);
            (uint256 e, uint256 c, uint8 t, bool h) = short.activityStatus(a);
            assertLe(e, c);
            assertEq(c, _refCap(h ? t : 0));
            assertEq(c, short.dailyCapForTier(h ? t : 0));
            assertEq(e, handler.dayActivity(a, block.timestamp / short.dayLength()));
        }
    }

    /// @dev Total points = activity awards + check-in awards (incl. streak bonuses).
    function invariant_PointsEqualActivityPlusCheckIns() public view {
        assertEq(handler.totalPoints(), handler.activityAwarded() + handler.checkInAwarded());
        assertEq(short.userCount() <= handler.actorsLength(), true);
    }
}
