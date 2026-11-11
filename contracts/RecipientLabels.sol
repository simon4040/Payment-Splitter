// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Read-only interface for checking split creators and current recipients.
interface ISplitFactoryLabels {
    function getSplit(uint256 splitId)
        external
        view
        returns (address creator, uint256 balance, uint256 totalDistributed, uint256 recipientCount);

    function getRecipients(uint256 splitId) external view returns (address[] memory addrs, uint96[] memory bps);
}

/// @title RecipientLabels
/// @notice Creator-controlled recipient labels for splits in a permanently linked factory.
contract RecipientLabels {
    /// @notice Factory used to verify split existence, creators and current recipients.
    address public immutable factory;

    /// @notice Maximum label length in bytes, not Unicode characters.
    uint256 public constant MAX_LABEL_BYTES = 64;
    /// @notice Maximum number of label updates in one call.
    uint256 public constant MAX_BATCH = 20;

    mapping(uint256 => mapping(address => string)) private _labels;

    error ZeroAddress();
    error Unauthorized();
    error LengthMismatch();
    error TooMany();
    error NotARecipient(address recipient);
    error LabelTooLong();
    error InvalidLabel();

    /// @notice Emitted for each label set, changed or cleared, including duplicates.
    event LabelSet(uint256 indexed splitId, address indexed recipient, string label);

    /// @notice Permanently links this registry to a nonzero factory address.
    constructor(address _factory) {
        if (_factory == address(0)) revert ZeroAddress();
        factory = _factory;
    }

    /// @notice Sets current recipients' labels; an empty string clears a label.
    /// @dev Only the factory-recorded creator may call. Factory reverts propagate.
    ///      Rejects ASCII control bytes below 0x20 and 0x7F; duplicates use the last label.
    function setLabels(uint256 splitId, address[] calldata recipients, string[] calldata labels) external {
        {
            (address creator,,,) = ISplitFactoryLabels(factory).getSplit(splitId);
            if (msg.sender != creator) revert Unauthorized();
        }

        if (recipients.length != labels.length) revert LengthMismatch();
        if (recipients.length > MAX_BATCH) revert TooMany();

        (address[] memory currentRecipients,) = ISplitFactoryLabels(factory).getRecipients(splitId);
        for (uint256 i = 0; i < recipients.length; ++i) {
            address recipient = recipients[i];
            _requireRecipient(currentRecipients, recipient);
            _validateLabel(labels[i]);

            _labels[splitId][recipient] = labels[i];
            emit LabelSet(splitId, recipient, labels[i]);
        }
    }

    function _requireRecipient(address[] memory current, address who) internal view {
        for (uint256 i = 0; i < current.length; ++i) {
            if (current[i] == who) return;
        }
        revert NotARecipient(who);
    }

    function _validateLabel(string calldata label) internal pure {
        bytes calldata labelBytes = bytes(label);
        if (labelBytes.length > MAX_LABEL_BYTES) revert LabelTooLong();
        for (uint256 i = 0; i < labelBytes.length; ++i) {
            uint8 character = uint8(labelBytes[i]);
            if (character < 0x20 || character == 0x7F) revert InvalidLabel();
        }
    }

    /// @notice Returns a recipient's label, or an empty string if unset or cleared.
    /// @dev Reads do not validate split existence or current recipient membership.
    function labelOf(uint256 splitId, address recipient) external view returns (string memory) {
        return _labels[splitId][recipient];
    }

    /// @notice Returns labels in input order, with empty strings for unset labels.
    /// @dev Reads do not validate split existence or current recipient membership.
    function labelsOf(uint256 splitId, address[] calldata recipients) external view returns (string[] memory labels) {
        uint256 length = recipients.length;
        labels = new string[](length);
        for (uint256 i = 0; i < length; ++i) {
            labels[i] = _labels[splitId][recipients[i]];
        }
    }
}
