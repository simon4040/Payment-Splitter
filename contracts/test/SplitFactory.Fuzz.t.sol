// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SplitFactory} from "../SplitFactory.sol";
import {SplitFactoryTestBase} from "./SplitFactory.Base.t.sol";

contract SplitFactoryFuzzTest is SplitFactoryTestBase {
    // (a) deposit conservation for any amount and any fee in [0, 500]
    function testFuzz_DepositConservation(uint256 amount, uint16 feeBps) public {
        amount = bound(amount, 1, 1e30);
        feeBps = uint16(bound(feeBps, 0, 500));

        vm.prank(owner);
        factory.setFeeBps(feeBps);
        uint256 id = _createDefault();

        usdc.mint(alice, amount);
        uint256 aliceBefore = usdc.balanceOf(alice);
        uint256 feeBefore = usdc.balanceOf(feeRecipient);
        uint256 facBefore = usdc.balanceOf(address(factory));

        (uint256 pNet, uint256 pFee) = factory.previewDeposit(amount);
        _dep(alice, id, amount);

        uint256 feePaid = usdc.balanceOf(feeRecipient) - feeBefore;
        uint256 netIn = usdc.balanceOf(address(factory)) - facBefore;

        assertEq(feePaid + netIn, amount, "fee + net == amount");
        assertLe(feePaid, amount * 5 / 100, "fee <= 5%");
        assertEq(feePaid, amount * feeBps / 10_000);
        assertEq(netIn, amount - feePaid);
        assertEq(factory.splitBalance(id), netIn);
        assertEq(aliceBefore - usdc.balanceOf(alice), amount);
        assertEq(pNet, netIn, "preview net");
        assertEq(pFee, feePaid, "preview fee");
    }

    function testFuzz_DepositEmitsMatchingEvent(uint256 amount, uint16 feeBps) public {
        amount = bound(amount, 1, 1e30);
        feeBps = uint16(bound(feeBps, 0, 500));
        vm.prank(owner);
        factory.setFeeBps(feeBps);
        uint256 id = _createDefault();
        usdc.mint(alice, amount);
        (uint256 net, uint256 fee) = factory.previewDeposit(amount);

        vm.expectEmit(true, true, false, true, address(factory));
        emit SplitFactory.Deposited(id, alice, net, fee);
        _dep(alice, id, amount);
    }

    function testFuzz_SetFeeBps_AboveMaxReverts(uint16 feeBps) public {
        feeBps = uint16(bound(feeBps, 501, type(uint16).max));
        vm.prank(owner);
        vm.expectRevert(SplitFactory.FeeTooHigh.selector);
        factory.setFeeBps(feeBps);
    }

    /// @dev Builds `n` recipients with pseudo-random bps summing to 10_000.
    function _randomSplit(uint256 seed, uint256 n) internal pure returns (address[] memory a, uint96[] memory b) {
        a = new address[](n);
        b = new uint96[](n);
        uint256 remaining = 10_000;
        for (uint256 i; i < n; ++i) {
            a[i] = address(uint160(0x20000 + i));
            if (i == n - 1) {
                b[i] = uint96(remaining);
            } else {
                uint256 part = uint256(keccak256(abi.encode(seed, i))) % (remaining + 1);
                b[i] = uint96(part);
                remaining -= part;
            }
        }
    }

    // (b) distribute conservation with random amounts and random splits
    function testFuzz_DistributeConservation(uint256 amount, uint256 seed, uint8 count, uint16 feeBps) public {
        amount = bound(amount, 1, 1e30);
        uint256 n = bound(count, 1, 20);
        feeBps = uint16(bound(feeBps, 0, 500));

        vm.prank(owner);
        factory.setFeeBps(feeBps);
        (address[] memory a, uint96[] memory b) = _randomSplit(seed, n);
        uint256 id = _create(alice, a, b);

        usdc.mint(alice, amount);
        _dep(alice, id, amount);
        (uint256 net,) = factory.previewDeposit(amount);

        uint256 aliceBefore = usdc.balanceOf(alice);
        factory.distribute(id);

        uint256 paid;
        uint256 sumShares;
        for (uint256 i; i < n; ++i) {
            uint256 expected = net * b[i] / 10_000;
            sumShares += expected;
            // recipient addresses are distinct, so balance == share
            assertEq(usdc.balanceOf(a[i]), expected, "recipient share");
            paid += usdc.balanceOf(a[i]);
        }
        uint256 dust = usdc.balanceOf(alice) - aliceBefore;

        assertEq(dust, net - sumShares, "creator gets only rounding dust");
        assertLt(dust, n, "dust < recipientCount");
        assertEq(paid + dust, net, "paid + dust == net");
        assertEq(usdc.balanceOf(address(factory)), 0);
        assertEq(factory.splitBalance(id), 0);
        (,, uint256 dist,) = factory.getSplit(id);
        assertEq(dist, net);
    }

    // updateSplit settlement conserves funds under the old config
    function testFuzz_UpdateSettlesUnderOldConfig(uint256 amount, uint256 seed) public {
        amount = bound(amount, 1, 1e30);
        (address[] memory a, uint96[] memory b) = _randomSplit(seed, 3);
        uint256 id = _create(alice, a, b);
        usdc.mint(alice, amount);
        _dep(alice, id, amount);
        (uint256 net,) = factory.previewDeposit(amount);

        vm.prank(alice);
        factory.updateSplit(id, _a1(dave), _b1(10_000));

        for (uint256 i; i < 3; ++i) {
            assertEq(usdc.balanceOf(a[i]), net * b[i] / 10_000);
        }
        assertEq(usdc.balanceOf(dave), 0);
        assertEq(usdc.balanceOf(address(factory)), 0);
        assertEq(factory.splitVersion(id), 2);
    }
}
