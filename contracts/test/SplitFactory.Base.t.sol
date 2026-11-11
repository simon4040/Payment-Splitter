// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SplitFactory} from "../SplitFactory.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";

interface IMockToken {
    function mint(address to, uint256 amount) external;
    function balanceOf(address who) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @dev Shared fixtures. No test functions here (every category inherits this).
abstract contract SplitFactoryTestBase is Test {
    uint16 internal constant FEE_BPS = 100; // 1%
    uint256 internal constant UNIT = 1e6;

    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal alice = makeAddr("alice"); // creator / depositor
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");
    address internal eve = makeAddr("eve");

    IMockToken internal usdc;
    SplitFactory internal factory;

    function _deployToken() internal virtual returns (address) {
        return address(new MockERC20("Mock USDC", "mUSDC", 6));
    }

    function setUp() public virtual {
        usdc = IMockToken(_deployToken());
        factory = new SplitFactory(address(usdc), owner, feeRecipient, FEE_BPS);
        _fund(alice, 1_000_000 * UNIT);
        _fund(eve, 1_000_000 * UNIT);
    }

    function _fund(address who, uint256 amt) internal {
        usdc.mint(who, amt);
        vm.prank(who);
        usdc.approve(address(factory), type(uint256).max);
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

    function _a1(address x) internal pure returns (address[] memory a) {
        a = new address[](1);
        a[0] = x;
    }

    function _b1(uint96 x) internal pure returns (uint96[] memory b) {
        b = new uint96[](1);
        b[0] = x;
    }

    function _create(address creator, address[] memory a, uint96[] memory b) internal returns (uint256 id) {
        vm.prank(creator);
        id = factory.createSplit(a, b);
    }

    /// @dev alice creates a 60% bob / 40% carol split.
    function _createDefault() internal returns (uint256) {
        return _create(alice, _a2(bob, carol), _b2(6000, 4000));
    }

    /// @dev Deposit using the split's current version.
    function _dep(address from, uint256 id, uint256 amount) internal {
        uint256 v = factory.splitVersion(id);
        vm.prank(from);
        factory.deposit(id, amount, v);
    }
}
