// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StrPointsTestBase} from "./StrPoints.Base.t.sol";
import {StrPoints} from "../StrPoints.sol";

contract StrPointsBridgeFuzzTest is StrPointsTestBase {
    bytes internal constant HOOK = hex"636374702d666f72776172640000000000000000000000000000000000000000";

    function testFuzz_Bridge_Conservation(uint256 amount, uint16 feeBps, uint256 maxFeeSeed, bool fast, address rcpt)
        public
    {
        amount = bound(amount, 1, type(uint96).max);
        feeBps = uint16(bound(feeBps, 0, 500));
        vm.assume(rcpt != address(0));
        vm.prank(owner);
        factory.setFeeBps(feeBps);

        uint256 fee = amount * feeBps / 10_000;
        uint256 burn = amount - fee;
        uint256 maxFee = maxFeeSeed % burn; // < burn (burn >= 1)
        uint32 fin = fast ? 1000 : 2000;

        _fundBridge(sp, dave, amount);
        uint256 recBefore = usdc.balanceOf(feeRecipient);
        uint256 msgBefore = usdc.balanceOf(address(messenger));

        _checkPreview(amount, fee, burn, feeBps);

        vm.prank(dave);
        sp.bridge(amount, maxFee, fin, rcpt, feeBps);

        assertEq(fee + burn, amount, "split");
        assertEq(usdc.balanceOf(feeRecipient) - recBefore, fee, "fee recipient delta");
        assertEq(usdc.balanceOf(address(messenger)) - msgBefore, burn, "messenger delta");
        assertEq(usdc.balanceOf(dave), 0, "user drained exactly");
        assertEq(usdc.balanceOf(address(sp)), 0, "sp holds");
        assertEq(usdc.allowance(address(sp), address(messenger)), 0, "allowance");

        _checkMessenger(burn, maxFee, fin, rcpt);
        _checkPoints(amount);
    }

    function _checkPreview(uint256 amount, uint256 fee, uint256 burn, uint16 feeBps) internal view {
        (uint256 pFee, uint256 pBurn, uint16 pBps) = sp.previewBridge(amount);
        assertEq(pFee, fee);
        assertEq(pBurn, burn);
        assertEq(pBps, feeBps);
    }

    function _checkMessenger(uint256 burn, uint256 maxFee, uint32 fin, address rcpt) internal view {
        assertEq(messenger.lastAmount(), burn);
        assertEq(messenger.lastDestinationDomain(), DOMAIN);
        assertEq(messenger.lastMintRecipient(), bytes32(uint256(uint160(rcpt))));
        assertEq(messenger.lastBurnToken(), address(usdc));
        assertEq(messenger.lastDestinationCaller(), bytes32(0));
        assertEq(messenger.lastMaxFee(), maxFee);
        assertEq(messenger.lastMinFinalityThreshold(), fin);
        assertEq(messenger.lastHookData(), HOOK);
    }

    /// @dev First action of the day: a single award never exceeds its own tier's cap.
    function _checkPoints(uint256 amount) internal view {
        (bool q,, uint256 pts) = _refTier(amount);
        assertEq(sp.pointsOf(dave), q ? pts : 0, "points");
        assertEq(sp.userCount(), q ? 1 : 0);
    }

    function testFuzz_Bridge_PointsMatchTierTableWithCap(uint256 a1, uint256 a2, uint256 a3) public {
        a1 = bound(a1, 1, 5_000e6);
        a2 = bound(a2, 1, 5_000e6);
        a3 = bound(a3, 1, 5_000e6);
        _fundBridge(sp, dave, a1 + a2 + a3);

        uint256 expected;
        uint256 earned;
        uint8 enc; // highest tier + 1
        uint256[3] memory amts = [a1, a2, a3];
        for (uint256 i = 0; i < 3; ++i) {
            (bool q, uint8 tier, uint256 pts) = _refTier(amts[i]);
            _bridgeAs(sp, dave, amts[i]);
            if (!q) continue;
            if (tier + 1 > enc) enc = tier + 1;
            uint256 cap = _refCap(enc - 1);
            uint256 rem = cap > earned ? cap - earned : 0;
            uint256 got = pts < rem ? pts : rem;
            earned += got;
            expected += got;
        }
        assertEq(sp.pointsOf(dave), expected);
        (uint256 e, uint256 c,,) = sp.activityStatus(dave);
        assertEq(e, earned);
        assertLe(e, c);
    }

    function testFuzz_Bridge_RevertsInvalidMaxFee(uint256 amount, uint256 over) public {
        amount = bound(amount, 1, type(uint96).max);
        (, uint256 burn,) = sp.previewBridge(amount);
        over = bound(over, 0, type(uint128).max);
        _fundBridge(sp, dave, amount);
        vm.prank(dave);
        vm.expectRevert(StrPoints.InvalidMaxFee.selector);
        sp.bridge(amount, burn + over, 1000, bob, 500);
        assertEq(usdc.balanceOf(dave), amount);
        assertEq(messenger.callCount(), 0);
    }

    function testFuzz_Bridge_RevertsInvalidFinality(uint32 fin) public {
        vm.assume(fin != 1000 && fin != 2000);
        _fundBridge(sp, dave, 100e6);
        vm.prank(dave);
        vm.expectRevert(StrPoints.InvalidFinality.selector);
        sp.bridge(100e6, 0, fin, bob, 500);
    }

    function testFuzz_Bridge_RevertsFeeTooHighWhenCapBelowLive(uint16 live, uint16 cap) public {
        live = uint16(bound(live, 1, 500));
        cap = uint16(bound(cap, 0, live - 1));
        vm.prank(owner);
        factory.setFeeBps(live);
        _fundBridge(sp, dave, 100e6);
        vm.prank(dave);
        vm.expectRevert(StrPoints.FeeTooHigh.selector);
        sp.bridge(100e6, 0, 1000, bob, cap);
    }
}
