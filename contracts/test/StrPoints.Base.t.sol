// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SplitFactory} from "../SplitFactory.sol";
import {StrPoints} from "../StrPoints.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";
import {MockTokenMessengerV2} from "../test-helpers/MockTokenMessengerV2.sol";

/// @dev Independent reference of the tier / cap tables (does not call the contract).
abstract contract StrPointsRef is Test {
    function _refTier(uint256 amount) internal pure returns (bool q, uint8 tier, uint256 pts) {
        if (amount < 1_000_000) return (false, 0, 0);
        if (amount < 10_000_000) return (true, 0, 5);
        if (amount < 50_000_000) return (true, 1, 25);
        if (amount < 100_000_000) return (true, 2, 50);
        if (amount < 250_000_000) return (true, 3, 75);
        if (amount < 1_000_000_000) return (true, 4, 100);
        return (true, 5, 150);
    }

    function _refCap(uint8 tier) internal pure returns (uint256) {
        uint16[6] memory caps = [uint16(50), 75, 100, 150, 200, 600];
        return caps[tier > 5 ? 5 : tier];
    }
}

/// @dev Shared fixtures for StrPoints tests. No test functions here.
abstract contract StrPointsTestBase is StrPointsRef {
    uint16 internal constant FEE_BPS = 50; // 0.5%
    uint256 internal constant UNIT = 1e6;
    uint256 internal constant DAY = 86400;

    // One representative gross amount per tier (exact lower threshold).
    uint256 internal constant A0 = 1e6; // tier 0 -> 5 pts,  cap 50
    uint256 internal constant A1 = 10e6; // tier 1 -> 25 pts, cap 75
    uint256 internal constant A2 = 50e6; // tier 2 -> 50 pts, cap 100
    uint256 internal constant A3 = 100e6; // tier 3 -> 75 pts, cap 150
    uint256 internal constant A4 = 250e6; // tier 4 -> 100 pts, cap 200
    uint256 internal constant A5 = 1000e6; // tier 5 -> 150 pts, cap 600

    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal alice = makeAddr("alice"); // split creator
    address internal bob = makeAddr("bob"); // recipient 60%
    address internal carol = makeAddr("carol"); // recipient 40%
    address internal dave = makeAddr("dave"); // depositor
    address internal eve = makeAddr("eve"); // stranger

    MockERC20 internal usdc;
    SplitFactory internal factory;
    StrPoints internal sp;
    MockTokenMessengerV2 internal messenger;
    uint32 internal constant DOMAIN = 6;

    /// @dev Day-aligned start so day arithmetic is easy (day index 1000).
    function _start(uint256 dayLen) internal pure returns (uint256) {
        return 1000 * dayLen;
    }

    function setUp() public virtual {
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        factory = new SplitFactory(address(usdc), owner, feeRecipient, FEE_BPS);
        messenger = new MockTokenMessengerV2();
        sp = new StrPoints(address(factory), address(usdc), DAY, address(messenger), DOMAIN);
        vm.warp(_start(DAY));
    }

    function _newPoints(uint256 dayLen) internal returns (StrPoints p) {
        p = new StrPoints(address(factory), address(usdc), dayLen, address(messenger), DOMAIN);
    }

    function _distViaPoints(StrPoints p, address who, uint256 id) internal {
        vm.prank(who);
        p.distribute(id);
    }

    /// @dev Mint USDC to `who` and approve `spender`.
    function _fund(address who, uint256 amt, address spender) internal {
        usdc.mint(who, amt);
        vm.prank(who);
        usdc.approve(spender, type(uint256).max);
    }

    function _a2(address x, address y) internal pure returns (address[] memory a) {
        a = new address[](2);
        a[0] = x;
        a[1] = y;
    }

    function _b2(uint96 x, uint96 y) internal pure returns (uint96[] memory b) {
        b = new uint96[](2);
        b[0] = x;
        b[1] = y;
    }

    /// @dev alice creates a 60% bob / 40% carol split.
    function _createDefault() internal returns (uint256 id) {
        vm.prank(alice);
        id = factory.createSplit(_a2(bob, carol), _b2(6000, 4000));
    }

    function _depViaPoints(StrPoints p, address from, uint256 id, uint256 amount) internal {
        uint256 v = factory.splitVersion(id);
        vm.prank(from);
        p.depositToSplit(id, amount, v);
    }

    /// @dev Mint `amount` to `from`, approve `p`, then deposit through `p`.
    function _mintDep(StrPoints p, address from, uint256 id, uint256 amount) internal {
        usdc.mint(from, amount);
        vm.prank(from);
        usdc.approve(address(p), type(uint256).max);
        _depViaPoints(p, from, id, amount);
    }

    /// @dev Deposit straight into the factory (no points involved).
    function _directDeposit(uint256 id, uint256 amount) internal {
        address funder = makeAddr("directFunder");
        usdc.mint(funder, amount);
        vm.startPrank(funder);
        usdc.approve(address(factory), amount);
        factory.deposit(id, amount, factory.splitVersion(id));
        vm.stopPrank();
    }

    function _checkIn(StrPoints p, address who) internal {
        vm.prank(who);
        p.checkIn();
    }

    function _status(StrPoints p, address who) internal view returns (uint256 e, uint256 c, uint8 t, bool h) {
        return p.activityStatus(who);
    }

    function _assertStatus(StrPoints p, address who, uint256 e, uint256 c, uint8 t, bool h) internal view {
        (uint256 ge, uint256 gc, uint8 gt, bool gh) = p.activityStatus(who);
        assertEq(ge, e, "earnedToday");
        assertEq(gc, c, "capToday");
        assertEq(gt, t, "tierToday");
        assertEq(gh, h, "hasTier");
    }

    function _assertClean(StrPoints p) internal view {
        assertEq(usdc.balanceOf(address(p)), 0, "sp holds usdc");
        assertEq(usdc.allowance(address(p), address(factory)), 0, "lingering allowance");
    }

    /// @dev Mint `amt` USDC to `who` and approve `p` for the gross amount.
    function _fundBridge(StrPoints p, address who, uint256 amt) internal {
        usdc.mint(who, amt);
        vm.prank(who);
        usdc.approve(address(p), type(uint256).max);
    }

    /// @dev Bridge `amt` as `who` (maxFee 0, fast finality, recipient = who, accept up to 500 bps).
    function _bridgeAs(StrPoints p, address who, uint256 amt) internal {
        vm.prank(who);
        p.bridge(amt, 0, 1000, who, 500);
    }

    /// @dev Fund + bridge in one step.
    function _fundAndBridge(StrPoints p, address who, uint256 amt) internal {
        _fundBridge(p, who, amt);
        _bridgeAs(p, who, amt);
    }
}
