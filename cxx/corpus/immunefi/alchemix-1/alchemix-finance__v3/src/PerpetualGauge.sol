// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IStrategyClassifier } from "./interfaces/IStrategyClassifier.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IAllocatorProxy {
    function allocate(uint256 strategyId, uint256 amount) external;
}

contract PerpetualGauge is ReentrancyGuard {
    event VoteUpdated(address indexed voter, uint256 ytId, uint256[] strategyIds, uint256[] weights, uint256 expiry);
    event AllocationExecuted(uint256 ytId, uint256[] strategyIds, uint256[] amounts);
    event VoterCleared(address indexed voter, uint256 ytId);

    struct Vote {
        uint256[] strategyIds;
        uint256[] weights;
        uint256 expiry;
    }

    IStrategyClassifier public stratClassifier;
    IAllocatorProxy public allocatorProxy;
    IERC20 public votingToken;

    uint256 public constant MAX_VOTE_DURATION = 365 days;
    uint256 public constant MIN_RESET_DURATION = 30 days;

    mapping(uint256 => mapping(address => Vote)) public votes;
    mapping(uint256 => uint256) public lastStrategyAddedAt;

    mapping(uint256 => address[]) private voters;
    mapping(uint256 => mapping(address => uint256)) private voterIndex;

    // Aggregate weighted votes per MYT + strategy
    mapping(uint256 => mapping(uint256 => uint256)) private aggStrategyWeight;

    constructor(address _stratClassifier, address _allocatorProxy, address _votingToken) {
        require(_stratClassifier != address(0) && _allocatorProxy != address(0) && _votingToken != address(0), "Bad address");
        stratClassifier = IStrategyClassifier(_stratClassifier);
        allocatorProxy = IAllocatorProxy(_allocatorProxy);
        votingToken = IERC20(_votingToken);
    }

    function vote(uint256 ytId, uint256[] calldata strategyIds, uint256[] calldata weights) external nonReentrant {
        require(strategyIds.length == weights.length && strategyIds.length > 0, "Invalid input");

        uint256 lastAdded = lastStrategyAddedAt[ytId];
        Vote storage existing = votes[ytId][msg.sender];
        uint256 expiry;

        if (existing.expiry > block.timestamp) {
            uint256 timeLeft = existing.expiry - block.timestamp;
            if (lastAdded > 0 && block.timestamp - lastAdded < MIN_RESET_DURATION && timeLeft < MIN_RESET_DURATION) {
                expiry = existing.expiry;
            } else {
                expiry = block.timestamp + MAX_VOTE_DURATION;
            }
        } else {
            expiry = block.timestamp + MAX_VOTE_DURATION;
        }

        uint256 power = votingToken.balanceOf(msg.sender);

        // 1. Remove old vote contribution from aggregate
        if (existing.strategyIds.length > 0 && existing.expiry > block.timestamp) {
            for (uint256 i = 0; i < existing.strategyIds.length; i++) {
                uint256 sid = existing.strategyIds[i];
                uint256 prevWeighted = existing.weights[i] * power;
                aggStrategyWeight[ytId][sid] -= prevWeighted;
            }
        }

        // 2. Store new vote
        votes[ytId][msg.sender] = Vote({ strategyIds: strategyIds, weights: weights, expiry: expiry });

        // 3. Add new contribution
        for (uint256 i = 0; i < strategyIds.length; i++) {
            uint256 sid = strategyIds[i];
            uint256 newWeighted = weights[i] * power;
            aggStrategyWeight[ytId][sid] += newWeighted;
        }

        // 4. Track voter in registry
        if (voterIndex[ytId][msg.sender] == 0) {
            voters[ytId].push(msg.sender);
            voterIndex[ytId][msg.sender] = voters[ytId].length; // 1-based
        }

        emit VoteUpdated(msg.sender, ytId, strategyIds, weights, expiry);
    }

    function clearVote(uint256 ytId) external nonReentrant {
        Vote storage v = votes[ytId][msg.sender];
        require(v.strategyIds.length > 0, "No vote");

        uint256 power = votingToken.balanceOf(msg.sender);

        for (uint256 i = 0; i < v.strategyIds.length; i++) {
            uint256 sid = v.strategyIds[i];
            uint256 weighted = v.weights[i] * power;
            aggStrategyWeight[ytId][sid] -= weighted;
        }

        delete votes[ytId][msg.sender];
        emit VoterCleared(msg.sender, ytId);
    }

    function registerNewStrategy(uint256 ytId, uint256 strategyId) external nonReentrant {
        lastStrategyAddedAt[ytId] = block.timestamp;
        // TODO
    }

    function getCurrentAllocations(uint256 ytId) public view
        returns (uint256[] memory strategyIds, uint256[] memory normalizedWeights)
    {
        uint256 n = strategyList[ytId].length;
        strategyIds = new uint256[](n);
        normalizedWeights = new uint256[](n);

        uint256 total;
        for (uint256 i; i < n; i++) {
            uint256 sid = strategyList[ytId][i];
            strategyIds[i] = sid;
            uint256 w = aggStrategyWeight[ytId][sid];
            normalizedWeights[i] = w;
            total += w;
        }

        for (uint256 i; i < n; i++) {
            if (total > 0) {
                normalizedWeights[i] = (normalizedWeights[i] * 1e18) / total;
            }
        }
    }

    function executeAllocation(uint256 ytId, uint256 totalIdleAssets) external nonReentrant {
        (uint256[] memory sIds, uint256[] memory weights) = getCurrentAllocations(ytId);
        require(sIds.length > 0, "No allocations");

        uint256 totalRiskAllocated;
        uint256[] memory allocatedAmounts = new uint256[](sIds.length);

        for (uint256 i = 0; i < sIds.length; i++) {
            uint8 risk = stratClassifier.getStrategyRiskLevel(sIds[i]);
            uint256 indivCap = stratClassifier.getIndividualCap(sIds[i]);
            uint256 globalCap = stratClassifier.getGlobalCap(risk);

            uint256 target = (weights[i] * totalIdleAssets) / 1e18;

            // Individual cap
            uint256 capIndiv = (indivCap * totalIdleAssets) / 1e4;
            if (target > capIndiv) target = capIndiv;

            // Global cap for risk group
            if (risk > 0) {
                uint256 capGlobalLeft = (globalCap * totalIdleAssets) / 1e4 - totalRiskAllocated;
                if (target > capGlobalLeft) target = capGlobalLeft;
                totalRiskAllocated += target;
            }

            if (target > 0) {
                // TODO double-check limits here?
                allocatorProxy.allocate(sIds[i], target);
            }

            allocatedAmounts[i] = target;
        }

        emit AllocationExecuted(ytId, sIds, allocatedAmounts);
    }

    // to keep track of strategies per ytId for getCurrentAllocations
    mapping(uint256 => uint256[]) public strategyList;
}
