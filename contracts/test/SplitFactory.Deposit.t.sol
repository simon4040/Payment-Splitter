// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {SplitFactory} from "../SplitFactory.sol";
import {SplitFactoryTestBase} from "./SplitFactory.Base.t.sol";

/// @dev deposit / previewDeposit / distribute / claim error paths (happy transfers only).
contract SplitFactoryDepositTest is SplitFactoryTestBase {
    uint256 internal id;

    function setUp() public override {
        super.setUp();
        id = _createDefault();
    }

    // ───────────────────────── deposit ─────────────────────────

    function test_Deposit_SplitsFeeAndNet() public {
        uint256 aliceBefore = usdc.balanceOf(alice);
        _dep(alice, id, 1000 * UNIT);

        assertEq(usdc.balanceOf(feeRecipient), 10 * UNIT);
        assertEq(usdc.balanceOf(address(factory)), 990 * UNIT);
        assertEq(factory.splitBalance(id), 990 * UNIT);
        assertEq(usdc.balanceOf(alice), aliceBefore - 1000 * UNIT);
        (, uint256 bal,,) = factory.getSplit(id);
        assertEq(bal, 990 * UNIT);
    }

    function test_Deposit_EmitsDeposited() public {
        vm.expectEmit(true, true, false, true, address(factory));
        emit SplitFactory.Deposited(id, alice, 990 * UNIT, 10 * UNIT);
        _dep(alice, id, 1000 * UNIT);
    }

    function test_Deposit_AnyoneCanFundASplit() public {
        _dep(eve, id, 500 * UNIT);
        assertEq(factory.splitBalance(id), 495 * UNIT);
    }

    function test_Deposit_Accumulates() public {
        _dep(alice, id, 1000 * UNIT);
        _dep(eve, id, 2000 * UNIT);
        assertEq(factory.splitBalance(id), 2970 * UNIT);
        assertEq(usdc.balanceOf(address(factory)), 2970 * UNIT);
        assertEq(usdc.balanceOf(feeRecipient), 30 * UNIT);
    }

    function test_Deposit_ZeroFeeSendsNoFeeTransfer() public {
        vm.prank(owner);
        factory.setFeeBps(0);

        vm.recordLogs();
        _dep(alice, id, 1000 * UNIT);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 transfers;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(usdc) && logs[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                ++transfers;
            }
        }
        assertEq(transfers, 1);
        assertEq(usdc.balanceOf(feeRecipient), 0);
        assertEq(factory.splitBalance(id), 1000 * UNIT);
    }

    function test_Deposit_FeeRoundsDownForSmallAmounts() public {
        _dep(alice, id, 99); // 99 * 100 / 10000 = 0
        assertEq(usdc.balanceOf(feeRecipient), 0);
        assertEq(factory.splitBalance(id), 99);

        _dep(alice, id, 100); // fee 1
        assertEq(usdc.balanceOf(feeRecipient), 1);
        assertEq(factory.splitBalance(id), 99 + 99);
    }

    function test_Deposit_UsesUpdatedFeeAndRecipient() public {
        vm.startPrank(owner);
        factory.setFeeBps(500);
        factory.setFeeRecipient(dave);
        vm.stopPrank();

        _dep(alice, id, 1000 * UNIT);
        assertEq(usdc.balanceOf(dave), 50 * UNIT);
        assertEq(usdc.balanceOf(feeRecipient), 0);
        assertEq(factory.splitBalance(id), 950 * UNIT);
    }

    function test_RevertDeposit_SplitNotFound() public {
        vm.startPrank(alice);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.deposit(0, 100, 1);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.deposit(99, 100, 1);
        vm.stopPrank();
    }

    function test_RevertDeposit_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(SplitFactory.ZeroAmount.selector);
        factory.deposit(id, 0, 1);
    }

    function test_RevertDeposit_ConfigChanged() public {
        vm.startPrank(alice);
        vm.expectRevert(SplitFactory.ConfigChanged.selector);
        factory.deposit(id, 100 * UNIT, 0);
        vm.expectRevert(SplitFactory.ConfigChanged.selector);
        factory.deposit(id, 100 * UNIT, 2);
        vm.stopPrank();
        assertEq(factory.splitBalance(id), 0);
    }

    function test_RevertDeposit_InsufficientAllowance() public {
        usdc.mint(dave, 100 * UNIT); // dave never approved
        vm.prank(dave);
        vm.expectRevert();
        factory.deposit(id, 100 * UNIT, 1);
        assertEq(factory.splitBalance(id), 0);
    }

    // ───────────────────────── previewDeposit ─────────────────────────

    function test_PreviewDeposit_MatchesDeposit() public {
        (uint256 net, uint256 fee) = factory.previewDeposit(1234 * UNIT + 17);
        assertEq(net + fee, 1234 * UNIT + 17);

        uint256 feeBefore = usdc.balanceOf(feeRecipient);
        _dep(alice, id, 1234 * UNIT + 17);
        assertEq(factory.splitBalance(id), net);
        assertEq(usdc.balanceOf(feeRecipient) - feeBefore, fee);
    }

    function test_PreviewDeposit_TracksFeeChanges() public {
        vm.prank(owner);
        factory.setFeeBps(500);
        (uint256 net, uint256 fee) = factory.previewDeposit(2000);
        assertEq(fee, 100);
        assertEq(net, 1900);
        (net, fee) = factory.previewDeposit(0);
        assertEq(net, 0);
        assertEq(fee, 0);
    }

    // ───────────────────────── distribute ─────────────────────────

    function test_Distribute_PaysRecipientsProRata() public {
        _dep(alice, id, 1000 * UNIT);
        uint256 aliceBefore = usdc.balanceOf(alice);

        vm.expectEmit(true, false, false, true, address(factory));
        emit SplitFactory.Distributed(id, 990 * UNIT, 2);
        vm.prank(eve); // permissionless
        factory.distribute(id);

        assertEq(usdc.balanceOf(bob), 594 * UNIT);
        assertEq(usdc.balanceOf(carol), 396 * UNIT);
        assertEq(usdc.balanceOf(alice), aliceBefore); // no dust
        assertEq(usdc.balanceOf(address(factory)), 0);
        assertEq(factory.splitBalance(id), 0);
        (,, uint256 dist,) = factory.getSplit(id);
        assertEq(dist, 990 * UNIT);
    }

    function test_Distribute_TotalDistributedAccumulates() public {
        _dep(alice, id, 1000 * UNIT);
        factory.distribute(id);
        _dep(alice, id, 1000 * UNIT);
        factory.distribute(id);
        (,, uint256 dist,) = factory.getSplit(id);
        assertEq(dist, 1980 * UNIT);
    }

    function test_Distribute_RoundingDustGoesToCreator() public {
        vm.prank(owner);
        factory.setFeeBps(0);
        uint256 id2 = _create(alice, _a2(bob, carol), _b2(3333, 6667));
        // 1 unit: shares are 0 and 0, whole unit is dust
        _dep(eve, id2, 1);
        uint256 aliceBefore = usdc.balanceOf(alice);
        factory.distribute(id2);
        assertEq(usdc.balanceOf(alice), aliceBefore + 1);
        assertEq(usdc.balanceOf(bob), 0);
        assertEq(usdc.balanceOf(carol), 0);
        assertEq(usdc.balanceOf(address(factory)), 0);
    }

    function test_Distribute_ThreeWayDust() public {
        vm.prank(owner);
        factory.setFeeBps(0);
        address[] memory a = new address[](3);
        uint96[] memory b = new uint96[](3);
        a[0] = bob;
        a[1] = carol;
        a[2] = dave;
        b[0] = 3333;
        b[1] = 3333;
        b[2] = 3334;
        uint256 id3 = _create(alice, a, b);
        _dep(eve, id3, 1000);
        uint256 aliceBefore = usdc.balanceOf(alice);
        factory.distribute(id3);
        assertEq(usdc.balanceOf(bob), 333);
        assertEq(usdc.balanceOf(carol), 333);
        assertEq(usdc.balanceOf(dave), 333);
        assertEq(usdc.balanceOf(alice), aliceBefore + 1);
    }

    function test_Distribute_SplitsAreIndependent() public {
        uint256 id2 = _create(eve, _a1(dave), _b1(10_000));
        _dep(alice, id, 1000 * UNIT);
        _dep(alice, id2, 2000 * UNIT);
        factory.distribute(id2);
        assertEq(usdc.balanceOf(dave), 1980 * UNIT);
        assertEq(factory.splitBalance(id), 990 * UNIT);
        assertEq(usdc.balanceOf(bob), 0);
    }

    function test_RevertDistribute_NoBalance() public {
        vm.expectRevert(SplitFactory.NoBalance.selector);
        factory.distribute(id);
        _dep(alice, id, 100 * UNIT);
        factory.distribute(id);
        vm.expectRevert(SplitFactory.NoBalance.selector);
        factory.distribute(id);
    }

    function test_RevertDistribute_NotFound() public {
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.distribute(42);
    }

    // ───────────────────────── claim / claimTo / rescueDust error paths ─────────────────────────

    function test_RevertClaim_NoClaimable() public {
        vm.expectRevert(SplitFactory.NoClaimable.selector);
        factory.claim(id, bob);
    }

    function test_RevertClaim_NotFound() public {
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.claim(99, bob);
    }

    function test_RevertClaimTo_NoClaimable() public {
        vm.prank(bob);
        vm.expectRevert(SplitFactory.NoClaimable.selector);
        factory.claimTo(id, dave);
    }

    function test_RevertClaimTo_NotFound() public {
        vm.prank(bob);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.claimTo(99, dave);
    }

    function test_RevertClaimTo_InvalidDestinations() public {
        vm.startPrank(bob);
        vm.expectRevert(SplitFactory.ZeroAddress.selector);
        factory.claimTo(id, address(0));
        vm.expectRevert(SplitFactory.InvalidDestination.selector);
        factory.claimTo(id, address(factory));
        vm.expectRevert(SplitFactory.InvalidDestination.selector);
        factory.claimTo(id, address(usdc));
        vm.expectRevert(SplitFactory.InvalidDestination.selector);
        factory.claimTo(id, address(0xFFFF));
        vm.stopPrank();
    }

    function test_RevertRescueDust_Paths() public {
        vm.prank(eve);
        vm.expectRevert(SplitFactory.Unauthorized.selector);
        factory.rescueDust(id);

        vm.prank(alice);
        vm.expectRevert(SplitFactory.NoPendingDust.selector);
        factory.rescueDust(id);

        vm.prank(alice);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.rescueDust(99);
    }
}
