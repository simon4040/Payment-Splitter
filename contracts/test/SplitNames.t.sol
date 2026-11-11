// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SplitFactoryTestBase} from "./SplitFactory.Base.t.sol";
import {SplitFactory} from "../SplitFactory.sol";
import {SplitNames} from "../SplitNames.sol";

contract SplitNamesTest is SplitFactoryTestBase {
    SplitNames internal names;
    uint256 internal id;

    function setUp() public override {
        super.setUp();
        names = new SplitNames(address(factory));
        id = _createDefault(); // creator = alice
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

    function _set(address who, uint256 splitId, string memory n) internal {
        vm.prank(who);
        names.setName(splitId, n);
    }

    // ---------- constructor ----------

    function test_Constructor_StoresFactory() public view {
        assertEq(names.factory(), address(factory));
        assertEq(names.MAX_NAME_BYTES(), 60);
    }

    function test_Constructor_RevertsOnZeroFactory() public {
        vm.expectRevert(SplitNames.ZeroAddress.selector);
        new SplitNames(address(0));
    }

    // ---------- setName happy path ----------

    function test_SetName_StoresAndReads() public {
        _set(alice, id, "Rent split");
        assertEq(names.nameOf(id), "Rent split");
    }

    function test_SetName_EmitsNameSet() public {
        vm.expectEmit(true, true, false, true, address(names));
        emit SplitNames.NameSet(id, alice, "Hello");
        _set(alice, id, "Hello");
    }

    function test_SetName_EmitsOnClearAndRename() public {
        _set(alice, id, "a");
        vm.expectEmit(true, true, false, true, address(names));
        emit SplitNames.NameSet(id, alice, "b");
        _set(alice, id, "b");
        vm.expectEmit(true, true, false, true, address(names));
        emit SplitNames.NameSet(id, alice, "");
        _set(alice, id, "");
    }

    function test_SetName_RenameOverwrites() public {
        _set(alice, id, "first");
        _set(alice, id, "second, longer name");
        assertEq(names.nameOf(id), "second, longer name");
        _set(alice, id, "x");
        assertEq(names.nameOf(id), "x");
    }

    function test_SetName_EmptyClears() public {
        _set(alice, id, "something");
        _set(alice, id, "");
        assertEq(names.nameOf(id), "");
    }

    function test_SetName_EmptyOnUnsetIsOk() public {
        _set(alice, id, "");
        assertEq(names.nameOf(id), "");
    }

    function test_SetName_AcceptsTextSpacesPunctuationDigits() public {
        string memory n = "Team A-1: rent & bills (2025), 50/50! #ok?";
        _set(alice, id, n);
        assertEq(names.nameOf(id), n);
        _set(alice, id, "  leading and trailing  ");
        assertEq(names.nameOf(id), "  leading and trailing  ");
        _set(alice, id, "0123456789");
        assertEq(names.nameOf(id), "0123456789");
    }

    function test_SetName_AcceptsNonAsciiUtf8() public {
        _set(alice, id, unicode"Café résumé naïve");
        assertEq(names.nameOf(id), unicode"Café résumé naïve");
        _set(alice, id, unicode"🎉 Party 🍕");
        assertEq(names.nameOf(id), unicode"🎉 Party 🍕");
        _set(alice, id, unicode"日本語");
        assertEq(names.nameOf(id), unicode"日本語");
    }

    function test_SetName_BoundaryCharsAccepted() public {
        // 0x20 (space) and 0x7E (~) are the edges of the allowed ASCII range
        _set(alice, id, " ");
        assertEq(names.nameOf(id), " ");
        _set(alice, id, "~");
        assertEq(names.nameOf(id), "~");
        // 0x80 and 0xC2 0x80 style bytes are fine
        _set(alice, id, string(hex"c280"));
        assertEq(names.nameOf(id), string(hex"c280"));
    }

    // ---------- length ----------

    function test_SetName_Exactly60BytesOk() public {
        string memory n = _rep("a", 60);
        assertEq(bytes(n).length, 60);
        _set(alice, id, n);
        assertEq(names.nameOf(id), n);
    }

    function test_RevertWhen_61Bytes() public {
        vm.prank(alice);
        vm.expectRevert(SplitNames.NameTooLong.selector);
        names.setName(id, _rep("a", 61));
    }

    function test_MultiByteUtf8_60BytesOk() public {
        string memory n = _rep(unicode"é", 30); // 30 chars, 60 bytes
        assertEq(bytes(n).length, 60);
        _set(alice, id, n);
        assertEq(names.nameOf(id), n);
        string memory e = _rep(unicode"🎉", 15); // 15 chars, 60 bytes
        assertEq(bytes(e).length, 60);
        _set(alice, id, e);
        assertEq(names.nameOf(id), e);
    }

    function test_RevertWhen_MultiByteUtf8BytesExceed60() public {
        string memory n = _rep(unicode"é", 31); // 31 chars (< 60) but 62 bytes
        assertEq(bytes(n).length, 62);
        vm.prank(alice);
        vm.expectRevert(SplitNames.NameTooLong.selector);
        names.setName(id, n);

        string memory e = _rep(unicode"🎉", 16); // 16 chars, 64 bytes
        vm.prank(alice);
        vm.expectRevert(SplitNames.NameTooLong.selector);
        names.setName(id, e);
    }

    function test_RevertWhen_TooLongDoesNotChangeExistingName() public {
        _set(alice, id, "keep");
        vm.prank(alice);
        vm.expectRevert(SplitNames.NameTooLong.selector);
        names.setName(id, _rep("z", 100));
        assertEq(names.nameOf(id), "keep");
    }

    // ---------- invalid characters ----------

    function test_RevertWhen_Newline() public {
        vm.prank(alice);
        vm.expectRevert(SplitNames.InvalidName.selector);
        names.setName(id, "line1\nline2");
    }

    function test_RevertWhen_TabAndCarriageReturn() public {
        vm.prank(alice);
        vm.expectRevert(SplitNames.InvalidName.selector);
        names.setName(id, "a\tb");
        vm.prank(alice);
        vm.expectRevert(SplitNames.InvalidName.selector);
        names.setName(id, "a\rb");
    }

    function test_RevertWhen_NullByte() public {
        vm.prank(alice);
        vm.expectRevert(SplitNames.InvalidName.selector);
        names.setName(id, string(hex"610062"));
    }

    function test_RevertWhen_Delete0x7F() public {
        vm.prank(alice);
        vm.expectRevert(SplitNames.InvalidName.selector);
        names.setName(id, string(hex"617f62"));
    }

    function test_RevertWhen_ControlCharAtStartOrEnd() public {
        vm.prank(alice);
        vm.expectRevert(SplitNames.InvalidName.selector);
        names.setName(id, string(hex"016162"));
        vm.prank(alice);
        vm.expectRevert(SplitNames.InvalidName.selector);
        names.setName(id, string(hex"61621f"));
    }

    function test_RevertWhen_InvalidDoesNotChangeExistingName() public {
        _set(alice, id, "keep");
        vm.prank(alice);
        vm.expectRevert(SplitNames.InvalidName.selector);
        names.setName(id, "bad\nname");
        assertEq(names.nameOf(id), "keep");
    }

    function test_EveryControlByteRejected() public {
        for (uint256 c = 0; c < 0x20; ++c) {
            bytes memory b = new bytes(3);
            b[0] = "a";
            b[1] = bytes1(uint8(c));
            b[2] = "b";
            vm.prank(alice);
            vm.expectRevert(SplitNames.InvalidName.selector);
            names.setName(id, string(b));
        }
    }

    // ---------- authorization / existence ----------

    function test_RevertWhen_NonCreatorSets() public {
        vm.prank(bob);
        vm.expectRevert(SplitNames.Unauthorized.selector);
        names.setName(id, "hijack");
        assertEq(names.nameOf(id), "");
    }

    function test_RevertWhen_RecipientIsNotCreator() public {
        // bob/carol are recipients, not creator
        vm.prank(carol);
        vm.expectRevert(SplitNames.Unauthorized.selector);
        names.setName(id, "nope");
    }

    function test_RevertWhen_OwnerAndFeeRecipientNotCreator() public {
        vm.prank(owner);
        vm.expectRevert(SplitNames.Unauthorized.selector);
        names.setName(id, "nope");
        vm.prank(feeRecipient);
        vm.expectRevert(SplitNames.Unauthorized.selector);
        names.setName(id, "nope");
    }

    function test_RevertWhen_SplitIdZero() public {
        vm.prank(alice);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        names.setName(0, "x");
    }

    function test_RevertWhen_SplitDoesNotExist() public {
        vm.prank(alice);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        names.setName(id + 1, "x");
        vm.prank(alice);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        names.setName(type(uint256).max, "x");
    }

    function test_RevertWhen_NonexistentSplitEmptyName() public {
        vm.prank(alice);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        names.setName(id + 1, "");
    }

    function test_CreatorOfLaterSplitCanName() public {
        uint256 id2 = _create(eve, _a1(bob), _b1(10_000));
        _set(eve, id2, "eve's");
        assertEq(names.nameOf(id2), "eve's");
    }

    // ---------- independence ----------

    function test_NamesIndependentPerSplit() public {
        uint256 id2 = _createDefault();
        _set(alice, id, "one");
        assertEq(names.nameOf(id2), "");
        _set(alice, id2, "two");
        assertEq(names.nameOf(id), "one");
        assertEq(names.nameOf(id2), "two");
        _set(alice, id, "");
        assertEq(names.nameOf(id), "");
        assertEq(names.nameOf(id2), "two");
    }

    function test_TwoCreatorsNameOwnSplits() public {
        uint256 id2 = _create(eve, _a1(bob), _b1(10_000));
        _set(alice, id, "alice-split");
        _set(eve, id2, "eve-split");
        assertEq(names.nameOf(id), "alice-split");
        assertEq(names.nameOf(id2), "eve-split");
    }

    function test_CreatorCannotNameOthersSplit() public {
        uint256 id2 = _create(eve, _a1(bob), _b1(10_000));
        vm.prank(alice);
        vm.expectRevert(SplitNames.Unauthorized.selector);
        names.setName(id2, "stolen");
        vm.prank(eve);
        vm.expectRevert(SplitNames.Unauthorized.selector);
        names.setName(id, "stolen");
        assertEq(names.nameOf(id), "");
        assertEq(names.nameOf(id2), "");
    }

    // ---------- nameOf / namesOf ----------

    function test_NameOf_EmptyForLegacyUnnamedSplit() public view {
        assertEq(names.nameOf(id), "");
    }

    function test_NameOf_EmptyForUnknownIds() public view {
        assertEq(names.nameOf(0), "");
        assertEq(names.nameOf(id + 100), "");
        assertEq(names.nameOf(type(uint256).max), "");
    }

    function test_NamesOf_OrderAndEmptyForUnset() public {
        uint256 id2 = _createDefault();
        uint256 id3 = _createDefault();
        _set(alice, id, "one");
        _set(alice, id3, "three");

        uint256[] memory ids = new uint256[](4);
        ids[0] = id3;
        ids[1] = id2;
        ids[2] = id;
        ids[3] = 999; // unknown
        string[] memory out = names.namesOf(ids);
        assertEq(out.length, 4);
        assertEq(out[0], "three");
        assertEq(out[1], "");
        assertEq(out[2], "one");
        assertEq(out[3], "");
    }

    function test_NamesOf_EmptyArray() public view {
        uint256[] memory ids = new uint256[](0);
        string[] memory out = names.namesOf(ids);
        assertEq(out.length, 0);
    }

    function test_NamesOf_DuplicateIdsPreserved() public {
        _set(alice, id, "dup");
        uint256[] memory ids = new uint256[](3);
        ids[0] = id;
        ids[1] = id;
        ids[2] = id;
        string[] memory out = names.namesOf(ids);
        assertEq(out.length, 3);
        assertEq(out[0], "dup");
        assertEq(out[1], "dup");
        assertEq(out[2], "dup");
    }

    function test_NamesOf_ManyIds() public {
        uint256 n = 60;
        uint256[] memory ids = new uint256[](n);
        ids[0] = id;
        for (uint256 i = 1; i < n; ++i) {
            ids[i] = _createDefault();
        }
        for (uint256 i = 0; i < n; i += 2) {
            _set(alice, ids[i], _rep("n", (i % 60) + 1));
        }
        string[] memory out = names.namesOf(ids);
        assertEq(out.length, n);
        for (uint256 i = 0; i < n; ++i) {
            if (i % 2 == 0) {
                assertEq(out[i], _rep("n", (i % 60) + 1));
                assertEq(out[i], names.nameOf(ids[i]));
            } else {
                assertEq(out[i], "");
            }
        }
    }

    // ---------- factory interaction ----------

    function test_UpdateSplitDoesNotChangeName() public {
        _set(alice, id, "persistent");
        vm.prank(alice);
        factory.updateSplit(id, _a2(carol, dave), _b2(5000, 5000));
        assertEq(names.nameOf(id), "persistent");
        // creator can still rename afterwards
        _set(alice, id, "renamed");
        assertEq(names.nameOf(id), "renamed");
    }

    function test_UpdateSplitDoesNotNameUnnamedSplit() public {
        vm.prank(alice);
        factory.updateSplit(id, _a2(carol, dave), _b2(5000, 5000));
        assertEq(names.nameOf(id), "");
    }

    // ---------- fuzz ----------

    function _sanitize(bytes memory b) internal pure returns (bytes memory) {
        for (uint256 i = 0; i < b.length; ++i) {
            uint8 c = uint8(b[i]);
            if (c < 0x20 || c == 0x7F) b[i] = "_";
        }
        return b;
    }

    function testFuzz_ValidNamesRoundTrip(bytes memory raw) public {
        vm.assume(raw.length <= 60);
        string memory n = string(_sanitize(raw));
        vm.expectEmit(true, true, false, true, address(names));
        emit SplitNames.NameSet(id, alice, n);
        _set(alice, id, n);
        assertEq(names.nameOf(id), n);

        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        assertEq(names.namesOf(ids)[0], n);
    }

    function testFuzz_ValidNamesAnyLengthUpTo60(uint256 len, uint8 fill) public {
        len = bound(len, 0, 60);
        uint8 f = uint8(bound(fill, 0x20, 0x7E));
        bytes memory b = new bytes(len);
        for (uint256 i = 0; i < len; ++i) {
            b[i] = bytes1(f);
        }
        _set(alice, id, string(b));
        assertEq(names.nameOf(id), string(b));
    }

    function testFuzz_TooLongReverts(uint256 len, uint8 fill) public {
        len = bound(len, 61, 400);
        bytes memory b = new bytes(len);
        for (uint256 i = 0; i < len; ++i) {
            b[i] = bytes1(uint8(bound(fill, 0x20, 0x7E)));
        }
        vm.prank(alice);
        vm.expectRevert(SplitNames.NameTooLong.selector);
        names.setName(id, string(b));
        assertEq(names.nameOf(id), "");
    }

    function testFuzz_ControlByteAnywhereReverts(uint256 len, uint256 pos, uint8 ctrl, bool useDel) public {
        len = bound(len, 1, 60);
        pos = bound(pos, 0, len - 1);
        bytes memory b = new bytes(len);
        for (uint256 i = 0; i < len; ++i) {
            b[i] = "x";
        }
        b[pos] = useDel ? bytes1(0x7F) : bytes1(uint8(bound(ctrl, 0, 0x1F)));
        vm.prank(alice);
        vm.expectRevert(SplitNames.InvalidName.selector);
        names.setName(id, string(b));
    }

    function testFuzz_OnlyCreatorCanSet(address caller, uint256 splitIdx) public {
        uint256 id2 = _create(eve, _a1(bob), _b1(10_000));
        uint256 target = splitIdx % 2 == 0 ? id : id2;
        address creator = target == id ? alice : eve;

        vm.prank(caller);
        if (caller != creator) {
            vm.expectRevert(SplitNames.Unauthorized.selector);
        }
        names.setName(target, "fuzzed");

        if (caller == creator) {
            assertEq(names.nameOf(target), "fuzzed");
        } else {
            assertEq(names.nameOf(target), "");
        }
    }

    function testFuzz_UnknownIdsRevertNotFound(uint256 splitId, address caller) public {
        splitId = bound(splitId, id + 1, type(uint256).max);
        vm.prank(caller);
        vm.expectRevert(SplitFactory.SplitNotFound.selector);
        names.setName(splitId, "x");
        assertEq(names.nameOf(splitId), "");
    }
}
