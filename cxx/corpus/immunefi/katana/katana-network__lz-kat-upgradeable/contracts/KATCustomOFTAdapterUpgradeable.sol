// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { KATOFTAdapterStorageLayout } from "./KATOFTAdapterStorageLayout.sol";
import { IKATVault } from "./interfaces/IKATVault.sol";
import { OFTAdapterUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTAdapterUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title KATCustomOFTAdapterUpgradeable
 * @notice Transparent proxy upgradeable OFT adapter using KATVault for transfers during lock period
 * @dev Works around locked transferFrom() by using vault.transferKat() with exempted transfer()
 */
contract KATCustomOFTAdapterUpgradeable is KATOFTAdapterStorageLayout, OFTAdapterUpgradeable, AccessControlUpgradeable {
    /// @notice Role identifier for users allowed to bridge tokens
    bytes32 public constant BRIDGE_USER = keccak256("BRIDGE_USER");

    /// @notice Emitted when a bridge user sends tokens cross-chain
    event BridgeInitiated(address indexed user, uint32 indexed dstEid, uint256 amount);

    /// @notice Emitted when the vault address is updated
    event VaultUpdated(address indexed oldVault, address indexed newVault);

    constructor(address _token, address _lzEndpoint) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        _disableInitializers();
    }

    /**
     * @param _delegate Delegate capable of making OApp configurations
     */
    function initialize(address _delegate) public initializer {
        __Ownable_init(_delegate);
        __AccessControl_init();
        __OFTAdapter_init(_delegate);

        _grantRole(DEFAULT_ADMIN_ROLE, _delegate);
    }

    /**
     * @notice Debit tokens using vault.transferKat() instead of transferFrom()
     * @dev Only BRIDGE_USER can initiate transfers
     * @param _amountLD Amount of tokens to send in local decimals
     * @param _minAmountLD Minimum amount to send in local decimals
     * @param _dstEid Destination chain ID
     */
    function _debit(
        address,
        /*_from*/
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    )
        internal
        virtual
        override
        onlyRole(BRIDGE_USER)
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        OftAdapterStorage storage $ = _getStorage();
        require(address($.vault) != address(0), "KATCustomOFTAdapter: vault not set");
        
        emit BridgeInitiated(msg.sender, _dstEid, _amountLD);
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        $.vault.transferKat(address(this), amountSentLD);
    }

    /**
     * @notice Grant the `BRIDGE_USER` role to `account`
     * @param account Address to give the `BRIDGE_USER` role to
     */
    function grantBridgeUser(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(BRIDGE_USER, account);
    }

    /**
     * @notice Revoke the `BRIDGE_USER` role from `account`
     * @param account Address to revoke the `BRIDGE_USER` role from
     */
    function revokeBridgeUser(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(BRIDGE_USER, account);
    }

    /**
     * @notice Update the vault address
     * @param _newVault New vault contract address
     */
    function setVault(address _newVault) external onlyOwner {
        OftAdapterStorage storage $ = _getStorage();
        require(_newVault != address(0), "KATCustomOFTAdapter: vault is zero address");
        address oldVault = address($.vault);
        $.vault = IKATVault(_newVault);
        emit VaultUpdated(oldVault, _newVault);
    }

    /// @notice Returns the address of the KAT vault.
    function getVault() external view returns (IKATVault) {
        return _getStorage().vault;
    }

    /**
     * @notice Wether or not a user has the `BRIDGE_USER` role.
     * @param account The address of the user
     */
    function isBridgeUser(address account) external view returns (bool) {
        return hasRole(BRIDGE_USER, account);
    }
}
