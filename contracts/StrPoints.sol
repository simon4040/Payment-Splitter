// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Minimal interface for the existing SplitFactory.
interface ISplitFactory {
    function deposit(uint256 splitId, uint256 amount, uint256 expectedVersion) external;
    function distribute(uint256 splitId) external;
    function feeBps() external view returns (uint16);
    function feeRecipient() external view returns (address);
    function getSplit(uint256 splitId)
        external
        view
        returns (address creator, uint256 balance, uint256 totalDistributed, uint256 recipientCount);
}

/// @notice CCTP V2 token messenger supporting forwarding hooks.
interface ITokenMessengerV2 {
    function depositForBurnWithHook(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        bytes calldata hookData
    ) external;
}

/// @title StrPoints
/// @notice Awards capped points for qualifying wrapped split actions and uncapped daily check-ins.
/// @dev Configure with the existing factory and its USDC token. Deposit funds are
///      forwarded to the factory; this wrapper does not change factory fees.
contract StrPoints is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    address public immutable factory;
    uint256 public immutable dayLength;
    address public immutable tokenMessenger;
    /// @notice Paired destination's Circle CCTP domain (6: Base Sepolia; 26: Arc Testnet).
    uint32 public immutable destinationDomain;

    /// @notice Circle Forwarding Service hook: cctp-forward, version zero, empty payload.
    bytes public constant FORWARD_HOOK = hex"636374702d666f72776172640000000000000000000000000000000000000000";

    uint256 public constant DEPOSIT_POINTS = 5;
    uint256 public constant DISTRIBUTE_POINTS = 5;
    uint256 public constant CHECKIN_POINTS = 5;
    uint256 public constant STREAK_BONUS = 25;
    uint8 public constant STREAK_LENGTH = 7;
    uint256 public constant BASE_DAILY_CAP = 50;

    uint8 public constant REASON_DEPOSIT = 1;
    uint8 public constant REASON_DISTRIBUTE = 2;
    uint8 public constant REASON_CHECKIN = 3;
    uint8 public constant REASON_STREAK_BONUS = 4;
    uint8 public constant REASON_BRIDGE = 5;

    uint8 public constant SKIP_BELOW_MIN = 1;
    uint8 public constant SKIP_DAILY_CAP = 2;

    struct Profile {
        uint256 points;
        uint64 lastCheckInDay1;
        uint8 streak;
        bool registered;
        uint64 activityDay1;
        uint16 activityPoints;
        uint8 activityTier; // Highest tier + 1; zero means no qualifying activity in the stored day.
    }

    mapping(address => Profile) private _profiles;
    address[] private _users;

    error ZeroAddress();
    error InvalidDayLength();
    error ZeroAmount();
    error AlreadyCheckedIn();
    error FeeTooHigh();
    error InvalidMaxFee();
    error InvalidFinality();

    event PointsAwarded(address indexed user, uint256 amount, uint8 reason);
    event PointsSkipped(address indexed user, uint8 reason, uint8 cause);
    event CheckedIn(address indexed user, uint8 streakAfter, bool bonusAwarded);
    event Bridged(
        address indexed user,
        address indexed recipient,
        uint256 amount,
        uint256 platformFee,
        uint256 burnAmount,
        uint256 maxFee
    );

    /// @notice Sets the factory, six-decimal USDC, day duration, CCTP V2 messenger and paired domain.
    constructor(
        address _factory,
        address _usdc,
        uint256 _dayLength,
        address _tokenMessenger,
        uint32 _destinationDomain
    ) {
        if (_factory == address(0) || _usdc == address(0)) revert ZeroAddress();
        if (_dayLength == 0) revert InvalidDayLength();
        if (_tokenMessenger == address(0)) revert ZeroAddress();
        factory = _factory;
        usdc = IERC20(_usdc);
        dayLength = _dayLength;
        tokenMessenger = _tokenMessenger;
        destinationDomain = _destinationDomain;
    }

    /// @notice Forwards a USDC deposit and awards capped points after success if the gross amount qualifies.
    /// @dev The caller must first approve this wrapper for amount USDC.
    function depositToSplit(uint256 splitId, uint256 amount, uint256 expectedVersion) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        usdc.forceApprove(factory, amount);
        ISplitFactory(factory).deposit(splitId, amount, expectedVersion);
        usdc.forceApprove(factory, 0);
        _awardActivity(msg.sender, amount, REASON_DEPOSIT);
    }

    /// @notice Distributes a split and awards capped points after success if its pre-distribution balance qualifies.
    function distribute(uint256 splitId) external nonReentrant {
        (, uint256 balance,,) = ISplitFactory(factory).getSplit(splitId);
        ISplitFactory(factory).distribute(splitId);
        _awardActivity(msg.sender, balance, REASON_DISTRIBUTE);
    }

    /// @notice Bridges net USDC through CCTP V2 and awards capped points on the gross amount.
    /// @dev Approve this wrapper for amount; finality must be 1000 (fast) or 2000 (standard).
    ///      The platform fee is bounded by maxPlatformFeeBps; maxFee bounds the CCTP fee.
    function bridge(
        uint256 amount,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        address recipient,
        uint16 maxPlatformFeeBps
    ) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (minFinalityThreshold != 1000 && minFinalityThreshold != 2000) revert InvalidFinality();

        uint16 bps = ISplitFactory(factory).feeBps();
        address feeTo = ISplitFactory(factory).feeRecipient();
        if (bps > maxPlatformFeeBps) revert FeeTooHigh();

        uint256 platformFee = amount * bps / 10_000;
        uint256 burnAmount = amount - platformFee;
        if (maxFee >= burnAmount) revert InvalidMaxFee();

        usdc.safeTransferFrom(msg.sender, address(this), amount);
        if (platformFee > 0) {
            usdc.safeTransfer(feeTo, platformFee);
        }

        usdc.forceApprove(tokenMessenger, burnAmount);
        ITokenMessengerV2(tokenMessenger).depositForBurnWithHook(
            burnAmount,
            destinationDomain,
            bytes32(uint256(uint160(recipient))),
            address(usdc),
            bytes32(0),
            maxFee,
            minFinalityThreshold,
            FORWARD_HOOK
        );
        usdc.forceApprove(tokenMessenger, 0);

        _awardActivity(msg.sender, amount, REASON_BRIDGE);
        emit Bridged(msg.sender, recipient, amount, platformFee, burnAmount, maxFee);
    }

    /// @notice Quotes the platform fee and amount to burn using the factory's current fee.
    function previewBridge(uint256 amount)
        external
        view
        returns (uint256 platformFee, uint256 burnAmount, uint16 feeBpsNow)
    {
        feeBpsNow = ISplitFactory(factory).feeBps();
        platformFee = amount * feeBpsNow / 10_000;
        burnAmount = amount - platformFee;
    }

    /// @notice Checks in once per day, with a bonus every seven consecutive days.
    function checkIn() external {
        uint256 day = block.timestamp / dayLength;
        Profile storage p = _profiles[msg.sender];
        if (p.lastCheckInDay1 == day + 1) revert AlreadyCheckedIn();

        if (p.lastCheckInDay1 != 0 && p.lastCheckInDay1 == day && p.streak > 0) {
            p.streak += 1;
        } else {
            p.streak = 1;
        }
        p.lastCheckInDay1 = uint64(day + 1);

        _award(msg.sender, CHECKIN_POINTS, REASON_CHECKIN);
        uint8 streakAfter = p.streak;
        bool bonusAwarded = streakAfter == STREAK_LENGTH;
        if (bonusAwarded) {
            _award(msg.sender, STREAK_BONUS, REASON_STREAK_BONUS);
            p.streak = 0;
        }
        emit CheckedIn(msg.sender, streakAfter, bonusAwarded);
    }

    /// @notice Returns the user's total points.
    function pointsOf(address user) external view returns (uint256) {
        return _profiles[user].points;
    }

    /// @notice Returns the stored streak if it is still alive, otherwise zero.
    function currentStreak(address user) public view returns (uint8) {
        Profile storage p = _profiles[user];
        uint256 day = block.timestamp / dayLength;
        if (p.lastCheckInDay1 != 0 && day <= p.lastCheckInDay1) {
            return p.streak;
        }
        return 0;
    }

    /// @notice Returns points, the live streak and when the next check-in is allowed.
    function checkInStatus(address user)
        external
        view
        returns (uint256 points, uint8 streak, bool canCheckInNow, uint256 secondsUntilNext)
    {
        Profile storage p = _profiles[user];
        uint256 day = block.timestamp / dayLength;
        points = p.points;
        streak = currentStreak(user);
        canCheckInNow = p.lastCheckInDay1 != day + 1;
        if (!canCheckInNow) {
            secondsUntilNext = ((day + 1) * dayLength) - block.timestamp;
        }
    }

    /// @notice Returns uncapped activity points and tier for an amount in six-decimal USDC base units.
    /// @dev Below 1 USDC returns (0, 0, false); tier zero is meaningful only when qualifies is true.
    function pointsForAmount(uint256 amount) external pure returns (uint256 points, uint8 tier, bool qualifies) {
        (qualifies, tier, points) = _tierOf(amount);
    }

    /// @notice Returns the shared daily activity cap for a tier; values above five clamp to tier five.
    function dailyCapForTier(uint8 tier) external pure returns (uint256) {
        return _capForTier(tier);
    }

    /// @notice Returns today's activity earnings, cap and highest tier, excluding check-ins and bonuses.
    /// @dev With no qualifying activity today returns (0, 50, 0, false).
    function activityStatus(address user)
        external
        view
        returns (uint256 earnedToday, uint256 capToday, uint8 tierToday, bool hasTier)
    {
        Profile storage p = _profiles[user];
        uint256 day = block.timestamp / dayLength;
        capToday = BASE_DAILY_CAP;
        if (p.activityDay1 == day + 1) {
            earnedToday = p.activityPoints;
            hasTier = p.activityTier != 0;
            if (hasTier) {
                tierToday = p.activityTier - 1;
                capToday = _capForTier(tierToday);
            }
        }
    }

    /// @notice Returns the number of users who have earned points.
    function userCount() external view returns (uint256) {
        return _users.length;
    }

    /// @notice Returns a page of users and points in registration order, not score order.
    function getUsers(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory users, uint256[] memory pts)
    {
        uint256 length = _users.length;
        if (offset >= length) {
            return (new address[](0), new uint256[](0));
        }
        uint256 remaining = length - offset;
        if (limit > remaining) limit = remaining;
        users = new address[](limit);
        pts = new uint256[](limit);
        for (uint256 i = 0; i < limit; ++i) {
            address user = _users[offset + i];
            users[i] = user;
            pts[i] = _profiles[user].points;
        }
    }

    /// @dev Fixed amount tiers in six-decimal USDC base units, without storage lookups.
    function _tierOf(uint256 amount) internal pure returns (bool qualifies, uint8 tier, uint256 points) {
        if (amount < 1e6) return (false, 0, 0);
        if (amount < 10e6) return (true, 0, 5);
        if (amount < 50e6) return (true, 1, 25);
        if (amount < 100e6) return (true, 2, 50);
        if (amount < 250e6) return (true, 3, 75);
        if (amount < 1000e6) return (true, 4, 100);
        return (true, 5, 150);
    }

    /// @dev Fixed daily caps; out-of-range tiers clamp to tier five.
    function _capForTier(uint8 tier) internal pure returns (uint256) {
        if (tier == 0) return BASE_DAILY_CAP;
        if (tier == 1) return 75;
        if (tier == 2) return 100;
        if (tier == 3) return 150;
        if (tier == 4) return 200;
        return 600;
    }

    /// @dev Raises today's highest tier before applying the shared cap; partial awards are allowed.
    function _awardActivity(address user, uint256 amount, uint8 reason) internal {
        (bool qualifies, uint8 tier, uint256 points) = _tierOf(amount);
        if (!qualifies) {
            emit PointsSkipped(user, reason, SKIP_BELOW_MIN);
            return;
        }
        Profile storage p = _profiles[user];
        uint256 day = block.timestamp / dayLength;
        if (p.activityDay1 != day + 1) {
            p.activityDay1 = uint64(day + 1);
            p.activityPoints = 0;
            p.activityTier = 0;
        }
        uint8 encodedTier = tier + 1;
        if (encodedTier > p.activityTier) p.activityTier = encodedTier;
        uint256 cap = _capForTier(p.activityTier - 1);
        uint256 remaining = cap > p.activityPoints ? cap - p.activityPoints : 0;
        if (remaining == 0) {
            emit PointsSkipped(user, reason, SKIP_DAILY_CAP);
            return;
        }
        uint256 awarded = points < remaining ? points : remaining;
        _award(user, awarded, reason);
        p.activityPoints += uint16(awarded);
    }

    /// @dev Registers a user once and records a points award with its reason.
    function _award(address user, uint256 amount, uint8 reason) internal {
        Profile storage p = _profiles[user];
        if (!p.registered) {
            p.registered = true;
            _users.push(user);
        }
        p.points += amount;
        emit PointsAwarded(user, amount, reason);
    }
}
