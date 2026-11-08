// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IYBSRegistry {
    event DeployerApproved(address indexed deployer, bool indexed approved);
    event DistributorUpdated(
        address indexed token,
        address indexed distributor
    );
    event FactoriesUpdated(
        address indexed ybsFactory,
        address indexed rewardFactory,
        address indexed utilsFactory
    );
    event NewDeployment(
        address indexed yearnBoostedStaker,
        address indexed rewardDistributor,
        address indexed utilities
    );
    event OwnershipTransferred(address indexed owner);
    event UtilitiesUpdated(address indexed token, address indexed utilities);

    function VERSION() external view returns (string memory);

    function acceptOwnership() external;

    function approveDeployer(address _deployer, bool _approved) external;

    function createNewDeployment(
        address _token,
        uint256 _max_stake_growth_weeks,
        uint256 _start_time,
        address _reward_token
    )
        external
        returns (
            address ybs,
            address distributor,
            address utils
        );

    function deployments(address)
        external
        view
        returns (
            address yearnBoostedStaker,
            address rewardDistributor,
            address utilities
        );

    function factories()
        external
        view
        returns (
            address yearnBoostedStaker,
            address rewardDistributor,
            address utilities
        );

    function isApprovedDeployer(address _deployer) external view returns (bool);

    function numTokens() external view returns (uint256);

    function owner() external view returns (address);

    function pendingOwner() external view returns (address);

    function tokens(uint256) external view returns (address);

    function transferOwnership(address _pendingOwner) external;

    function updateFactories(
        address _ybsFactory,
        address _rewardFactory,
        address _utilsFactory
    ) external;

    function updateRewardDistributor(address _token, address _distributor)
        external;

    function updateUtilities(address _token, address _utils) external;
}