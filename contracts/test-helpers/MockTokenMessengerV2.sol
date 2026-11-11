// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMockBurnToken {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @dev Mock of Circle's CCTP V2 TokenMessengerV2.depositForBurnWithHook.
///      Pulls tokens from msg.sender (needs allowance), holds them as "burned",
///      records every argument, and can be configured to revert.
contract MockTokenMessengerV2 {
    error MockMessengerReverted();
    error InsufficientMaxFee();
    error ZeroBurnAmount();

    bool public shouldRevert;

    uint256 public callCount;
    address public lastCaller;
    uint256 public lastAmount;
    uint32 public lastDestinationDomain;
    bytes32 public lastMintRecipient;
    address public lastBurnToken;
    bytes32 public lastDestinationCaller;
    uint256 public lastMaxFee;
    uint32 public lastMinFinalityThreshold;
    bytes public lastHookData;
    uint256 public totalBurned;

    function setShouldRevert(bool flag) external {
        shouldRevert = flag;
    }

    function depositForBurnWithHook(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        bytes calldata hookData
    ) external {
        if (shouldRevert) revert MockMessengerReverted();
        if (amount == 0) revert ZeroBurnAmount();
        if (maxFee >= amount) revert InsufficientMaxFee();

        IMockBurnToken(burnToken).transferFrom(msg.sender, address(this), amount);

        callCount++;
        lastCaller = msg.sender;
        lastAmount = amount;
        lastDestinationDomain = destinationDomain;
        lastMintRecipient = mintRecipient;
        lastBurnToken = burnToken;
        lastDestinationCaller = destinationCaller;
        lastMaxFee = maxFee;
        lastMinFinalityThreshold = minFinalityThreshold;
        lastHookData = hookData;
        totalBurned += amount;
    }
}
