// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SplitFactory} from "../SplitFactory.sol";
import {SplitFactoryTestBase} from "./SplitFactory.Base.t.sol";
import {MockBlocklistERC20} from "../test-helpers/MockBlocklistERC20.sol";

/// @dev Failed payouts: deferral to claimable, claim/claimTo, creator dust, rescueDust.
contract SplitFactoryDeferralTest is SplitFactoryTestBase {
    MockBlocklistERC20 internal tok;
    uint256 internal id;

    function _deployToken() internal override returns (address) {
        tok = new MockBlocklistERC20();
        return address(tok);
    }

    function setUp() public override {
        super.setUp();
        id = _createDefault(); // bob 60% / carol 40%
    }

    function _threeWay() internal returns (uint256 id3) {
        address[] memory a = new address[](3);
        uint96[] memory b = new uint96[](3);
        a[0] = bob;
        a[1] = carol;
        a[2] = dave;
        b[0] = 3333;
        b[1] = 3333;
        b[2] = 3334;
        id3 = _create(alice, a, b);
    }

    function _liabilities(uint256 splitId) internal view returns (uint256 total) {
        total = factory.splitBalance(splitId) + factory.pendingCreatorDust(splitId);
        total += factory.claimable(splitId, bob) + factory.claimable(splitId, carol) + factory.claimable(splitId, dave);
    }

    // ───────────────────────── deferral ─────────────────────────

    function test_Distribute_BlockedRecipientIsDeferredNotPaidToCreator() public {
        tok.setBlocked(bob, true);
        _dep(alice, id, 1000 * UNIT);
        uint256 aliceBefore = usdc.balanceOf(alice);

        vm.expectEmit(true, true, false, true, address(factory));
        emit SplitFactory.PayoutDeferred(id, bob, 594 * UNIT);
        factory.distribute(id);

        assertEq(usdc.balanceOf(bob), 0);
        assertEq(usdc.balanceOf(carol), 396 * UNIT);
        assertEq(factory.claimable(id, bob), 594 * UNIT);
        assertEq(factory.claimable(id, carol), 0);
        assertEq(usdc.balanceOf(alice), aliceBefore, "creator must not receive deferred share");
        assertEq(factory.pendingCreatorDust(id), 0);
        assertEq(usdc.balanceOf(address(factory)), 594 * UNIT);
        assertEq(factory.splitBalance(id), 0);
    }

    function test_Distribute_ReturnFalseRecipientIsDeferred() public {
        tok.setReturnFalse(carol, true);
        _dep(alice, id, 1000 * UNIT);
        factory.distribute(id);
        assertEq(factory.claimable(id, carol), 396 * UNIT);
        assertEq(usdc.balanceOf(bob), 594 * UNIT);
        assertEq(usdc.balanceOf(address(factory)), 396 * UNIT);
    }

    function test_Distribute_DeferralsAccumulateAcrossDistributions() public {
        tok.setBlocked(bob, true);
        _dep(alice, id, 1000 * UNIT);
        factory.distribute(id);
        _dep(alice, id, 1000 * UNIT);
        factory.distribute(id);
        assertEq(factory.claimable(id, bob), 1188 * UNIT);
    }

    function test_Distribute_AllRecipientsBlockedDoesNotRevert() public {
        tok.setBlocked(bob, true);
        tok.setBlocked(carol, true);
        _dep(alice, id, 1000 * UNIT);
        factory.distribute(id);
        assertEq(factory.claimable(id, bob) + factory.claimable(id, carol), 990 * UNIT);
        assertEq(usdc.balanceOf(address(factory)), 990 * UNIT);
    }

    function test_UpdateSplit_SettlementDefersBlockedRecipientWithoutReverting() public {
        tok.setBlocked(bob, true);
        _dep(alice, id, 1000 * UNIT);
        vm.prank(alice);
        factory.updateSplit(id, _a1(dave), _b1(10_000));
        assertEq(factory.claimable(id, bob), 594 * UNIT);
        assertEq(usdc.balanceOf(carol), 396 * UNIT);
        assertEq(factory.splitVersion(id), 2);
    }

    // ───────────────────────── claim ─────────────────────────

    function test_Claim_PermissionlessPaysRecipient() public {
        tok.setBlocked(bob, true);
        _dep(alice, id, 1000 * UNIT);
        factory.distribute(id);
        tok.setBlocked(bob, false);

        vm.expectEmit(true, true, false, true, address(factory));
        emit SplitFactory.Claimed(id, bob, 594 * UNIT);
        vm.prank(eve);
        factory.claim(id, bob);

        assertEq(usdc.balanceOf(bob), 594 * UNIT);
        assertEq(factory.claimable(id, bob), 0);
        assertEq(usdc.balanceOf(address(factory)), 0);

        vm.expectRevert(SplitFactory.NoClaimable.selector);
        factory.claim(id, bob);
    }

    function test_Claim_StillBlockedRevertsAndKeepsCredit() public {
        tok.setBlocked(bob, true);
        _dep(alice, id, 1000 * UNIT);
        factory.distribute(id);

        vm.expectRevert();
        factory.claim(id, bob);
        assertEq(factory.claimable(id, bob), 594 * UNIT);
    }

    function test_ClaimTo_PaysSenderCreditToDestination() public {
        tok.setBlocked(bob, true);
        _dep(alice, id, 1000 * UNIT);
        factory.distribute(id);

        vm.expectEmit(true, true, false, true, address(factory));
        emit SplitFactory.Claimed(id, bob, 594 * UNIT);
        vm.prank(bob);
        factory.claimTo(id, dave);

        assertEq(usdc.balanceOf(dave), 594 * UNIT);
        assertEq(usdc.balanceOf(bob), 0);
        assertEq(factory.claimable(id, bob), 0);

        vm.prank(bob);
        vm.expectRevert(SplitFactory.NoClaimable.selector);
        factory.claimTo(id, dave);
    }

    function test_ClaimTo_OtherCallerHasNoCredit() public {
        tok.setBlocked(bob, true);
        _dep(alice, id, 1000 * UNIT);
        factory.distribute(id);

        vm.prank(eve);
        vm.expectRevert(SplitFactory.NoClaimable.selector);
        factory.claimTo(id, eve);
        assertEq(factory.claimable(id, bob), 594 * UNIT);
    }

    function test_Claim_CreditIsPerSplit() public {
        uint256 id2 = _create(eve, _a2(bob, carol), _b2(6000, 4000));
        tok.setBlocked(bob, true);
        _dep(alice, id, 1000 * UNIT);
        factory.distribute(id);
        tok.setBlocked(bob, false);

        vm.expectRevert(SplitFactory.NoClaimable.selector);
        factory.claim(id2, bob);
        factory.claim(id, bob);
        assertEq(usdc.balanceOf(bob), 594 * UNIT);
    }

    // ───────────────────────── creator dust ─────────────────────────

    function test_Distribute_BlockedCreatorDustIsPendingThenRescued() public {
        vm.prank(owner);
        factory.setFeeBps(0);
        uint256 id3 = _threeWay();
        tok.setBlocked(alice, true);
        _dep(eve, id3, 1000); // dust = 1
        factory.distribute(id3);

        assertEq(factory.pendingCreatorDust(id3), 1);
        assertEq(usdc.balanceOf(bob), 333);
        assertEq(usdc.balanceOf(address(factory)), 1);

        // non-creator cannot rescue
        vm.prank(eve);
        vm.expectRevert(SplitFactory.Unauthorized.selector);
        factory.rescueDust(id3);

        // creator still blocked: rescue reverts, credit preserved
        vm.prank(alice);
        vm.expectRevert();
        factory.rescueDust(id3);
        assertEq(factory.pendingCreatorDust(id3), 1);

        tok.setBlocked(alice, false);
        uint256 aliceBefore = usdc.balanceOf(alice);
        vm.expectEmit(true, false, false, true, address(factory));
        emit SplitFactory.DustRescued(id3, 1);
        vm.prank(alice);
        factory.rescueDust(id3);

        assertEq(usdc.balanceOf(alice), aliceBefore + 1);
        assertEq(factory.pendingCreatorDust(id3), 0);
        assertEq(usdc.balanceOf(address(factory)), 0);

        vm.prank(alice);
        vm.expectRevert(SplitFactory.NoPendingDust.selector);
        factory.rescueDust(id3);
    }

    function test_Distribute_CreatorReturnFalseDustIsPending() public {
        vm.prank(owner);
        factory.setFeeBps(0);
        uint256 id3 = _threeWay();
        tok.setReturnFalse(alice, true);
        _dep(eve, id3, 1000);
        factory.distribute(id3);
        assertEq(factory.pendingCreatorDust(id3), 1);
    }

    function test_Distribute_BlockedCreatorNoDustLeavesNothingPending() public {
        tok.setBlocked(alice, true);
        _dep(eve, id, 1000 * UNIT);
        factory.distribute(id);
        assertEq(factory.pendingCreatorDust(id), 0);
        assertEq(usdc.balanceOf(bob), 594 * UNIT);
    }

    // ───────────────────────── conservation ─────────────────────────

    function test_Conservation_MixedBlockedPayouts() public {
        vm.prank(owner);
        factory.setFeeBps(0);
        uint256 id3 = _threeWay();
        tok.setBlocked(carol, true);
        tok.setBlocked(alice, true);
        _dep(eve, id3, 10_007);

        uint256 paidBefore = usdc.balanceOf(bob) + usdc.balanceOf(dave) + usdc.balanceOf(alice);
        factory.distribute(id3);
        uint256 paid = usdc.balanceOf(bob) + usdc.balanceOf(dave) + usdc.balanceOf(alice) - paidBefore;
        uint256 deferred = factory.claimable(id3, carol);
        uint256 pending = factory.pendingCreatorDust(id3);

        assertEq(paid + deferred + pending, 10_007);
        assertEq(usdc.balanceOf(address(factory)), deferred + pending);
        assertEq(_liabilities(id3), usdc.balanceOf(address(factory)));
    }

    function testFuzz_DistributeWithFailures_Conserves(uint256 amount, uint8 mask) public {
        amount = bound(amount, 1, 1e24);
        vm.prank(owner);
        factory.setFeeBps(0);
        uint256 id3 = _threeWay();

        if (mask & 1 != 0) tok.setBlocked(bob, true);
        if (mask & 2 != 0) tok.setReturnFalse(carol, true);
        if (mask & 4 != 0) tok.setBlocked(dave, true);
        if (mask & 8 != 0) tok.setBlocked(alice, true);

        usdc.mint(eve, amount);
        _dep(eve, id3, amount);
        uint256 recvBefore = usdc.balanceOf(bob) + usdc.balanceOf(carol) + usdc.balanceOf(dave) + usdc.balanceOf(alice);
        factory.distribute(id3);
        uint256 paid = usdc.balanceOf(bob) + usdc.balanceOf(carol) + usdc.balanceOf(dave) + usdc.balanceOf(alice) - recvBefore;

        uint256 deferred = factory.claimable(id3, bob) + factory.claimable(id3, carol) + factory.claimable(id3, dave);
        uint256 pending = factory.pendingCreatorDust(id3);

        assertEq(paid + deferred + pending, amount);
        assertEq(usdc.balanceOf(address(factory)), deferred + pending);
        // deferred shares are exactly the blocked recipients' floor shares
        if (mask & 1 != 0) assertEq(factory.claimable(id3, bob), amount * 3333 / 10_000);
        else assertEq(factory.claimable(id3, bob), 0);
        // creator is never paid a recipient's failed share
        uint256 dust = amount - (amount * 3333 / 10_000) * 2 - (amount * 3334 / 10_000);
        assertEq(pending, mask & 8 != 0 ? dust : 0);
    }
}
