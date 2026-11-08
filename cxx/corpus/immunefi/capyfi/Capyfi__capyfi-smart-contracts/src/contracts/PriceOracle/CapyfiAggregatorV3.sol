// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Ownable2Step } from "openzeppelin-contracts/access/Ownable2Step.sol";
import { AggregatorV2V3Interface } from "./AggregatorV3Interface.sol";

contract CapyfiAggregatorV3 is AggregatorV2V3Interface, Ownable2Step {
    
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    uint8 private immutable _decimals;
    string private _description;
    uint256 private immutable _version;
    
    // Chainlink-compatible round ID management
    uint16 private currentPhaseId;
    uint64 private currentRoundId; // Original ID within phase
    mapping(uint80 => RoundData) private rounds;
    RoundData private _latestRound;
    
    // Optional price bounds 
    int256 public minAnswer;
    int256 public maxAnswer;
    bool public boundChecksEnabled;
    
    /// @dev Mapping of addresses authorized to update price feeds, in addition to the owner
    mapping(address => bool) public authorizedAddresses;

    /// @dev Emitted when an address is granted authorization to update prices
    /// @param addr The address that was granted authorization
    event AuthorizedAddressAdded(address indexed addr);
    
    /// @dev Emitted when an address has its authorization to update prices removed
    /// @param addr The address that had its authorization removed
    event AuthorizedAddressRemoved(address indexed addr);

    /// @dev Emitted when price bounds are configured
    /// @param minAnswer The minimum allowed price
    /// @param maxAnswer The maximum allowed price
    /// @param enabled Whether bounds checking is enabled
    event BoundsConfigured(int256 minAnswer, int256 maxAnswer, bool enabled);

    /// @dev Emitted when bounds checking is toggled
    /// @param enabled Whether bounds checking is enabled
    event BoundChecksToggled(bool enabled);

    error UnauthorizedCaller(address caller);
    error InvalidAddress(address addr);
    error InvalidPrice(int256 price);
    error PriceOutOfBounds(int256 price, int256 min, int256 max);
    error InvalidBounds(int256 min, int256 max);
    error NoRoundsAvailable();
    error AddressAlreadyAuthorized(address addr);
    error AddressNotAuthorized(address addr);

    modifier onlyAuthorized() {
        if (msg.sender != owner() && !authorizedAddresses[msg.sender]) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    /**
     * @notice Deploy the contract with initial parameters
     * @param decimals_ Number of decimals for the price feed
     * @param description_ Description of what this aggregator represents
     * @param version_ Version of the aggregator
     * @param initialPrice Initial price to set (cannot be 0)
     */
    constructor(
        uint8 decimals_,
        string memory description_,
        uint256 version_,
        int256 initialPrice
    ) {
        if (initialPrice <= 0) revert InvalidPrice(initialPrice);
        _decimals = decimals_;
        _description = description_;
        _version = version_;
        
        // Start with phase 1, round 1 (Chainlink-compatible)
        // This will create the first round ID as (1 << 64) + 1 = 18446744073709551617
        currentPhaseId = 1;
        currentRoundId = 1;
        
        _updateAnswer(initialPrice);
    }

    /**
     * @notice Add an authorized address that can update prices
     * @param addr Address to authorize
     */
    function addAuthorizedAddress(address addr) external onlyOwner {
        if (addr == address(0)) revert InvalidAddress(addr);
        if (authorizedAddresses[addr]) revert AddressAlreadyAuthorized(addr);
        authorizedAddresses[addr] = true;
        emit AuthorizedAddressAdded(addr);
    }

    /**
     * @notice Remove an authorized address
     * @param addr Address to remove authorization from
     */
    function removeAuthorizedAddress(address addr) external onlyOwner {
        if (addr == address(0)) revert InvalidAddress(addr);
        if (!authorizedAddresses[addr]) revert AddressNotAuthorized(addr);
        authorizedAddresses[addr] = false;
        emit AuthorizedAddressRemoved(addr);
    }

    /**
     * @notice Set price bounds (optional, like Chainlink)
     * @param _minAnswer Minimum allowed price
     * @param _maxAnswer Maximum allowed price
     * @param _enabled Whether to enable bounds checking
     */
    function setBounds(int256 _minAnswer, int256 _maxAnswer, bool _enabled) external onlyOwner {
        if (_minAnswer >= _maxAnswer) revert InvalidBounds(_minAnswer, _maxAnswer);
        
        minAnswer = _minAnswer;
        maxAnswer = _maxAnswer;
        boundChecksEnabled = _enabled;
        
        emit BoundsConfigured(_minAnswer, _maxAnswer, _enabled);
    }

    /**
     * @notice Toggle bounds checking on/off
     * @param _enabled Whether to enable bounds checking
     */
    function toggleBoundsChecking(bool _enabled) external onlyOwner {
        boundChecksEnabled = _enabled;
        emit BoundChecksToggled(_enabled);
    }

    /**
     * @notice Update the price (only owner or authorized addresses)
     * @param newAnswer New price to set
     */
    function updateAnswer(int256 newAnswer) external onlyAuthorized {
        if (newAnswer <= 0) revert InvalidPrice(newAnswer);
        
        // Optional bounds checking 
        if (boundChecksEnabled) {
            if (newAnswer < minAnswer || newAnswer > maxAnswer) {
                revert PriceOutOfBounds(newAnswer, minAnswer, maxAnswer);
            }
        }
        
        _updateAnswer(newAnswer);
    }

    /**
     * @notice Internal function to update the answer and create a new round
     * @param newAnswer New price to set
     */
    function _updateAnswer(int256 newAnswer) internal {
        uint256 timestamp = block.timestamp;
        
        // Create Chainlink-compatible round ID: (phaseId << 64) + originalId
        uint80 roundId = uint80((uint256(currentPhaseId) << 64) + currentRoundId);
        
        RoundData memory newRound = RoundData({
            roundId: roundId,
            answer: newAnswer,
            startedAt: timestamp,
            updatedAt: timestamp,
            answeredInRound: roundId
        });
        
        rounds[roundId] = newRound;
        _latestRound = newRound;
        
        emit AnswerUpdated(newAnswer, roundId, timestamp);
        emit NewRound(roundId, msg.sender, timestamp);
        
        currentRoundId++;
    }

    // AggregatorInterface (V2) implementation
    
    /**
     * @notice Get the latest answer without round data
     */
    function latestAnswer() external view override returns (int256) {
        if (_latestRound.roundId == 0) revert NoRoundsAvailable();
        return _latestRound.answer;
    }

    /**
     * @notice Get the timestamp of the latest update
     */
    function latestTimestamp() external view override returns (uint256) {
        if (_latestRound.roundId == 0) revert NoRoundsAvailable();
        return _latestRound.updatedAt;
    }

    /**
     * @notice Get the latest round ID (Chainlink-compatible format)
     */
    function latestRound() external view override returns (uint256) {
        return _latestRound.roundId;
    }

    /**
     * @notice Get the answer for a specific round (Chainlink-compatible)
     * @param roundId The round ID to get the answer for
     * @return answer The price, or 0 if round doesn't exist
     */
    function getAnswer(uint256 roundId) external view override returns (int256) {
        // Return 0 for invalid round IDs (like Chainlink)
        if (roundId > type(uint80).max) return 0;
        
        RoundData memory round = rounds[uint80(roundId)];
        return round.answer; // Returns 0 if round doesn't exist
    }

    /**
     * @notice Get the timestamp for a specific round (Chainlink-compatible)
     * @param roundId The round ID to get the timestamp for
     * @return timestamp The timestamp, or 0 if round doesn't exist
     */
    function getTimestamp(uint256 roundId) external view override returns (uint256) {
        // Return 0 for invalid round IDs (like Chainlink)
        if (roundId > type(uint80).max) return 0;
        
        RoundData memory round = rounds[uint80(roundId)];
        return round.updatedAt; // Returns 0 if round doesn't exist
    }

    // AggregatorV3Interface implementation

    /**
     * @notice Returns the number of decimals
     */
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Returns the description
     */
    function description() external view override returns (string memory) {
        return _description;
    }

    /**
     * @notice Returns the version
     */
    function version() external view override returns (uint256) {
        return _version;
    }

    /**
     * @notice Get data from a specific round (Chainlink-compatible)
     * @param roundId The round ID to retrieve data for
     * @return roundId_ The round ID (0 if round doesn't exist)
     * @return answer The price (0 if round doesn't exist)
     * @return startedAt The timestamp when round started (0 if round doesn't exist)  
     * @return updatedAt The timestamp when round was updated (0 if round doesn't exist)
     * @return answeredInRound The round ID in which the answer was computed (0 if round doesn't exist)
     */
    function getRoundData(uint80 roundId) 
        external 
        view 
        override 
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        ) 
    {
        RoundData memory round = rounds[roundId];
        
        // Return zeros for non-existent rounds (like Chainlink)
        return (
            round.roundId,        
            round.answer,         
            round.startedAt,      
            round.updatedAt,     
            round.answeredInRound 
        );
    }

    /**
     * @notice Get data from the latest round
     */
    function latestRoundData()
        external
        view
        override
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        if (_latestRound.roundId == 0) revert NoRoundsAvailable();
        
        return (
            _latestRound.roundId,
            _latestRound.answer,
            _latestRound.startedAt,
            _latestRound.updatedAt,
            _latestRound.answeredInRound
        );
    }

    // Helper functions for Chainlink compatibility

    /**
     * @notice Helper function to check if a round exists
     * @param roundId The round ID to check
     * @return exists Whether the round exists
     */
    function roundExists(uint80 roundId) external view returns (bool) {
        return rounds[roundId].roundId != 0;
    }

    /**
     * @notice Get current phase and round info
     * @return phaseId Current phase ID
     * @return roundId Current round ID within the phase
     */
    function getCurrentPhaseInfo() external view returns (uint16 phaseId, uint64 roundId) {
        return (currentPhaseId, currentRoundId);
    }

    /**
     * @notice Extract phase ID from a round ID
     * @param roundId The round ID to extract from
     * @return phaseId The phase ID
     */
    function getPhaseId(uint80 roundId) external pure returns (uint16) {
        return uint16(roundId >> 64);
    }

    /**
     * @notice Extract original round ID from a round ID
     * @param roundId The round ID to extract from
     * @return originalRoundId The original round ID within the phase
     */
    function getOriginalRoundId(uint80 roundId) external pure returns (uint64) {
        return uint64(roundId);
    }
} 