// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IPredepostVaultOApp} from "../../src/periphery/interface/IPredepostVaultOApp.sol";

/**
 * @title MockPredepositVault
 * @notice Simplified mock vault for testing PredepostVaultOApp
 * @dev Minimal implementation with only required functions from PredepositVaultImpl
 */
contract MockPredepositVault is ERC20 {
    // Message type identifier for cross-chain claims
    uint16 public constant MSG_TYPE_CLAIM = 1;

    // The underlying asset
    IERC20 public immutable asset;

    // OApp address for cross-chain messaging
    address public oapp;

    // Self claims enabled flag
    bool public selfClaimsEnabled;

    // Locked shares tracking
    mapping(address => uint256) public lockedShares;

    // Events
    event SharesClaimedOnTargetChain(address indexed user, uint256 shares);
    event SelfClaimsEnabledUpdated(bool enabled);
    event OAppSet(address indexed oapp);

    // Errors
    error NoSharesToClaim();
    error SelfClaimsDisabled();
    error OAppNotSet();
    error DepositsNotLocked();

    constructor(address _asset, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        asset = IERC20(_asset);
    }

    /**
     * @notice Mint shares to an account (for testing)
     */
    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    /**
     * @notice Set the OApp contract address
     */
    function setOApp(address oappAddress) external {
        oapp = oappAddress;
        emit OAppSet(oappAddress);
    }

    /**
     * @notice Get the OApp contract address
     */
    function getOApp() external view returns (address) {
        return oapp;
    }

    /**
     * @notice Set self claims enabled flag
     */
    function setSelfClaimsEnabled(bool enabled) external {
        selfClaimsEnabled = enabled;
        emit SelfClaimsEnabledUpdated(enabled);
    }

    /**
     * @notice Get self claims enabled flag
     */
    function getSelfClaimsEnabled() external view returns (bool) {
        return selfClaimsEnabled;
    }

    /**
     * @notice Get locked shares for a user
     */
    function getLockedShares(address user) external view returns (uint256) {
        return lockedShares[user];
    }

    /**
     * @notice Claim shares on target chain via LayerZero
     * @dev Burns shares, tracks locked shares, and sends LZ message via OApp
     * @param options LayerZero messaging options
     */
    function claimOnTargetChain(bytes calldata options) external payable {
        require(selfClaimsEnabled, SelfClaimsDisabled());
        require(oapp != address(0), OAppNotSet());

        uint256 userShares = balanceOf(msg.sender);
        require(userShares != 0, NoSharesToClaim());

        // Burn shares and track locked
        _burn(msg.sender, userShares);
        lockedShares[msg.sender] += userShares;

        // Encode the message payload
        bytes memory payload = abi.encode(MSG_TYPE_CLAIM, msg.sender, userShares);

        // Send the message via the OApp (quote and fee validation done internally)
        IPredepostVaultOApp(oapp).send{value: msg.value}(payload, options, msg.sender);

        emit SharesClaimedOnTargetChain(msg.sender, userShares);
    }
}

