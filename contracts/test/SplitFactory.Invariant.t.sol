// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SplitFactory} from "../SplitFactory.sol";
import {SplitFactoryTestBase} from "./SplitFactory.Base.t.sol";
import {MockBlocklistERC20} from "../test-helpers/MockBlocklistERC20.sol";

/// @dev Bounded action surface for the invariant fuzzer. Recipients/creator are drawn
///      from a fixed actor set so liabilities (claimable) can be enumerated exactly.
contract SplitFactoryHandler is Test {
    SplitFactory public factory;
    MockBlocklistERC20 public tok;
    address public owner;
    address public feeRecipient;
    address[5] public actors;
    uint256 public ghostFees;
    uint256 public ghostDeposits;

    constructor(SplitFactory _factory, MockBlocklistERC20 _tok, address _owner, address _feeRecipient) {
        factory = _factory;
        tok = _tok;
        owner = _owner;
        feeRecipient = _feeRecipient;
        for (uint256 i; i < 5; ++i) {
            actors[i] = address(uint160(0x30000 + i));
        }
        tok.mint(actors[0], type(uint128).max);
        vm.prank(actors[0]);
        tok.approve(address(factory), type(uint256).max);
    }

    function _randomSplit(uint256 seed) internal view returns (address[] memory a, uint96[] memory b) {
        uint256 n = (seed % 4) + 1;
        a = new address[](n);
        b = new uint96[](n);
        uint256 remaining = 10_000;
        for (uint256 i; i < n; ++i) {
            a[i] = actors[uint256(keccak256(abi.encode(seed, "a", i))) % 5];
            if (i == n - 1) {
                b[i] = uint96(remaining);
            } else {
                uint256 part = uint256(keccak256(abi.encode(seed, "b", i))) % (remaining + 1);
                b[i] = uint96(part);
                remaining -= part;
            }
        }
    }

    function createSplit(uint256 seed) external {
        if (factory.splitCount() >= 6) return;
        (address[] memory a, uint96[] memory b) = _randomSplit(seed);
        vm.prank(actors[0]);
        factory.createSplit(a, b);
    }

    function updateSplit(uint256 idSeed, uint256 seed) external {
        uint256 count = factory.splitCount();
        if (count == 0) return;
        uint256 id = (idSeed % count) + 1;
        (address[] memory a, uint96[] memory b) = _randomSplit(seed);
        vm.prank(actors[0]);
        factory.updateSplit(id, a, b);
    }

    function deposit(uint256 idSeed, uint256 amount) external {
        uint256 count = factory.splitCount();
        if (count == 0) return;
        uint256 id = (idSeed % count) + 1;
        amount = bound(amount, 1, 1e12);
        (, uint256 fee) = factory.previewDeposit(amount);
        ghostFees += fee;
        ghostDeposits += amount;
        uint256 v = factory.splitVersion(id);
        vm.prank(actors[0]);
        factory.deposit(id, amount, v);
    }

    function distribute(uint256 idSeed) external {
        uint256 count = factory.splitCount();
        if (count == 0) return;
        uint256 id = (idSeed % count) + 1;
        if (factory.splitBalance(id) == 0) return;
        factory.distribute(id);
    }

    function claim(uint256 idSeed, uint256 actorSeed) external {
        uint256 count = factory.splitCount();
        if (count == 0) return;
        uint256 id = (idSeed % count) + 1;
        address who = actors[actorSeed % 5];
        if (factory.claimable(id, who) == 0 || tok.blocked(who)) return;
        factory.claim(id, who);
    }

    function claimTo(uint256 idSeed, uint256 actorSeed, uint256 toSeed) external {
        uint256 count = factory.splitCount();
        if (count == 0) return;
        uint256 id = (idSeed % count) + 1;
        address who = actors[actorSeed % 5];
        address to = actors[toSeed % 5];
        if (factory.claimable(id, who) == 0 || tok.blocked(to)) return;
        vm.prank(who);
        factory.claimTo(id, to);
    }

    function rescueDust(uint256 idSeed) external {
        uint256 count = factory.splitCount();
        if (count == 0) return;
        uint256 id = (idSeed % count) + 1;
        if (factory.pendingCreatorDust(id) == 0 || tok.blocked(actors[0])) return;
        vm.prank(actors[0]);
        factory.rescueDust(id);
    }

    function toggleBlock(uint256 actorSeed, bool flag) external {
        tok.setBlocked(actors[actorSeed % 5], flag);
    }

    function setFee(uint256 bps) external {
        bps = bound(bps, 0, 500);
        vm.prank(owner);
        factory.setFeeBps(uint16(bps));
    }

    /// @dev Sum of everything the factory owes: split balances + creator dust + claimable credits.
    function liabilities() external view returns (uint256 total) {
        uint256 count = factory.splitCount();
        for (uint256 id = 1; id <= count; ++id) {
            total += factory.splitBalance(id) + factory.pendingCreatorDust(id);
            for (uint256 i; i < 5; ++i) {
                total += factory.claimable(id, actors[i]);
            }
        }
    }
}

contract SplitFactoryInvariantTest is SplitFactoryTestBase {
    SplitFactoryHandler internal handler;

    function _deployToken() internal override returns (address) {
        return address(new MockBlocklistERC20());
    }

    function setUp() public override {
        super.setUp();
        handler = new SplitFactoryHandler(factory, MockBlocklistERC20(address(usdc)), owner, feeRecipient);

        targetContract(address(handler));
        bytes4[] memory sels = new bytes4[](9);
        sels[0] = SplitFactoryHandler.createSplit.selector;
        sels[1] = SplitFactoryHandler.updateSplit.selector;
        sels[2] = SplitFactoryHandler.deposit.selector;
        sels[3] = SplitFactoryHandler.distribute.selector;
        sels[4] = SplitFactoryHandler.claim.selector;
        sels[5] = SplitFactoryHandler.claimTo.selector;
        sels[6] = SplitFactoryHandler.rescueDust.selector;
        sels[7] = SplitFactoryHandler.toggleBlock.selector;
        sels[8] = SplitFactoryHandler.setFee.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: sels}));
    }

    /// @dev Factory USDC balance == sum of splitBalance + pending dust + claimable liabilities.
    function invariant_FactoryBalanceEqualsLiabilities() public view {
        assertEq(usdc.balanceOf(address(factory)), handler.liabilities());
    }

    /// @dev Fee recipient receives exactly the fees implied by deposits (never from payouts).
    function invariant_FeeRecipientBalanceEqualsGhostFees() public view {
        assertEq(usdc.balanceOf(feeRecipient), handler.ghostFees());
    }

    /// @dev Fee never exceeds the 5% cap on cumulative deposits.
    function invariant_FeesWithinCap() public view {
        assertLe(handler.ghostFees(), handler.ghostDeposits() * 5 / 100);
    }
}
