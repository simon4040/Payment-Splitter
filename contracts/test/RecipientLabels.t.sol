// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SplitFactoryTestBase} from "./SplitFactory.Base.t.sol";
import {SplitFactory} from "../SplitFactory.sol";
import {RecipientLabels} from "../RecipientLabels.sol";

contract RecipientLabelsTest is SplitFactoryTestBase {
    RecipientLabels internal labels;
    uint256 internal id; // alice creator, bob 60% / carol 40%

    function setUp() public override {
        super.setUp();
        labels = new RecipientLabels(address(factory));
        id = _createDefault();
    }

    // ---------- helpers ----------

    function _rep(string memory unit, uint256 n) internal pure returns (string memory) {
        bytes memory u = bytes(unit);
        bytes memory out = new bytes(u.length * n);
        for (uint256 i = 0; i < n; ++i) {
            for (uint256 j = 0; j < u.length; ++j) {
                out[i * u.length + j] = u[j];
            }
        }
        return string(out);
    }

    function _s1(string memory a) internal pure returns (string[] memory s) {
        s = new string[](1);
        s[0] = a;
    }

    function _s2(string memory a, string memory b) internal pure returns (string[] memory s) {
        s = new string[](2);
        s[0] = a;
        s[1] = b;
    }

    function _set(address who, uint256 splitId, address r, string memory l) internal {
        vm.prank(who);
        labels.setLabels(splitId, _a1(r), _s1(l));
    }

    function _set2(address who, uint256 splitId, string memory lb, string memory lc) internal {
        vm.prank(who);
        labels.setLabels(splitId, _a2(bob, carol), _s2(lb, lc));
    }

    function _bytesOfLen(bytes1 c, uint256 n) internal pure returns (string memory) {
        bytes memory b = new bytes(n);
        for (uint256 i = 0; i < n; ++i) {
            b[i] = c;
        }
        return string(b);
    }

    function _recips(uint256 n) internal pure returns (address[] memory a) {
        a = new address[](n);
        for (uint256 i = 0; i < n; ++i) {
            a[i] = address(uint160(0x100000 + i));
        }
    }

    function _bpsEven(uint256 n) internal pure returns (uint96[] memory b) {
        b = new uint96[](n);
        for (uint256 i = 0; i < n; ++i) {
            b[i] = uint96(10_000 / n);
        }
    }

    function _bigSplit(uint256 n) internal returns (uint256 sid, address[] memory r) {
        r = _recips(n);
        sid = _create(alice, r, _bpsEven(n));
    }

    // ---------- constructor ----------

    function test_Constructor_StoresFactoryAndConstants() public view {
        assertEq(labels.factory(), address(factory));
        assertEq(labels.MAX_LABEL_BYTES(), 64);
        assertEq(labels.MAX_BATCH(), 20);
    }

    function test_Constructor_RevertsOnZeroFactory() public {
        vm.expectRevert(RecipientLabels.ZeroAddress.selector);
        new RecipientLabels(address(0));
    }

    // ---------- setLabels happy path ----------

    function test_SetLabels_StoresAndReads() public {
        _set2(alice, id, "Landlord", "Roommate");
        assertEq(labels.labelOf(id, bob), "Landlord");
        assertEq(labels.labelOf(id, carol), "Roommate");
    }

    function test_SetLabels_EmitsLabelSetPerEntry() public {
        vm.expectEmit(true, true, false, true, address(labels));
        emit RecipientLabels.LabelSet(id, bob, "B");
        vm.expectEmit(true, true, false, true, address(labels));
        emit RecipientLabels.LabelSet(id, carol, "C");
        _set2(alice, id, "B", "C");
    }

    function test_SetLabels_EmitsOnClear() public {
        _set(alice, id, bob, "x");
        vm.expectEmit(true, true, false, true, address(labels));
        emit RecipientLabels.LabelSet(id, bob, "");
        _set(alice, id, bob, "");
    }

    function test_SetLabels_EmptyArraysNoop() public {
        vm.recordLogs();
        vm.prank(alice);
        labels.setLabels(id, new address[](0), new string[](0));
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_SetLabels_OverwriteAndOnlyTouchesListed() public {
        _set2(alice, id, "one", "two");
        _set(alice, id, bob, "uno");
        assertEq(labels.labelOf(id, bob), "uno");
        assertEq(labels.labelOf(id, carol), "two");
    }

    function test_SetLabels_EmptyClears() public {
        _set(alice, id, bob, "tag");
        _set(alice, id, bob, "");
        assertEq(labels.labelOf(id, bob), "");
    }

    function test_SetLabels_DuplicatesLastWins() public {
        address[] memory r = new address[](3);
        r[0] = bob;
        r[1] = bob;
        r[2] = bob;
        string[] memory l = new string[](3);
        l[0] = "first";
        l[1] = "second";
        l[2] = "third";
        vm.expectEmit(true, true, false, true, address(labels));
        emit RecipientLabels.LabelSet(id, bob, "first");
        vm.expectEmit(true, true, false, true, address(labels));
        emit RecipientLabels.LabelSet(id, bob, "second");
        vm.expectEmit(true, true, false, true, address(labels));
        emit RecipientLabels.LabelSet(id, bob, "third");
        vm.prank(alice);
        labels.setLabels(id, r, l);
        assertEq(labels.labelOf(id, bob), "third");
    }

    function test_SetLabels_DuplicateWithClearLastWins() public {
        address[] memory r = _a2(bob, bob);
        vm.prank(alice);
        labels.setLabels(id, r, _s2("something", ""));
        assertEq(labels.labelOf(id, bob), "");
    }

    // ---------- access control ----------

    function test_SetLabels_RevertsForNonCreators() public {
        address[5] memory callers = [bob, carol, owner, feeRecipient, eve];
        for (uint256 i = 0; i < callers.length; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(RecipientLabels.Unauthorized.selector);
            labels.setLabels(id, _a1(bob), _s1("x"));
        }
        assertEq(labels.labelOf(id, bob), "");
    }

    function test_SetLabels_CreatorSucceeds() public {
        _set(alice, id, bob, "ok");
        assertEq(labels.labelOf(id, bob), "ok");
    }

    // ---------- unknown split ----------

    function test_SetLabels_UnknownSplitReverts() public {
        uint256[3] memory ids = [uint256(0), id + 1, type(uint256).max];
        for (uint256 i = 0; i < ids.length; ++i) {
            vm.prank(alice);
            vm.expectRevert(SplitFactory.SplitNotFound.selector);
            labels.setLabels(ids[i], _a1(bob), _s1("x"));
        }
    }

    // ---------- array validation ----------

    function test_SetLabels_LengthMismatchReverts() public {
        vm.prank(alice);
        vm.expectRevert(RecipientLabels.LengthMismatch.selector);
        labels.setLabels(id, _a2(bob, carol), _s1("x"));

        vm.prank(alice);
        vm.expectRevert(RecipientLabels.LengthMismatch.selector);
        labels.setLabels(id, _a1(bob), _s2("x", "y"));

        vm.prank(alice);
        vm.expectRevert(RecipientLabels.LengthMismatch.selector);
        labels.setLabels(id, new address[](0), _s1("x"));
    }

    function test_SetLabels_ExactlyMaxBatchOk() public {
        (uint256 sid, address[] memory r) = _bigSplit(20);
        string[] memory l = new string[](20);
        for (uint256 i = 0; i < 20; ++i) {
            l[i] = string(abi.encodePacked("r", vm.toString(i)));
        }
        vm.prank(alice);
        labels.setLabels(sid, r, l);
        string[] memory got = labels.labelsOf(sid, r);
        for (uint256 i = 0; i < 20; ++i) {
            assertEq(got[i], l[i]);
        }
    }

    function test_SetLabels_OverMaxBatchReverts() public {
        (uint256 sid, address[] memory r) = _bigSplit(20);
        address[] memory r21 = new address[](21);
        string[] memory l21 = new string[](21);
        for (uint256 i = 0; i < 20; ++i) {
            r21[i] = r[i];
        }
        r21[20] = r[0];
        vm.prank(alice);
        vm.expectRevert(RecipientLabels.TooMany.selector);
        labels.setLabels(sid, r21, l21);
    }

    function test_SetLabels_NotARecipientReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RecipientLabels.NotARecipient.selector, dave));
        labels.setLabels(id, _a1(dave), _s1("x"));

        // creator is not a recipient either
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RecipientLabels.NotARecipient.selector, alice));
        labels.setLabels(id, _a1(alice), _s1("x"));

        // zero address
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RecipientLabels.NotARecipient.selector, address(0)));
        labels.setLabels(id, _a1(address(0)), _s1("x"));
    }

    // ---------- label validation ----------

    function test_SetLabels_Exactly64BytesOk() public {
        string memory l = _bytesOfLen("a", 64);
        _set(alice, id, bob, l);
        assertEq(labels.labelOf(id, bob), l);
    }

    function test_SetLabels_65BytesReverts() public {
        vm.prank(alice);
        vm.expectRevert(RecipientLabels.LabelTooLong.selector);
        labels.setLabels(id, _a1(bob), _s1(_bytesOfLen("a", 65)));
    }

    function test_SetLabels_MultiByteCountedInBytes() public {
        string memory ok = _rep(unicode"é", 32); // 64 bytes
        _set(alice, id, bob, ok);
        assertEq(labels.labelOf(id, bob), ok);

        vm.prank(alice);
        vm.expectRevert(RecipientLabels.LabelTooLong.selector);
        labels.setLabels(id, _a1(bob), _s1(_rep(unicode"é", 33)));
    }

    function test_SetLabels_ControlCharsRevert() public {
        bytes1[5] memory bad = [bytes1(0x00), 0x01, 0x09, 0x0A, 0x1F];
        for (uint256 i = 0; i < bad.length; ++i) {
            vm.prank(alice);
            vm.expectRevert(RecipientLabels.InvalidLabel.selector);
            labels.setLabels(id, _a1(bob), _s1(string(abi.encodePacked("ab", bad[i], "cd"))));
        }
        // DEL
        vm.prank(alice);
        vm.expectRevert(RecipientLabels.InvalidLabel.selector);
        labels.setLabels(id, _a1(bob), _s1(string(abi.encodePacked("a", bytes1(0x7F)))));
        // control at start and end, newline/tab/CR
        vm.prank(alice);
        vm.expectRevert(RecipientLabels.InvalidLabel.selector);
        labels.setLabels(id, _a1(bob), _s1("\nstart"));
        vm.prank(alice);
        vm.expectRevert(RecipientLabels.InvalidLabel.selector);
        labels.setLabels(id, _a1(bob), _s1("end\r"));
    }

    function test_SetLabels_BoundaryPrintableAccepted() public {
        // 0x20 (space) and 0x7E (~) are valid
        string memory l = string(abi.encodePacked(bytes1(0x20), "x", bytes1(0x7E)));
        _set(alice, id, bob, l);
        assertEq(labels.labelOf(id, bob), l);
    }

    function test_SetLabels_AcceptsNormalText() public {
        string[6] memory ok = [
            "Rent: Q3 (50%) - landlord!",
            "@alice_handle",
            "  spaced   out  ",
            "12345",
            unicode"Café Zoë 🎉",
            unicode"田中さん"
        ];
        for (uint256 i = 0; i < ok.length; ++i) {
            _set(alice, id, bob, ok[i]);
            assertEq(labels.labelOf(id, bob), ok[i]);
        }
    }

    // ---------- atomicity ----------

    function test_FailedCall_LeavesLabelsUnchanged() public {
        _set2(alice, id, "keepB", "keepC");

        // invalid second entry
        vm.prank(alice);
        vm.expectRevert(RecipientLabels.InvalidLabel.selector);
        labels.setLabels(id, _a2(bob, carol), _s2("newB", "bad\x01"));
        assertEq(labels.labelOf(id, bob), "keepB");
        assertEq(labels.labelOf(id, carol), "keepC");

        // non-recipient second entry
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RecipientLabels.NotARecipient.selector, dave));
        labels.setLabels(id, _a2(bob, dave), _s2("newB", "x"));
        assertEq(labels.labelOf(id, bob), "keepB");

        // too long second entry
        vm.prank(alice);
        vm.expectRevert(RecipientLabels.LabelTooLong.selector);
        labels.setLabels(id, _a2(bob, carol), _s2("newB", _bytesOfLen("a", 65)));
        assertEq(labels.labelOf(id, bob), "keepB");
        assertEq(labels.labelOf(id, carol), "keepC");
    }

    // ---------- reads ----------

    function test_LabelOf_UnsetReturnsEmpty() public view {
        assertEq(labels.labelOf(id, bob), "");
        assertEq(labels.labelOf(999, dave), "");
        assertEq(labels.labelOf(0, address(0)), "");
    }

    function test_LabelsOf_PreservesOrderAndUnset() public {
        _set(alice, id, carol, "C");
        address[] memory q = new address[](4);
        q[0] = carol;
        q[1] = bob;
        q[2] = dave; // never a recipient
        q[3] = carol;
        string[] memory got = labels.labelsOf(id, q);
        assertEq(got.length, 4);
        assertEq(got[0], "C");
        assertEq(got[1], "");
        assertEq(got[2], "");
        assertEq(got[3], "C");
    }

    function test_LabelsOf_EmptyArray() public view {
        assertEq(labels.labelsOf(id, new address[](0)).length, 0);
    }

    function test_LabelsOf_UnknownSplitReturnsEmptyStrings() public view {
        string[] memory got = labels.labelsOf(12345, _a2(bob, carol));
        assertEq(got.length, 2);
        assertEq(got[0], "");
        assertEq(got[1], "");
    }

    // ---------- per-split independence ----------

    function test_LabelsIndependentPerSplit() public {
        uint256 id2 = _create(alice, _a2(bob, carol), _b2(5000, 5000));
        uint256 id3 = _create(eve, _a1(bob), _b1(10_000));
        _set(alice, id, bob, "split1");
        _set(alice, id2, bob, "split2");
        _set(eve, id3, bob, "split3");
        assertEq(labels.labelOf(id, bob), "split1");
        assertEq(labels.labelOf(id2, bob), "split2");
        assertEq(labels.labelOf(id3, bob), "split3");
        _set(alice, id, bob, "");
        assertEq(labels.labelOf(id2, bob), "split2");
    }

    function test_CreatorOfOtherSplitCannotLabel() public {
        uint256 id3 = _create(eve, _a1(bob), _b1(10_000));
        vm.prank(eve);
        vm.expectRevert(RecipientLabels.Unauthorized.selector);
        labels.setLabels(id, _a1(bob), _s1("x"));
        vm.prank(alice);
        vm.expectRevert(RecipientLabels.Unauthorized.selector);
        labels.setLabels(id3, _a1(bob), _s1("x"));
    }

    // ---------- interaction with updateSplit ----------

    function test_RemovedRecipient_LabelPersistsButCannotBeSet() public {
        _set2(alice, id, "Bob tag", "Carol tag");

        vm.prank(alice);
        factory.updateSplit(id, _a2(carol, dave), _b2(5000, 5000));

        // old label still readable
        assertEq(labels.labelOf(id, bob), "Bob tag");

        // cannot set / clear for removed address
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RecipientLabels.NotARecipient.selector, bob));
        labels.setLabels(id, _a1(bob), _s1("new"));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RecipientLabels.NotARecipient.selector, bob));
        labels.setLabels(id, _a1(bob), _s1(""));

        // new recipient can be labelled
        _set(alice, id, dave, "Dave tag");
        assertEq(labels.labelOf(id, dave), "Dave tag");

        // re-add bob: old label visible again, and settable
        vm.prank(alice);
        factory.updateSplit(id, _a2(bob, dave), _b2(5000, 5000));
        assertEq(labels.labelOf(id, bob), "Bob tag");
        _set(alice, id, bob, "Bob v2");
        assertEq(labels.labelOf(id, bob), "Bob v2");
    }

    // ---------- fuzz ----------

    function _sanitize(bytes memory raw, uint256 maxLen) internal pure returns (string memory) {
        uint256 n = raw.length > maxLen ? maxLen : raw.length;
        bytes memory out = new bytes(n);
        for (uint256 i = 0; i < n; ++i) {
            bytes1 c = raw[i];
            out[i] = (uint8(c) < 0x20 || uint8(c) == 0x7F) ? bytes1("a") : c;
        }
        return string(out);
    }

    function testFuzz_ValidLabelRoundTrips(bytes memory raw) public {
        string memory l = _sanitize(raw, 64);
        vm.expectEmit(true, true, false, true, address(labels));
        emit RecipientLabels.LabelSet(id, carol, l);
        _set(alice, id, carol, l);
        assertEq(labels.labelOf(id, carol), l);
        assertEq(labels.labelsOf(id, _a1(carol))[0], l);
        assertEq(labels.labelOf(id, bob), "");
    }

    function testFuzz_OnlyCreatorSucceeds(address caller, bytes memory raw) public {
        string memory l = _sanitize(raw, 64);
        vm.prank(caller);
        if (caller != alice) vm.expectRevert(RecipientLabels.Unauthorized.selector);
        labels.setLabels(id, _a1(bob), _s1(l));
        if (caller == alice) {
            assertEq(labels.labelOf(id, bob), l);
        } else {
            assertEq(labels.labelOf(id, bob), "");
        }
    }

    function testFuzz_TooLongLabelReverts(uint256 extra, bytes1 fill) public {
        extra = bound(extra, 1, 400);
        uint8 f = uint8(fill);
        if (f < 0x20 || f == 0x7F) fill = "z";
        _set(alice, id, bob, "prev");
        vm.prank(alice);
        vm.expectRevert(RecipientLabels.LabelTooLong.selector);
        labels.setLabels(id, _a1(bob), _s1(_bytesOfLen(fill, 64 + extra)));
        assertEq(labels.labelOf(id, bob), "prev");
    }

    function testFuzz_ControlByteAnywhereReverts(uint256 len, uint256 pos, uint8 ctl) public {
        len = bound(len, 1, 64);
        pos = bound(pos, 0, len - 1);
        ctl = uint8(bound(ctl, 0, 0x21));
        bytes memory b = bytes(_bytesOfLen("a", len));
        b[pos] = ctl == 0x20 ? bytes1(0x7F) : (ctl == 0x21 ? bytes1(0x1F) : bytes1(ctl));
        if (ctl == 0x20) b[pos] = 0x7F;
        vm.prank(alice);
        vm.expectRevert(RecipientLabels.InvalidLabel.selector);
        labels.setLabels(id, _a1(bob), _s1(string(b)));
    }
}
