// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SplitFactory} from "../SplitFactory.sol";
import {SplitFactoryTestBase} from "./SplitFactory.Base.t.sol";

/// @dev Constructor, fee administration, ownership, createSplit, updateSplit, views.
contract SplitFactoryTest is SplitFactoryTestBase {
    // ───────────────────────── Constructor ─────────────────────────

    function test_Constructor_SetsState() public view {
        assertEq(factory.usdc(), address(usdc));
        assertEq(factory.owner(), owner);
        assertEq(factory.feeRecipient(), feeRecipient);
        assertEq(factory.feeBps(), FEE_BPS);
        assertEq(factory.MAX_FEE_BPS(), 500);
        assertEq(factory.splitCount(), 0);
    }

    function test_Constructor_EmitsFeeEvents() public {
        vm.expectEmit(false, false, false, true);
        emit SplitFactory.FeeBpsUpdated(0, 250);
        vm.expectEmit(true, true, false, false);
        emit SplitFactory.FeeRecipientUpdated(address(0), feeRecipient);
        new SplitFactory(address(usdc), owner, feeRecipient, 250);
    }

    function test_Constructor_AllowsMaxAndZeroFee() public {
        assertEq(new SplitFactory(address(usdc), owner, feeRecipient, 500).feeBps(), 500);
        assertEq(new SplitFactory(address(usdc), owner, feeRecipient, 0).feeBps(), 0);
    }

    function test_RevertConstructor_ZeroUsdc() public {
        vm.expectRevert(SplitFactory.ZeroAddress.selector);
        new SplitFactory(address(0), owner, feeRecipient, 100);
    }

    function test_RevertConstructor_ZeroFeeRecipient() public {
        vm.expectRevert(SplitFactory.ZeroAddress.selector);
        new SplitFactory(address(usdc), owner, address(0), 100);
    }

    function test_RevertConstructor_ZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new SplitFactory(address(usdc), address(0), feeRecipient, 100);
    }

    function test_RevertConstructor_FeeTooHigh() public {
        vm.expectRevert(SplitFactory.FeeTooHigh.selector);
        new SplitFactory(address(usdc), owner, feeRecipient, 501);
    }

    // ───────────────────────── Fee administration ─────────────────────────

    function test_SetFeeBps_UpdatesAndEmits() public {
        vm.expectEmit(false, false, false, true, address(factory));
        emit SplitFactory.FeeBpsUpdated(FEE_BPS, 300);
        vm.prank(owner);
        factory.setFeeBps(300);
        assertEq(factory.feeBps(), 300);
    }

    function test_SetFeeBps_AllowsZeroAndExactMax() public {
        vm.startPrank(owner);
        factory.setFeeBps(500);
        assertEq(factory.feeBps(), 500);
        factory.setFeeBps(0);
        assertEq(factory.feeBps(), 0);
        vm.stopPrank();
    }

    function test_RevertSetFeeBps_AboveMax() public {
        vm.prank(owner);
        vm.expectRevert(SplitFactory.FeeTooHigh.selector);
        factory.setFeeBps(501);
    }

    function test_RevertSetFeeBps_NonOwner() public {
        vm.prank(eve);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, eve));
        factory.setFeeBps(10);
    }

    function test_SetFeeRecipient_UpdatesAndEmits() public {
        vm.expectEmit(true, true, false, false, address(factory));
        emit SplitFactory.FeeRecipientUpdated(feeRecipient, dave);
        vm.prank(owner);
        factory.setFeeRecipient(dave);
        assertEq(factory.feeRecipient(), dave);
    }

    function test_RevertSetFeeRecipient_Zero() public {
        vm.prank(owner);
        vm.expectRevert(SplitFactory.ZeroAddress.selector);
        factory.setFeeRecipient(address(0));
    }

    function test_RevertSetFeeRecipient_NonOwner() public {
        vm.prank(eve);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, eve));
        factory.setFeeRecipient(eve);
    }

    // ───────────────────────── Ownership ─────────────────────────

    function test_RevertRenounceOwnership() public {
        vm.prank(owner);
        vm.expectRevert(SplitFactory.RenounceDisabled.selector);
        factory.renounceOwnership();
        assertEq(factory.owner(), owner);
    }

    function test_Ownable2Step_TransferFlow() public {
        vm.prank(owner);
        factory.transferOwnership(alice);
        assertEq(factory.owner(), owner);
        assertEq(factory.pendingOwner(), alice);

        vm.prank(eve);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, eve));
        factory.acceptOwnership();

        vm.prank(alice);
        factory.acceptOwnership();
        assertEq(factory.owner(), alice);

        vm.prank(alice);
        factory.setFeeBps(7);
        assertEq(factory.feeBps(), 7);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        factory.setFeeBps(8);
    }

    // ───────────────────────── createSplit ─────────────────────────

    function test_CreateSplit_StoresStateAndVersion() public {
        uint256 id = _createDefault();
        assertEq(id, 1);
        assertEq(factory.splitCount(), 1);
        assertEq(factory.splitVersion(id), 1);

        (address creator, uint256 bal, uint256 dist, uint256 count) = factory.getSplit(id);
        assertEq(creator, alice);
        assertEq(bal, 0);
        assertEq(dist, 0);
        assertEq(count, 2);

        (address[] memory a, uint96[] memory b) = factory.getRecipients(id);
        assertEq(a[0], bob);
        assertEq(a[1], carol);
        assertEq(b[0], 6000);
        assertEq(b[1], 4000);
    }

    function test_CreateSplit_EmitsEvent() public {
        vm.expectEmit(true, true, false, false, address(factory));
        emit SplitFactory.SplitCreated(1, alice);
        _createDefault();
    }

    function test_CreateSplit_IndependentSplits() public {
        uint256 id1 = _createDefault();
        uint256 id2 = _create(eve, _a1(dave), _b1(10_000));
        assertEq(id2, id1 + 1);
        (address c1,,,) = factory.getSplit(id1);
        (address c2,,, uint256 n2) = factory.getSplit(id2);
        assertEq(c1, alice);
        assertEq(c2, eve);
        assertEq(n2, 1);
        assertEq(factory.splitVersion(id2), 1);
    }

    function test_CreateSplit_MaxTwentyRecipients() public {
        address[] memory a = new address[](20);
        uint96[] memory b = new uint96[](20);
        for (uint256 i; i < 20; ++i) {
            a[i] = address(uint160(0x20000 + i));
            b[i] = 500;
        }
        uint256 id = _create(alice, a, b);
        (,,, uint256 n) = factory.getSplit(id);
        assertEq(n, 20);
    }

    function test_CreateSplit_AcceptsLowestValidAddress() public {
        uint256 id = _create(alice, _a1(address(0x10000)), _b1(10_000));
        (address[] memory a,) = factory.getRecipients(id);
        assertEq(a[0], address(0x10000));
    }

    function test_RevertCreateSplit_LengthMismatch() public {
        vm.prank(alice);
        vm.expectRevert(SplitFactory.InvalidSplit.selector);
        factory.createSplit(_a2(bob, carol), _b1(10_000));
    }

    function test_RevertCreateSplit_Empty() public {
        vm.prank(alice);
        vm.expectRevert(SplitFactory.InvalidSplit.selector);
        factory.createSplit(new address[](0), new uint96[](0));
    }

    function test_RevertCreateSplit_TooManyRecipients() public {
        address[] memory a = new address[](21);
        uint96[] memory b = new uint96[](21);
        for (uint256 i; i < 21; ++i) {
            a[i] = address(uint160(0x20000 + i));
            b[i] = 476;
        }
        vm.prank(alice);
        vm.expectRevert(SplitFactory.InvalidSplit.selector);
        factory.createSplit(a, b);
    }

    function test_RevertCreateSplit_BpsNotTotal10000() public {
        vm.startPrank(alice);
        vm.expectRevert(SplitFactory.InvalidSplit.selector);
        factory.createSplit(_a2(bob, carol), _b2(5000, 4999));
        vm.expectRevert(SplitFactory.InvalidSplit.selector);
        factory.createSplit(_a2(bob, carol), _b2(5000, 5001));
        vm.stopPrank();
    }

    function test_RevertCreateSplit_ZeroAddress() public {
        vm.prank(alice);
        vm.expectRevert(SplitFactory.ZeroAddress.selector);
        factory.createSplit(_a2(bob, address(0)), _b2(5000, 5000));
    }

    function test_RevertCreateSplit_InvalidDestinations() public {
        vm.startPrank(alice);
        vm.expectRevert(SplitFactory.InvalidDestination.selector);
        factory.createSplit(_a1(address(factory)), _b1(10_000));
        vm.expectRevert(SplitFactory.InvalidDestination.selector);
        factory.createSplit(_a1(address(usdc)), _b1(10_000));
        vm.expectRevert(SplitFactory.InvalidDestination.selector);
        factory.createSplit(_a1(address(0xFFFF)), _b1(10_000));
        vm.expectRevert(SplitFactory.InvalidDestination.selector);
        factory.createSplit(_a1(address(1)), _b1(10_000));
        vm.stopPrank();
    }

    // ───────────────────────── updateSplit ─────────────────────────

    function test_UpdateSplit_ReplacesRecipientsAndBumpsVersion() public {
        uint256 id = _createDefault();
        vm.expectEmit(true, false, false, false, address(factory));
        emit SplitFactory.SplitUpdated(id);
        vm.prank(alice);
        factory.updateSplit(id, _a2(dave, eve), _b2(1000, 9000));

        assertEq(factory.splitVersion(id), 2);
        (address[] memory a, uint96[] memory b) = factory.getRecipients(id);
        assertEq(a.length, 2);
        assertEq(a[0], dave);
        assertEq(a[1], eve);
        assertEq(b[0], 1000);
        assertEq(b[1], 9000);
    }

    function test_UpdateSplit_CanShrinkRecipients() public {
        uint256 id = _createDefault();
        vm.prank(alice);
        factory.updateSplit(id, _a1(dave), _b1(10_000));
        (address[] memory a,) = factory.getRecipients(id);
        assertEq(a.length, 1);
        assertEq(a[0], dave);
    }

    function test_UpdateSplit_VersionIncrementsEachTime() public {
        uint256 id = _createDefault();
        for (uint256 i; i < 3; ++i) {
            vm.prank(alice);
            factory.updateSplit(id, _a1(dave), _b1(10_000));
        }
        assertEq(factory.splitVersion(id), 4);
    }

    function test_UpdateSplit_SettlesUnderOldRecipientsFirst() public {
        uint256 id = _createDefault();
        _dep(alice, id, 1000 * UNIT); // fee 10, net 990
        uint256 net = 990 * UNIT;
        assertEq(factory.splitBalance(id), net);

        vm.prank(alice);
        factory.updateSplit(id, _a1(dave), _b1(10_000));

        // old recipients were paid 60/40 of the pending balance; new one got nothing
        assertEq(usdc.balanceOf(bob), net * 6000 / 10_000);
        assertEq(usdc.balanceOf(carol), net * 4000 / 10_000);
        assertEq(usdc.balanceOf(dave), 0);
        assertEq(factory.splitBalance(id), 0);
        assertEq(usdc.balanceOf(address(factory)), 0);
        (,, uint256 dist,) = factory.getSplit(id);
        assertEq(dist, net);

        // post-update deposits go to new recipients
        _dep(alice, id, 1000 * UNIT);
        factory.distribute(id);
        assertEq(usdc.balanceOf(dave), net);
        assertEq(usdc.balanceOf(bob), net * 6000 / 10_000);
    }

    function test_UpdateSplit_StaleVersionDepositReverts() public {
        uint256 id = _createDefault();
        uint256 staleVersion = factory.splitVersion(id);
        vm.prank(alice);
        factory.updateSplit(id, _a1(dave), _b1(10_000));

        vm.prank(alice);
        vm.expectRevert(SplitFactory.ConfigChanged.selector);
        factory.deposit(id, 100 * UNIT, staleVersion);
    }

    function test_UpdateSplit_NoBalanceDoesNotDistribute() public {
        uint256 id = _createDefault();
        vm.recordLogs();
        vm.prank(alice);
        factory.updateSplit(id, _a1(dave), _b1(10_000));
        assertEq(vm.getRecordedLogs().length, 1); // only SplitUpdated
    }

    function test_RevertUpdateSplit_NonCreator() public {
        uint256 id = _createDefault();
        vm.prank(eve);
        vm.expectRevert(SplitFactory.Unauthorized.selector);
        factory.updateSplit(id, _a1(dave), _b1(10_000));
    }

    function test_RevertUpdateSplit_NotFound() public {
        vm.prank(alice);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.updateSplit(1, _a1(dave), _b1(10_000));
    }

    function test_RevertUpdateSplit_Validation() public {
        uint256 id = _createDefault();
        vm.startPrank(alice);
        vm.expectRevert(SplitFactory.InvalidSplit.selector);
        factory.updateSplit(id, _a2(bob, carol), _b2(1, 1));
        vm.expectRevert(SplitFactory.ZeroAddress.selector);
        factory.updateSplit(id, _a1(address(0)), _b1(10_000));
        vm.expectRevert(SplitFactory.InvalidDestination.selector);
        factory.updateSplit(id, _a1(address(factory)), _b1(10_000));
        vm.expectRevert(SplitFactory.InvalidDestination.selector);
        factory.updateSplit(id, _a1(address(usdc)), _b1(10_000));
        vm.expectRevert(SplitFactory.InvalidDestination.selector);
        factory.updateSplit(id, _a1(address(0xFFFF)), _b1(10_000));
        vm.stopPrank();
        assertEq(factory.splitVersion(id), 1);
    }

    function test_RevertUpdateSplit_InvalidInputsDoNotSettleBalance() public {
        uint256 id = _createDefault();
        _dep(alice, id, 1000 * UNIT);
        vm.prank(alice);
        vm.expectRevert(SplitFactory.InvalidSplit.selector);
        factory.updateSplit(id, _a2(bob, carol), _b2(1, 1));
        assertEq(factory.splitBalance(id), 990 * UNIT);
        assertEq(usdc.balanceOf(bob), 0);
    }

    // ───────────────────────── Views ─────────────────────────

    function test_RevertViews_SplitNotFound() public {
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.getSplit(0);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.getSplit(1);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.getRecipients(1);
    }
}
