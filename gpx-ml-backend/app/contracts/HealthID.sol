// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IRewardPoolManager {
    function insurers(address insurer)
        external
        view
        returns (
            string memory name,
            string memory licenseInfo,
            bool isActive,
            uint256 registeredAt
        );
}

contract HealthID {
    struct UserInfo {
        address user;
        string name;
        uint256 dob;
        string policyNo;
        uint256 contractValue;
        address insurer;
    }

    mapping(address => UserInfo) public users;
    IRewardPoolManager public rewardPoolManager;

    event UserRegistered(address indexed user, string name, address insurer, uint256 contractValue);
    event UserBurned(address indexed user);

    constructor(address _rewardPoolManager) {
        require(_rewardPoolManager != address(0), "Invalid RewardPoolManager");
        rewardPoolManager = IRewardPoolManager(_rewardPoolManager);
    }

    function registerUser(
        string memory name,
        uint256 dob,
        string memory policyNo,
        uint256 contractValue,
        address insurer
    ) external {
        require(users[msg.sender].user == address(0), "Already registered");
        require(insurer != address(0), "Invalid insurer");
        require(contractValue > 0, "Contract value must be greater than 0");

        users[msg.sender] = UserInfo({
            user: msg.sender,
            name: name,
            dob: dob,
            policyNo: policyNo,
            contractValue: contractValue,
            insurer: insurer
        });

        emit UserRegistered(msg.sender, name, insurer, contractValue);
    }

    function burnHealthID() external {
        require(users[msg.sender].user != address(0), "Not registered");
        delete users[msg.sender];
        emit UserBurned(msg.sender);
    }

    // Backward-compatible: returns ONLY the insurer address (what ActivityLogger expects)
    function getUserInsurer(address user) external view returns (address) {
        require(users[user].user != address(0), "User not found");
        return users[user].insurer;
    }

    // New helper with full info (for UI)
    function getUserInsurerInfo(address user)
        external
        view
        returns (string memory insurerName, address insurerAddress, string memory licenseInfo)
    {
        require(users[user].user != address(0), "User not found");
        insurerAddress = users[user].insurer;
        (insurerName, licenseInfo, , ) = rewardPoolManager.insurers(insurerAddress);
    }
}
