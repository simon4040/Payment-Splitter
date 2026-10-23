// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SplitFactory {
    using SafeERC20 for IERC20;

    struct Recipient {
        address addr;
        uint96 bps;
    }

    struct Split {
        address creator;
        Recipient[] recipients;
        uint256 totalDistributed;
    }

    error ZeroAddress();
    error InvalidSplit();
    error SplitNotFound();
    error NoBalance();
    error Unauthorized();
    error NoPendingDust();
    error ZeroAmount();

    event SplitCreated(uint256 indexed splitId, address indexed creator);
    event SplitUpdated(uint256 indexed splitId);
    event Deposited(uint256 indexed splitId, address indexed sender, uint256 amount);
    event Distributed(uint256 indexed splitId, uint256 totalAmount, uint256 recipientCount);
    event DustRescued(uint256 indexed splitId, uint256 amount);

    address public immutable usdc;
    uint256 public splitCount;
    mapping(uint256 => Split) private _splits;
    mapping(uint256 => uint256) public splitBalance;
    mapping(uint256 => uint256) public pendingCreatorDust;

    constructor(address _usdc) {
        if (_usdc == address(0)) revert ZeroAddress();
        usdc = _usdc;
    }

    function createSplit(address[] calldata addrs, uint96[] calldata bps) external returns (uint256 splitId) {
        _validateSplitInputs(addrs, bps);

        splitId = ++splitCount;
        Split storage split = _splits[splitId];
        split.creator = msg.sender;

        uint256 length = addrs.length;
        for (uint256 i = 0; i < length; ++i) {
            split.recipients.push(Recipient({addr: addrs[i], bps: bps[i]}));
        }

        emit SplitCreated(splitId, msg.sender);
    }

    function updateSplit(uint256 splitId, address[] calldata addrs, uint96[] calldata bps) external {
        Split storage split = _getSplitOrRevert(splitId);
        if (msg.sender != split.creator) revert Unauthorized();

        _validateSplitInputs(addrs, bps);

        delete split.recipients;

        uint256 length = addrs.length;
        for (uint256 i = 0; i < length; ++i) {
            split.recipients.push(Recipient({addr: addrs[i], bps: bps[i]}));
        }

        emit SplitUpdated(splitId);
    }

    function deposit(uint256 splitId, uint256 amount) external {
        _getSplitOrRevert(splitId);
        if (amount == 0) revert ZeroAmount();

        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);
        splitBalance[splitId] += amount;

        emit Deposited(splitId, msg.sender, amount);
    }

    function distribute(uint256 splitId) external {
        Split storage split = _getSplitOrRevert(splitId);

        uint256 recipientCount = split.recipients.length;
        if (recipientCount == 0) revert InvalidSplit();

        uint256 amount = splitBalance[splitId];
        if (amount == 0) revert NoBalance();

        splitBalance[splitId] = 0;
        split.totalDistributed += amount;

        IERC20 token = IERC20(usdc);
        uint256 distributed;

        for (uint256 i = 0; i < recipientCount; ++i) {
            Recipient memory recipient = split.recipients[i];
            uint256 share = (amount * recipient.bps) / 10_000;

            if (share > 0) {
                try token.transfer(recipient.addr, share) returns (bool ok) {
                    if (ok) {
                        distributed += share;
                    }
                } catch {
                    // failed share becomes dust for the split creator
                }
            }
        }

        uint256 dust = amount - distributed;
        if (dust > 0) {
            try token.transfer(split.creator, dust) returns (bool ok) {
                if (!ok) {
                    pendingCreatorDust[splitId] += dust;
                }
            } catch {
                pendingCreatorDust[splitId] += dust;
            }
        }

        emit Distributed(splitId, amount, recipientCount);
    }

    function rescueDust(uint256 splitId) external {
        Split storage split = _getSplitOrRevert(splitId);
        if (msg.sender != split.creator) revert Unauthorized();

        uint256 amount = pendingCreatorDust[splitId];
        if (amount == 0) revert NoPendingDust();

        pendingCreatorDust[splitId] = 0;
        IERC20(usdc).safeTransfer(split.creator, amount);

        emit DustRescued(splitId, amount);
    }

    function getSplit(
        uint256 splitId
    ) external view returns (address creator, uint256 balance, uint256 totalDistributed, uint256 recipientCount) {
        Split storage split = _getSplitOrRevert(splitId);

        creator = split.creator;
        balance = splitBalance[splitId];
        totalDistributed = split.totalDistributed;
        recipientCount = split.recipients.length;
    }

    function getRecipients(uint256 splitId) external view returns (address[] memory addrs, uint96[] memory bps) {
        Split storage split = _getSplitOrRevert(splitId);

        uint256 length = split.recipients.length;
        addrs = new address[](length);
        bps = new uint96[](length);

        for (uint256 i = 0; i < length; ++i) {
            Recipient memory recipient = split.recipients[i];
            addrs[i] = recipient.addr;
            bps[i] = recipient.bps;
        }
    }

    function _validateSplitInputs(address[] calldata addrs, uint96[] calldata bps) internal pure {
        uint256 length = addrs.length;
        if (length != bps.length || length == 0 || length > 20) revert InvalidSplit();

        uint256 totalBps;
        for (uint256 i = 0; i < length; ++i) {
            if (addrs[i] == address(0)) revert ZeroAddress();
            totalBps += bps[i];
        }

        if (totalBps != 10_000) revert InvalidSplit();
    }

    function _getSplitOrRevert(uint256 splitId) internal view returns (Split storage split) {
        if (splitId == 0 || splitId > splitCount) revert SplitNotFound();
        split = _splits[splitId];
    }
}
