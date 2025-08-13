// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract RewardPoolManager is AccessControl, ReentrancyGuard {
    bytes32 public constant INSURER_ROLE        = keccak256("INSURER_ROLE");
    bytes32 public constant REWARD_MANAGER_ROLE = keccak256("REWARD_MANAGER_ROLE");

    struct InsurerProfile {
        string  name;
        string  licenseInfo;
        bool    isActive;
        uint256 registeredAt;
    }

    // balances + stats
    mapping(address => uint256) public insurerBalances;                 // balance per insurer
    mapping(address => uint256) public insurerRewardCount;              // total rewards paid (count)
    mapping(address => mapping(address => bool)) public insurerRewardedUser; // insurer => user => rewarded?
    mapping(address => uint256) public insurerRewardUserCount;          // unique rewarded users count
    mapping(address => InsurerProfile) public insurers;                 // insurer addr => profile

    event InsurerRegistered(address indexed insurer, string name, string licenseInfo, uint256 amount);
    event FundAdded(address indexed insurer, uint256 amount);
    event RewardPaid(address indexed insurer, address indexed user, uint256 amount, address indexed caller);
    event WithdrawnByAdmin(address indexed to, uint256 amount);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Register a new insurer with name, address and license info. Send ETH as initial funding.
    function registerInsurer(
        string calldata name,
        address insurer,
        string calldata licenseInfo
    ) external payable {
        require(insurer != address(0), "Invalid insurer address");
        require(bytes(name).length > 0, "Name required");
        require(bytes(licenseInfo).length > 0, "License info required");
        require(msg.value > 0, "Must deposit ETH to register");
        require(!insurers[insurer].isActive, "Insurer already registered");

        insurers[insurer] = InsurerProfile({
            name: name,
            licenseInfo: licenseInfo,
            isActive: true,
            registeredAt: block.timestamp
        });

        _grantRole(INSURER_ROLE, insurer);
        insurerBalances[insurer] += msg.value;

        emit InsurerRegistered(insurer, name, licenseInfo, msg.value);
    }

    /// @notice Add more funds (only the insurer can top up their own balance)
    function fundMore() external payable onlyRole(INSURER_ROLE) {
        require(msg.value > 0, "No ETH sent");
        require(insurers[msg.sender].isActive, "Insurer not active");
        insurerBalances[msg.sender] += msg.value;
        emit FundAdded(msg.sender, msg.value);
    }

    /// @notice Pay reward to a user (Admin, Insurer itself, or Reward Manager can call)
    function payReward(address insurer, address user, uint256 amount)
        external
        nonReentrant
    {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) ||
            (hasRole(INSURER_ROLE, msg.sender) && msg.sender == insurer) ||
            hasRole(REWARD_MANAGER_ROLE, msg.sender),
            "Not authorized"
        );
        require(insurers[insurer].isActive, "Insurer not active");
        require(user != address(0), "Invalid user");
        require(amount > 0, "Invalid amount");
        require(insurerBalances[insurer] >= amount, "Insufficient balance");

        insurerBalances[insurer] -= amount;
        (bool sent, ) = payable(user).call{value: amount}("");
        require(sent, "Transfer failed");

        // Update reward stats
        insurerRewardCount[insurer] += 1;
        if (!insurerRewardedUser[insurer][user]) {
            insurerRewardedUser[insurer][user] = true;
            insurerRewardUserCount[insurer] += 1;
        }

        emit RewardPaid(insurer, user, amount, msg.sender);
    }

    /// @notice Quick check: returns the insurer's name and current balance
    function getInsurerBalanceWithName(address insurer)
        external
        view
        returns (string memory name, uint256 balance)
    {
        name = insurers[insurer].name;
        balance = insurerBalances[insurer];
    }

    /// @notice Detailed profile getter
    function getInsurerProfile(address insurer)
        external
        view
        returns (string memory name, string memory licenseInfo, bool isActive, uint256 registeredAt, uint256 balance)
    {
        InsurerProfile memory p = insurers[insurer];
        return (p.name, p.licenseInfo, p.isActive, p.registeredAt, insurerBalances[insurer]);
    }

    /// @notice Reward stats for an insurer
    function getInsurerRewardStats(address insurer)
        external
        view
        returns (uint256 totalRewards, uint256 uniqueUsers)
    {
        return (insurerRewardCount[insurer], insurerRewardUserCount[insurer]);
    }

    /// @notice Admin withdraw to any address, up to current contract balance
    function withdrawTo(address to, uint256 amount)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(to != address(0), "Invalid recipient");
        require(amount > 0 && amount <= address(this).balance, "Invalid amount");

        (bool sent, ) = payable(to).call{value: amount}("");
        require(sent, "Withdraw failed");

        emit WithdrawnByAdmin(to, amount);
    }

    /// @notice Total ETH in the contract
    function contractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {}
}
