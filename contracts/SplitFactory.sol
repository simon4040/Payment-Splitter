// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SplitFactory is Ownable2Step {
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
    error InvalidDestination();
    error InvalidSplit();
    error SplitNotFound();
    error NoBalance();
    error Unauthorized();
    error NoPendingDust();
    error ZeroAmount();
    error FeeTooHigh();
    error RenounceDisabled();
    error NoClaimable();
    error ConfigChanged();

    event SplitCreated(uint256 indexed splitId, address indexed creator);
    event SplitUpdated(uint256 indexed splitId);
    event Deposited(uint256 indexed splitId, address indexed sender, uint256 netAmount, uint256 fee);
    event Distributed(uint256 indexed splitId, uint256 totalAmount, uint256 recipientCount);
    event DustRescued(uint256 indexed splitId, uint256 amount);
    event Claimed(uint256 indexed splitId, address indexed recipient, uint256 amount);
    event PayoutDeferred(uint256 indexed splitId, address indexed recipient, uint256 amount);
    event FeeBpsUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    /// @notice Maximum protocol fee in basis points (5%).
    uint16 public constant MAX_FEE_BPS = 500;
    /// @notice Protocol fee charged on deposits, in basis points.
    uint16 public feeBps;
    /// @notice Address receiving protocol fees directly from depositors.
    address public feeRecipient;

    address public immutable usdc;
    uint256 public splitCount;
    mapping(uint256 => Split) private _splits;
    mapping(uint256 => uint256) public splitBalance;
    mapping(uint256 => uint256) public pendingCreatorDust;
    mapping(uint256 => mapping(address => uint256)) public claimable;
    mapping(uint256 => uint256) public splitVersion;

    /// @notice Initializes the token, owner, fee recipient and capped deposit fee.
    constructor(address _usdc, address _owner, address _feeRecipient, uint16 _feeBps) Ownable(_owner) {
        if (_usdc == address(0) || _feeRecipient == address(0)) revert ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();
        usdc = _usdc;
        feeBps = _feeBps;
        feeRecipient = _feeRecipient;

        emit FeeBpsUpdated(0, _feeBps);
        emit FeeRecipientUpdated(address(0), _feeRecipient);
    }

    /// @notice Updates the deposit fee without exceeding the hard cap.
    function setFeeBps(uint16 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh();
        uint16 oldFeeBps = feeBps;
        feeBps = newFeeBps;
        emit FeeBpsUpdated(oldFeeBps, newFeeBps);
    }

    /// @notice Updates the nonzero address receiving deposit fees.
    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /// @notice Ownership cannot be renounced, preserving fee administration.
    function renounceOwnership() public override {
        revert RenounceDisabled();
    }

    function createSplit(address[] calldata addrs, uint96[] calldata bps) external returns (uint256 splitId) {
        _validateSplitInputs(addrs, bps);

        splitId = ++splitCount;
        splitVersion[splitId] = 1;
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

        if (splitBalance[splitId] != 0) _distribute(splitId, split);

        delete split.recipients;

        uint256 length = addrs.length;
        for (uint256 i = 0; i < length; ++i) {
            split.recipients.push(Recipient({addr: addrs[i], bps: bps[i]}));
        }

        ++splitVersion[splitId];
        emit SplitUpdated(splitId);
    }

    /// @notice Credits net funds to a split and transfers the fee directly to its recipient.
    function deposit(uint256 splitId, uint256 amount, uint256 expectedVersion) external {
        _getSplitOrRevert(splitId);
        if (splitVersion[splitId] != expectedVersion) revert ConfigChanged();
        if (amount == 0) revert ZeroAmount();

        uint256 fee = amount * feeBps / 10_000;
        uint256 net = amount - fee;
        splitBalance[splitId] += net;

        if (fee > 0) {
            IERC20(usdc).safeTransferFrom(msg.sender, feeRecipient, fee);
        }
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), net);

        emit Deposited(splitId, msg.sender, net, fee);
    }

    /// @notice Returns the net split credit and protocol fee for a deposit amount.
    function previewDeposit(uint256 amount) external view returns (uint256 net, uint256 fee) {
        fee = amount * feeBps / 10_000;
        net = amount - fee;
    }

    function distribute(uint256 splitId) external {
        Split storage split = _getSplitOrRevert(splitId);

        uint256 recipientCount = split.recipients.length;
        if (recipientCount == 0) revert InvalidSplit();

        uint256 amount = splitBalance[splitId];
        if (amount == 0) revert NoBalance();

        _distribute(splitId, split);
    }

    function _distribute(uint256 splitId, Split storage split) internal {
        uint256 recipientCount = split.recipients.length;
        uint256 amount = splitBalance[splitId];

        splitBalance[splitId] = 0;
        split.totalDistributed += amount;

        IERC20 token = IERC20(usdc);
        uint256 distributed;
        uint256 accounted;

        for (uint256 i = 0; i < recipientCount; ++i) {
            Recipient memory recipient = split.recipients[i];
            uint256 share = (amount * recipient.bps) / 10_000;
            accounted += share;

            if (share > 0) {
                try token.transfer(recipient.addr, share) returns (bool ok) {
                    if (ok) {
                        distributed += share;
                    } else {
                        claimable[splitId][recipient.addr] += share;
                        emit PayoutDeferred(splitId, recipient.addr, share);
                    }
                } catch {
                    claimable[splitId][recipient.addr] += share;
                    emit PayoutDeferred(splitId, recipient.addr, share);
                }
            }
        }

        uint256 dust = amount - accounted;
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

    function claim(uint256 splitId, address recipient) external {
        _getSplitOrRevert(splitId);

        uint256 amount = claimable[splitId][recipient];
        if (amount == 0) revert NoClaimable();

        claimable[splitId][recipient] = 0;
        IERC20(usdc).safeTransfer(recipient, amount);

        emit Claimed(splitId, recipient, amount);
    }

    function claimTo(uint256 splitId, address to) external {
        _getSplitOrRevert(splitId);
        if (to == address(0)) revert ZeroAddress();
        if (!_isValidDestination(to)) revert InvalidDestination();

        uint256 amount = claimable[splitId][msg.sender];
        if (amount == 0) revert NoClaimable();

        claimable[splitId][msg.sender] = 0;
        IERC20(usdc).safeTransfer(to, amount);

        emit Claimed(splitId, msg.sender, amount);
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

    function _isValidDestination(address a) internal view returns (bool) {
        if (a == address(0) || a == address(this) || a == usdc || uint160(a) < 0x10000) return false;
        return true;
    }

    function _validateSplitInputs(address[] calldata addrs, uint96[] calldata bps) internal view {
        uint256 length = addrs.length;
        if (length != bps.length || length == 0 || length > 20) revert InvalidSplit();

        uint256 totalBps;
        for (uint256 i = 0; i < length; ++i) {
            if (addrs[i] == address(0)) revert ZeroAddress();
            if (!_isValidDestination(addrs[i])) revert InvalidDestination();
            totalBps += bps[i];
        }

        if (totalBps != 10_000) revert InvalidSplit();
    }

    function _getSplitOrRevert(uint256 splitId) internal view returns (Split storage split) {
        if (splitId == 0 || splitId > splitCount) revert SplitNotFound();
        split = _splits[splitId];
    }
}
