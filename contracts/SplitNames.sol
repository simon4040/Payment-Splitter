// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Read-only interface for checking a split's creator in the existing factory.
interface ISplitFactoryNames {
    function getSplit(uint256 splitId)
        external
        view
        returns (address creator, uint256 balance, uint256 totalDistributed, uint256 recipientCount);
}

/// @title SplitNames
/// @notice Creator-controlled names for splits in a permanently linked factory.
contract SplitNames {
    /// @notice Factory used to verify split existence and creator authorization.
    address public immutable factory;

    /// @notice Maximum name length in bytes, not Unicode characters.
    uint256 public constant MAX_NAME_BYTES = 60;

    mapping(uint256 => string) private _names;

    error ZeroAddress();
    error Unauthorized();
    error NameTooLong();
    error InvalidName();

    /// @notice Emitted when a creator sets, changes or clears a split's name.
    event NameSet(uint256 indexed splitId, address indexed creator, string name);

    /// @notice Permanently links this registry to a nonzero factory address.
    constructor(address _factory) {
        if (_factory == address(0)) revert ZeroAddress();
        factory = _factory;
    }

    /// @notice Sets a split's name; an empty string clears it.
    /// @dev Only the factory-recorded creator may call. Factory reverts propagate.
    ///      Rejects ASCII control bytes below 0x20 and 0x7F.
    function setName(uint256 splitId, string calldata name) external {
        (address creator,,,) = ISplitFactoryNames(factory).getSplit(splitId);
        if (msg.sender != creator) revert Unauthorized();

        bytes calldata nameBytes = bytes(name);
        uint256 length = nameBytes.length;
        if (length > MAX_NAME_BYTES) revert NameTooLong();
        for (uint256 i = 0; i < length; ++i) {
            uint8 character = uint8(nameBytes[i]);
            if (character < 0x20 || character == 0x7F) revert InvalidName();
        }

        _names[splitId] = name;
        emit NameSet(splitId, creator, name);
    }

    /// @notice Returns a split's name, or an empty string if unset or cleared.
    /// @dev Reads do not validate whether the split exists in the factory.
    function nameOf(uint256 splitId) external view returns (string memory) {
        return _names[splitId];
    }

    /// @notice Returns names in input order, with empty strings for unset names.
    /// @dev Reads do not validate split existence; duplicate IDs are preserved.
    function namesOf(uint256[] calldata splitIds) external view returns (string[] memory names) {
        uint256 length = splitIds.length;
        names = new string[](length);
        for (uint256 i = 0; i < length; ++i) {
            names[i] = _names[splitIds[i]];
        }
    }
}
