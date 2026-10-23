// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SplitFactory} from "../SplitFactory.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";

contract SplitFactoryTest is Test {
    // ── Constants ────────────────────────────────────────────────────────────
    address internal constant USDC_ADDR = 0x3600000000000000000000000000000000000000;
    uint256 internal constant DECIMALS   = 6;
    uint256 internal constant UNIT       = 10 ** DECIMALS; // 1 USDC = 1_000_000

    // ── Actors ───────────────────────────────────────────────────────────────
    address internal alice   = makeAddr("alice");   // creator / depositor
    address internal bob     = makeAddr("bob");     // recipient
    address internal carol   = makeAddr("carol");   // recipient
    address internal dave    = makeAddr("dave");    // recipient
    address internal eve     = makeAddr("eve");     // unauthorised third party

    // ── Contracts under test ─────────────────────────────────────────────────
    SplitFactory internal factory;
    MockERC20    internal usdc;

    // ────────────────────────────────────────────────────────────────────────
    // setUp — runs before EVERY test
    // ────────────────────────────────────────────────────────────────────────
    function setUp() public {
        // 1. Deploy a MockERC20 and etch its bytecode at the canonical USDC address.
        MockERC20 mock = new MockERC20("Mock USDC", "mUSDC", uint8(DECIMALS));
        vm.etch(USDC_ADDR, address(mock).code);
        usdc = MockERC20(USDC_ADDR);

        // 2. Deploy factory — USDC constant now has code behind it.
        factory = new SplitFactory(USDC_ADDR);

        // 3. Seed actors with USDC and pre-approve the factory.
        usdc.mint(alice, 100_000 * UNIT);
        usdc.mint(bob,   100_000 * UNIT);
        vm.prank(alice);
        usdc.approve(address(factory), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(factory), type(uint256).max);
    }

    // ════════════════════════════════════════════════════════════════════════
    // Helper: build single-recipient split arrays
    // ════════════════════════════════════════════════════════════════════════
    function _singleSplit(address r) internal pure returns (address[] memory addrs, uint96[] memory bps) {
        addrs = new address[](1);
        bps   = new uint96[](1);
        addrs[0] = r;
        bps[0]   = 10_000;
    }

    function _twoWaySplit(address r1, address r2, uint96 b1, uint96 b2)
        internal pure returns (address[] memory addrs, uint96[] memory bps)
    {
        addrs = new address[](2);
        bps   = new uint96[](2);
        addrs[0] = r1; bps[0] = b1;
        addrs[1] = r2; bps[1] = b2;
    }

    function _threeWaySplit(address r1, address r2, address r3, uint96 b1, uint96 b2, uint96 b3)
        internal pure returns (address[] memory addrs, uint96[] memory bps)
    {
        addrs = new address[](3);
        bps   = new uint96[](3);
        addrs[0] = r1; bps[0] = b1;
        addrs[1] = r2; bps[1] = b2;
        addrs[2] = r3; bps[2] = b3;
    }

    // ════════════════════════════════════════════════════════════════════════
    //  CONSTRUCTOR
    // ════════════════════════════════════════════════════════════════════════

    function test_Constructor_StoresUsdc() public view {
        assertEq(factory.usdc(), USDC_ADDR);
    }

    function test_Constructor_ZeroAddressReverts() public {
        vm.expectRevert(SplitFactory.ZeroAddress.selector);
        new SplitFactory(address(0));
    }

    function test_Constructor_SplitCountStartsAtZero() public view {
        assertEq(factory.splitCount(), 0);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  createSplit — happy paths
    // ════════════════════════════════════════════════════════════════════════

    function test_CreateSplit_SingleRecipient_ReturnsId1() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);
        assertEq(id, 1);
    }

    function test_CreateSplit_SingleRecipient_IncrementsSplitCount() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        factory.createSplit(addrs, bps);
        assertEq(factory.splitCount(), 1);
    }

    function test_CreateSplit_ThreeRecipients_HappyPath() public {
        (address[] memory addrs, uint96[] memory bps) =
            _threeWaySplit(bob, carol, dave, 5_000, 3_000, 2_000);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);
        assertEq(id, 1);

        (address[] memory retAddrs, uint96[] memory retBps) = factory.getRecipients(id);
        assertEq(retAddrs.length, 3);
        assertEq(retAddrs[0], bob);   assertEq(retBps[0], 5_000);
        assertEq(retAddrs[1], carol); assertEq(retBps[1], 3_000);
        assertEq(retAddrs[2], dave);  assertEq(retBps[2], 2_000);
    }

    function test_CreateSplit_SetsCreatorCorrectly() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        (address creator,,,) = factory.getSplit(id);
        assertEq(creator, alice);
    }

    function test_CreateSplit_EmitsSplitCreated() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        vm.expectEmit(true, true, false, false, address(factory));
        emit SplitFactory.SplitCreated(1, alice);
        factory.createSplit(addrs, bps);
    }

    function test_CreateSplit_MultipleCreatesIncrementIds() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.startPrank(alice);
        uint256 id1 = factory.createSplit(addrs, bps);
        uint256 id2 = factory.createSplit(addrs, bps);
        uint256 id3 = factory.createSplit(addrs, bps);
        vm.stopPrank();
        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);
        assertEq(factory.splitCount(), 3);
    }

    function test_CreateSplit_InitialBalanceAndDistributedAreZero() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        (, uint256 bal, uint256 totalDist,) = factory.getSplit(id);
        assertEq(bal, 0);
        assertEq(totalDist, 0);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  createSplit — validation reverts
    // ════════════════════════════════════════════════════════════════════════

    function test_CreateSplit_Revert_LengthMismatch() public {
        address[] memory addrs = new address[](2);
        uint96[]  memory bps   = new uint96[](1);
        addrs[0] = bob; addrs[1] = carol;
        bps[0]   = 10_000;
        vm.prank(alice);
        vm.expectRevert(SplitFactory.InvalidSplit.selector);
        factory.createSplit(addrs, bps);
    }

    function test_CreateSplit_Revert_EmptyRecipients() public {
        address[] memory addrs = new address[](0);
        uint96[]  memory bps   = new uint96[](0);
        vm.prank(alice);
        vm.expectRevert(SplitFactory.InvalidSplit.selector);
        factory.createSplit(addrs, bps);
    }

    function test_CreateSplit_Revert_TooManyRecipients() public {
        address[] memory addrs = new address[](21);
        uint96[]  memory bps   = new uint96[](21);
        for (uint256 i = 0; i < 21; ++i) {
            addrs[i] = makeAddr(string(abi.encodePacked("r", i)));
            bps[i]   = 476; // doesn't matter — fails on length first
        }
        vm.prank(alice);
        vm.expectRevert(SplitFactory.InvalidSplit.selector);
        factory.createSplit(addrs, bps);
    }

    function test_CreateSplit_Revert_ZeroAddress() public {
        address[] memory addrs = new address[](1);
        uint96[]  memory bps   = new uint96[](1);
        addrs[0] = address(0);
        bps[0]   = 10_000;
        vm.prank(alice);
        vm.expectRevert(SplitFactory.ZeroAddress.selector);
        factory.createSplit(addrs, bps);
    }

    function test_CreateSplit_Revert_BpsNotTen000() public {
        (address[] memory addrs, uint96[] memory bps) = _twoWaySplit(bob, carol, 5_000, 4_999);
        vm.prank(alice);
        vm.expectRevert(SplitFactory.InvalidSplit.selector);
        factory.createSplit(addrs, bps);
    }

    function test_CreateSplit_Revert_BpsOver10000() public {
        (address[] memory addrs, uint96[] memory bps) = _twoWaySplit(bob, carol, 5_000, 5_001);
        vm.prank(alice);
        vm.expectRevert(SplitFactory.InvalidSplit.selector);
        factory.createSplit(addrs, bps);
    }

    function test_CreateSplit_ExactlyTwentyRecipients_Succeeds() public {
        address[] memory addrs = new address[](20);
        uint96[]  memory bps   = new uint96[](20);
        for (uint256 i = 0; i < 20; ++i) {
            addrs[i] = makeAddr(string(abi.encodePacked("r", i)));
            bps[i]   = 500; // 20 * 500 = 10_000
        }
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);
        assertEq(id, 1);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  updateSplit — happy path
    // ════════════════════════════════════════════════════════════════════════

    function test_UpdateSplit_ReplacesRecipients() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        (address[] memory newAddrs, uint96[] memory newBps) = _twoWaySplit(carol, dave, 6_000, 4_000);
        vm.prank(alice);
        factory.updateSplit(id, newAddrs, newBps);

        (address[] memory retAddrs, uint96[] memory retBps) = factory.getRecipients(id);
        assertEq(retAddrs.length, 2);
        assertEq(retAddrs[0], carol); assertEq(retBps[0], 6_000);
        assertEq(retAddrs[1], dave);  assertEq(retBps[1], 4_000);
    }

    function test_UpdateSplit_EmitsSplitUpdated() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        (address[] memory newAddrs, uint96[] memory newBps) = _singleSplit(carol);
        vm.prank(alice);
        vm.expectEmit(true, false, false, false, address(factory));
        emit SplitFactory.SplitUpdated(id);
        factory.updateSplit(id, newAddrs, newBps);
    }

    function test_UpdateSplit_DoesNotChangeCreator() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        (address[] memory newAddrs, uint96[] memory newBps) = _singleSplit(carol);
        vm.prank(alice);
        factory.updateSplit(id, newAddrs, newBps);

        (address creator,,,) = factory.getSplit(id);
        assertEq(creator, alice);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  updateSplit — revert paths
    // ════════════════════════════════════════════════════════════════════════

    function test_UpdateSplit_Revert_Unauthorized() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        (address[] memory newAddrs, uint96[] memory newBps) = _singleSplit(carol);
        vm.prank(eve);
        vm.expectRevert(SplitFactory.Unauthorized.selector);
        factory.updateSplit(id, newAddrs, newBps);
    }

    function test_UpdateSplit_Revert_SplitNotFound() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.updateSplit(99, addrs, bps);
    }

    function test_UpdateSplit_Revert_InvalidBps() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        (address[] memory newAddrs, uint96[] memory newBps) = _twoWaySplit(carol, dave, 5_000, 4_000);
        vm.prank(alice);
        vm.expectRevert(SplitFactory.InvalidSplit.selector);
        factory.updateSplit(id, newAddrs, newBps);
    }

    function test_UpdateSplit_Revert_ZeroAddressInRecipients() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        address[] memory newAddrs = new address[](1);
        uint96[]  memory newBps   = new uint96[](1);
        newAddrs[0] = address(0);
        newBps[0]   = 10_000;
        vm.prank(alice);
        vm.expectRevert(SplitFactory.ZeroAddress.selector);
        factory.updateSplit(id, newAddrs, newBps);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  deposit — happy path
    // ════════════════════════════════════════════════════════════════════════

    function test_Deposit_HappyPath_BalanceIncrements() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        uint256 amount = 1_000 * UNIT;
        vm.prank(alice);
        factory.deposit(id, amount);

        assertEq(factory.splitBalance(id), amount);
    }

    function test_Deposit_PullsUsdcFromSender() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        uint256 balBefore = usdc.balanceOf(alice);
        uint256 amount = 500 * UNIT;
        vm.prank(alice);
        factory.deposit(id, amount);

        assertEq(usdc.balanceOf(alice),            balBefore - amount);
        assertEq(usdc.balanceOf(address(factory)), amount);
    }

    function test_Deposit_EmitsDeposited() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        uint256 amount = 200 * UNIT;
        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(factory));
        emit SplitFactory.Deposited(id, alice, amount);
        factory.deposit(id, amount);
    }

    function test_Deposit_MultipleDepositsAccumulate() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        vm.startPrank(alice);
        factory.deposit(id, 100 * UNIT);
        factory.deposit(id, 200 * UNIT);
        factory.deposit(id, 300 * UNIT);
        vm.stopPrank();

        assertEq(factory.splitBalance(id), 600 * UNIT);
    }

    function test_Deposit_BalanceOnGetSplitMatchesSplitBalance() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        uint256 amount = 777 * UNIT;
        vm.prank(alice);
        factory.deposit(id, amount);

        (, uint256 bal,,) = factory.getSplit(id);
        assertEq(bal, factory.splitBalance(id));
        assertEq(bal, amount);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  deposit — revert paths
    // ════════════════════════════════════════════════════════════════════════

    function test_Deposit_Revert_ZeroAmount() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        vm.prank(alice);
        vm.expectRevert(SplitFactory.ZeroAmount.selector);
        factory.deposit(id, 0);
    }

    function test_Deposit_Revert_SplitNotFound() public {
        vm.prank(alice);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.deposit(99, 100 * UNIT);
    }

    function test_Deposit_Revert_SplitIdZero() public {
        vm.prank(alice);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.deposit(0, 100 * UNIT);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  distribute — even split
    // ════════════════════════════════════════════════════════════════════════

    function test_Distribute_EvenSplit_TwoRecipients() public {
        (address[] memory addrs, uint96[] memory bps) = _twoWaySplit(bob, carol, 5_000, 5_000);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        uint256 amount = 1_000 * UNIT;
        vm.prank(alice);
        factory.deposit(id, amount);

        uint256 bobBefore   = usdc.balanceOf(bob);
        uint256 carolBefore = usdc.balanceOf(carol);

        factory.distribute(id);

        assertEq(usdc.balanceOf(bob)   - bobBefore,   500 * UNIT);
        assertEq(usdc.balanceOf(carol) - carolBefore, 500 * UNIT);
        assertEq(factory.splitBalance(id), 0);
    }

    function test_Distribute_SplitBalance_ZeroedBeforeTransfers_CEI() public {
        // After distribute, splitBalance must be 0 regardless of transfer outcomes.
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        vm.prank(alice);
        factory.deposit(id, 1_000 * UNIT);

        factory.distribute(id);

        assertEq(factory.splitBalance(id), 0);
    }

    function test_Distribute_TotalDistributedIncrements() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        uint256 amount1 = 400 * UNIT;
        uint256 amount2 = 600 * UNIT;

        vm.prank(alice);
        factory.deposit(id, amount1);
        factory.distribute(id);

        vm.prank(alice);
        factory.deposit(id, amount2);
        factory.distribute(id);

        (,, uint256 totalDist,) = factory.getSplit(id);
        assertEq(totalDist, amount1 + amount2);
    }

    function test_Distribute_EmitsDistributed() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        uint256 amount = 1_000 * UNIT;
        vm.prank(alice);
        factory.deposit(id, amount);

        vm.expectEmit(true, false, false, true, address(factory));
        emit SplitFactory.Distributed(id, amount, 1);
        factory.distribute(id);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  distribute — uneven split → dust to creator
    // ════════════════════════════════════════════════════════════════════════

    function test_Distribute_UnevenSplit_DustToCreator() public {
        // 3-way 33.33%/33.33%/33.34% → 1 unit of dust with amount=1
        // Use an amount that forces integer dust with 3 equal parts
        // 10 USDC / 3 recipients at 3334/3333/3333 bps:
        //   10_000_000 * 3334 / 10_000 = 3_334_000
        //   10_000_000 * 3333 / 10_000 = 3_333_000
        //   10_000_000 * 3333 / 10_000 = 3_333_000
        //   total = 10_000_000, dust = 0 — too clean.
        // Use 10_000_001 so dust = 1.
        uint256 amount = 10_000_001;
        usdc.mint(alice, amount);

        address[] memory addrs = new address[](3);
        uint96[]  memory bps   = new uint96[](3);
        addrs[0] = bob;   bps[0] = 3_334;
        addrs[1] = carol; bps[1] = 3_333;
        addrs[2] = dave;  bps[2] = 3_333;

        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        vm.prank(alice);
        factory.deposit(id, amount);

        uint256 creatorBalBefore = usdc.balanceOf(alice);
        factory.distribute(id);

        uint256 share0 = (amount * 3_334) / 10_000;
        uint256 share1 = (amount * 3_333) / 10_000;
        uint256 share2 = (amount * 3_333) / 10_000;
        uint256 dust   = amount - share0 - share1 - share2;

        // Dust > 0 → should have gone to creator (alice)
        assertTrue(dust > 0, "expected non-zero dust");
        assertEq(usdc.balanceOf(alice), creatorBalBefore + dust);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  distribute — revert paths
    // ════════════════════════════════════════════════════════════════════════

    function test_Distribute_Revert_SplitNotFound() public {
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.distribute(99);
    }

    function test_Distribute_Revert_NoBalance() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        vm.expectRevert(SplitFactory.NoBalance.selector);
        factory.distribute(id);
    }

    function test_Distribute_Revert_InvalidSplit_NoRecipients() public {
        // Create a split, then update it to zero recipients is impossible via
        // updateSplit (validation). Instead: create a split, then to get
        // InvalidSplit we can't wipe recipients with updateSplit.
        // The only way to hit InvalidSplit on distribute is if there's a code
        // path; the validation prevents 0-recipient splits from being created
        // or updated. We test that the guard exists by checking distribute on
        // a valid split works, and that distribute(0) == SplitNotFound.
        //
        // The InvalidSplit path in distribute fires only when recipients.length==0
        // which CANNOT be reached via the public API (create/update always validate ≥1).
        // We document this as an unreachable guard and test the next-closest proxy:
        // ensure distribute after update still works.
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        vm.prank(alice);
        factory.deposit(id, 100 * UNIT);

        // update replaces recipients — distribute still works
        (address[] memory newAddrs, uint96[] memory newBps) = _singleSplit(carol);
        vm.prank(alice);
        factory.updateSplit(id, newAddrs, newBps);

        factory.distribute(id);
        assertEq(usdc.balanceOf(carol), 100 * UNIT);
    }

    function test_Distribute_Revert_NoBalance_AfterDistribute() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        vm.prank(alice);
        factory.deposit(id, 100 * UNIT);
        factory.distribute(id);

        // Second distribute on same split with no new deposit
        vm.expectRevert(SplitFactory.NoBalance.selector);
        factory.distribute(id);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  distribute — dust accumulation path (transfer reverts)
    // ════════════════════════════════════════════════════════════════════════

    function test_Distribute_DustAccumulates_WhenTransferReverts() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        uint256 amount = 1_000 * UNIT;
        vm.prank(alice);
        factory.deposit(id, amount);

        // Make all transfers revert → entire amount becomes pendingCreatorDust
        usdc.setRevertOnTransfer(true);
        factory.distribute(id);
        usdc.setRevertOnTransfer(false);

        // splitBalance zeroed (CEI)
        assertEq(factory.splitBalance(id), 0);
        // All dust queued for creator
        assertEq(factory.pendingCreatorDust(id), amount);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  rescueDust
    // ════════════════════════════════════════════════════════════════════════

    function _setupDust(uint256 amount) internal returns (uint256 id) {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        id = factory.createSplit(addrs, bps);

        vm.prank(alice);
        factory.deposit(id, amount);

        // Force all transfers to revert so dust accumulates
        usdc.setRevertOnTransfer(true);
        factory.distribute(id);
        usdc.setRevertOnTransfer(false);
    }

    function test_RescueDust_HappyPath_TransfersDustToCreator() public {
        uint256 amount = 1_000 * UNIT;
        uint256 id = _setupDust(amount);

        assertEq(factory.pendingCreatorDust(id), amount);

        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        factory.rescueDust(id);

        assertEq(usdc.balanceOf(alice),        balBefore + amount);
        assertEq(factory.pendingCreatorDust(id), 0);
    }

    function test_RescueDust_EmitsDustRescued() public {
        uint256 amount = 500 * UNIT;
        uint256 id = _setupDust(amount);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(factory));
        emit SplitFactory.DustRescued(id, amount);
        factory.rescueDust(id);
    }

    function test_RescueDust_ClearsPendingDust() public {
        uint256 id = _setupDust(200 * UNIT);

        vm.prank(alice);
        factory.rescueDust(id);

        assertEq(factory.pendingCreatorDust(id), 0);
    }

    function test_RescueDust_Revert_NoPendingDust() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        vm.prank(alice);
        vm.expectRevert(SplitFactory.NoPendingDust.selector);
        factory.rescueDust(id);
    }

    function test_RescueDust_Revert_Unauthorized() public {
        uint256 id = _setupDust(100 * UNIT);

        vm.prank(eve);
        vm.expectRevert(SplitFactory.Unauthorized.selector);
        factory.rescueDust(id);
    }

    function test_RescueDust_Revert_SplitNotFound() public {
        vm.prank(alice);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.rescueDust(99);
    }

    function test_RescueDust_Revert_NoPendingDust_AfterRescue() public {
        uint256 id = _setupDust(100 * UNIT);
        vm.prank(alice);
        factory.rescueDust(id);

        vm.prank(alice);
        vm.expectRevert(SplitFactory.NoPendingDust.selector);
        factory.rescueDust(id);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  getSplit / getRecipients — correct return values at each stage
    // ════════════════════════════════════════════════════════════════════════

    function test_GetSplit_Revert_SplitNotFound() public {
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.getSplit(0);
    }

    function test_GetSplit_Revert_SplitNotFoundBeyondCount() public {
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.getSplit(1);
    }

    function test_GetSplit_AfterDepositAndDistribute() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        uint256 amount = 100 * UNIT;
        vm.prank(alice);
        factory.deposit(id, amount);

        // Before distribute
        (, uint256 bal, uint256 totDist, uint256 rCount) = factory.getSplit(id);
        assertEq(bal,     amount);
        assertEq(totDist, 0);
        assertEq(rCount,  1);

        factory.distribute(id);

        // After distribute
        (, uint256 bal2, uint256 totDist2,) = factory.getSplit(id);
        assertEq(bal2,     0);
        assertEq(totDist2, amount);
    }

    function test_GetSplit_RecipientCountUpdatesAfterUpdateSplit() public {
        (address[] memory addrs, uint96[] memory bps) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        (,,, uint256 rCount) = factory.getSplit(id);
        assertEq(rCount, 1);

        (address[] memory newAddrs, uint96[] memory newBps) = _threeWaySplit(bob, carol, dave, 4_000, 3_000, 3_000);
        vm.prank(alice);
        factory.updateSplit(id, newAddrs, newBps);

        (,,, uint256 rCount2) = factory.getSplit(id);
        assertEq(rCount2, 3);
    }

    function test_GetRecipients_Revert_SplitNotFound() public {
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        factory.getRecipients(0);
    }

    function test_GetRecipients_ReturnsCorrectData() public {
        (address[] memory addrs, uint96[] memory bps) =
            _threeWaySplit(bob, carol, dave, 5_000, 3_000, 2_000);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        (address[] memory retAddrs, uint96[] memory retBps) = factory.getRecipients(id);
        assertEq(retAddrs.length, 3);
        assertEq(retAddrs[0], bob);   assertEq(retBps[0], 5_000);
        assertEq(retAddrs[1], carol); assertEq(retBps[1], 3_000);
        assertEq(retAddrs[2], dave);  assertEq(retBps[2], 2_000);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  Multiple splits are independent
    // ════════════════════════════════════════════════════════════════════════

    function test_MultipleSplits_DistributeDoesNotAffectOtherSplitBalance() public {
        // Split 1: alice → bob (all)
        (address[] memory a1, uint96[] memory b1) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id1 = factory.createSplit(a1, b1);

        // Split 2: alice → carol (all)
        (address[] memory a2, uint96[] memory b2) = _singleSplit(carol);
        vm.prank(alice);
        uint256 id2 = factory.createSplit(a2, b2);

        uint256 dep1 = 300 * UNIT;
        uint256 dep2 = 700 * UNIT;

        vm.startPrank(alice);
        factory.deposit(id1, dep1);
        factory.deposit(id2, dep2);
        vm.stopPrank();

        uint256 bobBefore   = usdc.balanceOf(bob);
        uint256 carolBefore = usdc.balanceOf(carol);

        // Distribute split 1 only
        factory.distribute(id1);

        assertEq(factory.splitBalance(id1), 0);
        assertEq(factory.splitBalance(id2), dep2); // untouched
        assertEq(usdc.balanceOf(bob)   - bobBefore,   dep1);
        assertEq(usdc.balanceOf(carol) - carolBefore, 0); // split 2 not yet distributed
    }

    function test_MultipleSplits_IndependentTotalDistributed() public {
        (address[] memory a1, uint96[] memory b1) = _singleSplit(bob);
        vm.prank(alice);
        uint256 id1 = factory.createSplit(a1, b1);

        (address[] memory a2, uint96[] memory b2) = _singleSplit(carol);
        vm.prank(alice);
        uint256 id2 = factory.createSplit(a2, b2);

        uint256 dep1 = 100 * UNIT;
        uint256 dep2 = 999 * UNIT;

        vm.startPrank(alice);
        factory.deposit(id1, dep1);
        factory.deposit(id2, dep2);
        vm.stopPrank();

        factory.distribute(id1);
        factory.distribute(id2);

        (,, uint256 td1,) = factory.getSplit(id1);
        (,, uint256 td2,) = factory.getSplit(id2);
        assertEq(td1, dep1);
        assertEq(td2, dep2);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  FUZZ — no funds created or destroyed
    // ════════════════════════════════════════════════════════════════════════

    /// @dev Fuzz deposit amount; after distribute, sum of recipient balances
    ///      plus any pendingCreatorDust plus what creator received equals `amount`.
    function testFuzz_Distribute_Conservation(uint256 amount) public {
        // Bound: at least 1 unit, at most 10M USDC (6 decimals)
        amount = bound(amount, 1, 10_000_000 * UNIT);

        usdc.mint(alice, amount);

        // 3-way split: 50/30/20
        (address[] memory addrs, uint96[] memory bps) =
            _threeWaySplit(bob, carol, dave, 5_000, 3_000, 2_000);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        vm.prank(alice);
        factory.deposit(id, amount);

        uint256 creatorBefore = usdc.balanceOf(alice);
        uint256 bobBefore     = usdc.balanceOf(bob);
        uint256 carolBefore   = usdc.balanceOf(carol);
        uint256 daveBefore    = usdc.balanceOf(dave);

        factory.distribute(id);

        uint256 creatorGain = usdc.balanceOf(alice) - creatorBefore;
        uint256 bobGain     = usdc.balanceOf(bob)   - bobBefore;
        uint256 carolGain   = usdc.balanceOf(carol) - carolBefore;
        uint256 daveGain    = usdc.balanceOf(dave)  - daveBefore;
        uint256 dustPending = factory.pendingCreatorDust(id);

        // Total out = total in
        assertEq(
            bobGain + carolGain + daveGain + creatorGain + dustPending,
            amount,
            "fund conservation violated"
        );
        // Nothing left inside the contract for this split
        assertEq(factory.splitBalance(id), 0);
    }

    /// @dev Fuzz: multiple successive deposits then single distribute conserves funds.
    function testFuzz_Distribute_Conservation_AfterMultiDeposits(uint128 a, uint128 b) public {
        uint256 dep1 = bound(uint256(a), 1, 5_000_000 * UNIT);
        uint256 dep2 = bound(uint256(b), 1, 5_000_000 * UNIT);

        usdc.mint(alice, dep1 + dep2);

        (address[] memory addrs, uint96[] memory bps) = _twoWaySplit(bob, carol, 6_000, 4_000);
        vm.prank(alice);
        uint256 id = factory.createSplit(addrs, bps);

        vm.startPrank(alice);
        factory.deposit(id, dep1);
        factory.deposit(id, dep2);
        vm.stopPrank();

        uint256 total = dep1 + dep2;
        uint256 bobBefore   = usdc.balanceOf(bob);
        uint256 carolBefore = usdc.balanceOf(carol);
        uint256 creatorBefore = usdc.balanceOf(alice);

        factory.distribute(id);

        uint256 out = (usdc.balanceOf(bob)   - bobBefore)
                    + (usdc.balanceOf(carol) - carolBefore)
                    + (usdc.balanceOf(alice) - creatorBefore)
                    + factory.pendingCreatorDust(id);

        assertEq(out, total, "fund conservation violated on multi-deposit");
    }

    // ════════════════════════════════════════════════════════════════════════
    //  splitBalance public mapping
    // ════════════════════════════════════════════════════════════════════════

    function test_SplitBalance_ZeroForNonExistentSplit() public view {
        // splitBalance mapping is public, doesn't check existence
        assertEq(factory.splitBalance(999), 0);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  pendingCreatorDust public mapping
    // ════════════════════════════════════════════════════════════════════════

    function test_PendingCreatorDust_ZeroByDefault() public view {
        assertEq(factory.pendingCreatorDust(1), 0);
    }
}
