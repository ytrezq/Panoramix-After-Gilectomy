// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {TestBase} from "../lib/TestBase.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {TokenVotingSetup} from "../../src/TokenVotingSetup.sol";
import {TokenVoting} from "../../src/TokenVoting.sol";
import {GovernanceERC20} from "../../src/erc20/GovernanceERC20.sol";
import {MajorityVotingBase} from "../../src/base/MajorityVotingBase.sol";
import {VotingPowerCondition} from "../../src/condition/VotingPowerCondition.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

contract SimpleBuilder is TestBase {
    address immutable DAO_BASE = address(new DAO());
    address immutable TOKEN_VOTING_PLUGIN_BASE = address(new TokenVoting());
    address private constant ANY_ADDR = address(type(uint160).max);

    // Parameters to override
    address daoOwner; // Used for testing purposes only

    MajorityVotingBase.VotingMode votingMode = MajorityVotingBase.VotingMode.Standard;
    uint32 supportThreshold = 500_000; // 50%
    uint32 minParticipation = 100_000; // 10%
    uint64 minDuration = 60 * 60; // 1h
    uint256 minProposerVotingPower;

    IVotesUpgradeable token;
    address[] newTokenHolders;
    uint256[] newTokenBalances;
    address targetAddress;
    IPlugin.Operation targetOperation;
    uint256 minApprovals;
    bytes pluginMetadata;
    address[] excludedAccounts;
    bool selfDelegateOnMint = true;

    constructor() {
        // Set the caller as the initial daoOwner
        // It can grant and revoke permissions freely for testing purposes
        withDaoOwner(msg.sender);
    }

    // Override methods
    function withDaoOwner(address _newOwner) public returns (SimpleBuilder) {
        daoOwner = _newOwner;
        return this;
    }

    function withEarlyExecution() public returns (SimpleBuilder) {
        votingMode = MajorityVotingBase.VotingMode.EarlyExecution;
        return this;
    }

    function withVoteReplacement() public returns (SimpleBuilder) {
        votingMode = MajorityVotingBase.VotingMode.VoteReplacement;
        return this;
    }

    function withSupportThreshold(uint32 _newThreshold) public returns (SimpleBuilder) {
        supportThreshold = _newThreshold;
        return this;
    }

    function withMinParticipation(uint32 _newValue) public returns (SimpleBuilder) {
        minParticipation = _newValue;
        return this;
    }

    function withMinDuration(uint64 _newValue) public returns (SimpleBuilder) {
        minDuration = _newValue;
        return this;
    }

    function withMinApprovals(uint64 _newValue) public returns (SimpleBuilder) {
        minApprovals = _newValue;
        return this;
    }

    function withMinProposerVotingPower(uint256 _newValue) public returns (SimpleBuilder) {
        minProposerVotingPower = _newValue;
        return this;
    }

    // Use the given token
    function withToken(IVotesUpgradeable _newToken) public returns (SimpleBuilder) {
        token = _newToken;
        return this;
    }

    // A list of token holders, all with the same balance
    function withNewToken(address[] memory _holders, uint256 _balance) public returns (SimpleBuilder) {
        for (uint256 i = 0; i < _holders.length; i++) {
            newTokenHolders.push(_holders[i]);
            newTokenBalances.push(_balance);
        }
        return this;
    }

    // A list of token holders, each with their own balance
    function withNewToken(address[] memory _holders, uint256[] memory _balances) public returns (SimpleBuilder) {
        for (uint256 i = 0; i < _holders.length; i++) {
            newTokenHolders.push(_holders[i]);
            newTokenBalances.push(_balances[i]);
        }
        return this;
    }

    function withTargetConfig(address _target, IPlugin.Operation _operation) public returns (SimpleBuilder) {
        targetAddress = _target;
        targetOperation = _operation;
        return this;
    }

    function withPluginMetadata(bytes memory _newValue) public returns (SimpleBuilder) {
        pluginMetadata = _newValue;
        return this;
    }

    function withExcludedAccount(address account) public returns (SimpleBuilder) {
        excludedAccounts.push(account);
        return this;
    }

    function withSelfDelegationOnMint() public returns (SimpleBuilder) {
        selfDelegateOnMint = true;
        return this;
    }

    function withoutSelfDelegationOnMint() public returns (SimpleBuilder) {
        selfDelegateOnMint = false;
        return this;
    }

    /// @dev Creates a DAO with the given orchestration settings.
    function build()
        public
        returns (DAO dao, TokenVoting plugin, IVotesUpgradeable token_, VotingPowerCondition condition)
    {
        // Deploy the DAO with `daoOwner` as ROOT
        dao = DAO(
            payable(
                ProxyLib.deployUUPSProxy(
                    address(DAO_BASE), abi.encodeCall(DAO.initialize, ("", daoOwner, address(0x0), ""))
                )
            )
        );

        // Plugin params
        if (address(token) == address(0)) {
            if (newTokenHolders.length != newTokenBalances.length) {
                revert("Mismatch between token holders and balances count");
            } else if (newTokenHolders.length == 0) {
                // Fallback: Mint a token with `msg.sender`
                newTokenHolders.push(msg.sender);
                newTokenBalances.push(1000 ether);
            }

            token_ = new GovernanceERC20(
                dao,
                "MyToken",
                "SYM",
                GovernanceERC20.MintSettings(newTokenHolders, newTokenBalances, selfDelegateOnMint)
            );
        } else {
            token_ = token;
        }

        // Target the DAO by default
        if (targetAddress == address(0)) {
            targetAddress = address(dao);
        }
        IPlugin.TargetConfig memory targetConfig = IPlugin.TargetConfig(targetAddress, targetOperation);

        MajorityVotingBase.VotingSettings memory votingSettings = MajorityVotingBase.VotingSettings({
            votingMode: votingMode,
            supportThreshold: supportThreshold,
            minParticipation: minParticipation,
            minDuration: minDuration,
            minProposerVotingPower: minProposerVotingPower
        });

        // Deploy the plugin
        plugin = TokenVoting(
            ProxyLib.deployUUPSProxy(
                address(TOKEN_VOTING_PLUGIN_BASE),
                abi.encodeCall(
                    TokenVoting.initialize,
                    (dao, votingSettings, token_, targetConfig, minApprovals, pluginMetadata, excludedAccounts)
                )
            )
        );

        vm.startPrank(daoOwner);

        // Allow anyone with enough balance to create proposals (only if set)
        if (minProposerVotingPower > 0) {
            condition = new VotingPowerCondition(address(plugin));
            dao.grantWithCondition(address(plugin), ANY_ADDR, plugin.CREATE_PROPOSAL_PERMISSION_ID(), condition);
        }

        // Allow the plugin to execute on the DAO
        dao.grant(address(dao), address(plugin), dao.EXECUTE_PERMISSION_ID());

        // Make the DAO ROOT on itself
        dao.grant(address(dao), address(dao), dao.ROOT_PERMISSION_ID());

        vm.stopPrank();

        // Labels
        vm.label(address(dao), "DAO");
        vm.label(address(plugin), "TokenVoting");
        vm.label(address(token_), "Token");

        // Moving forward to ensure that snapshots are ready
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }
}
