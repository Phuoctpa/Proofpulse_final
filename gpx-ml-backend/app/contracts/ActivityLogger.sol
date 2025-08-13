// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IHealthID {
    function getUserInsurer(address user) external view returns (address);
}

interface IRewardPoolManager {
    function payReward(address insurer, address user, uint256 amount) external;
}

contract ActivityLogger is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    struct Activity {
        uint256 distanceKmX100; // km × 100 (e.g., 607 = 6.07 km)
        uint256 elevationGainM; // meters
        uint256 timestamp;      // unix timestamp (auto-filled if 0)
        bool isRewarded;
    }

    mapping(address => Activity[]) public userActivities;

    uint256 public distanceThreshold   = 500;        // 5.00 km
    uint256 public elevationThreshold  = 100;        // 100 m
    uint256 public rewardAmount        = 0.001 ether;
    uint256 public constant MAX_FUTURE_SKEW = 5 minutes; // optional guard

    IHealthID public healthID;
    IRewardPoolManager public rewardPool;

    event ActivityLogged(address indexed user, uint256 distanceKmX100, uint256 elevationGainM, uint256 timestamp);
    event RewardRedeemed(address indexed user, uint256 amount, uint256 eligibleCount);

    constructor(address _healthID, address _rewardPool) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        healthID = IHealthID(_healthID);
        rewardPool = IRewardPoolManager(_rewardPool);
    }

    /// Log activity (distance, elevation, timestamp). If timestamp==0, uses block.timestamp.
    function logActivity(
        uint256 distanceKmX100,
        uint256 elevationGainM,
        uint256 activityTimestamp
    ) external {
        require(distanceKmX100 > 0 || elevationGainM > 0, "Invalid activity data");

        uint256 ts = activityTimestamp == 0 ? block.timestamp : activityTimestamp;
        require(ts <= block.timestamp + MAX_FUTURE_SKEW, "Timestamp in future");

        userActivities[msg.sender].push(Activity({
            distanceKmX100: distanceKmX100,
            elevationGainM: elevationGainM,
            timestamp: ts,
            isRewarded: false
        }));

        emit ActivityLogged(msg.sender, distanceKmX100, elevationGainM, ts);
    }

    /// Read all activities for a given user
    function getUserActivities(address user) external view returns (Activity[] memory) {
        return userActivities[user];
    }

    /// Current thresholds
    function getThresholds() external view returns (uint256, uint256) {
        return (distanceThreshold, elevationThreshold);
    }

    /// Redeem: eligible if distance >= threshold OR elevation >= threshold. Pays per eligible log.
    function redeemReward() external nonReentrant {
        Activity[] storage logs = userActivities[msg.sender];
        uint256 eligibleCount = 0;

        for (uint256 i = 0; i < logs.length; i++) {
            if (!logs[i].isRewarded &&
                (logs[i].distanceKmX100 >= distanceThreshold || logs[i].elevationGainM >= elevationThreshold)
            ) {
                logs[i].isRewarded = true;
                eligibleCount++;
            }
        }

        require(eligibleCount > 0, "No eligible activity found");

        address insurer = healthID.getUserInsurer(msg.sender);
        require(insurer != address(0), "User not registered");

        uint256 totalReward = rewardAmount * eligibleCount;
        rewardPool.payReward(insurer, msg.sender, totalReward);

        emit RewardRedeemed(msg.sender, totalReward, eligibleCount);
    }

    /// Admin-only setters
    function setThresholds(uint256 newDistanceThreshold, uint256 newElevationThreshold)
        external onlyRole(ADMIN_ROLE)
    {
        distanceThreshold = newDistanceThreshold;
        elevationThreshold = newElevationThreshold;
    }

    function setRewardAmount(uint256 newAmount) external onlyRole(ADMIN_ROLE) {
        rewardAmount = newAmount;
    }
}
