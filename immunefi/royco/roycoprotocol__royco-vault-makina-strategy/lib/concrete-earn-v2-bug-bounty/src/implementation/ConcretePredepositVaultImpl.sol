// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.24;

import {ConcreteStandardVaultImpl} from "./ConcreteStandardVaultImpl.sol";
import {IConcreteStandardVaultImpl} from "../interface/IConcreteStandardVaultImpl.sol";
import {IConcretePredepositVaultImpl} from "../interface/IConcretePredepositVaultImpl.sol";
import {
    ConcretePredepositVaultImplStorageLib as PDVLib
} from "../lib/storage/ConcretePredepositVaultImplStorageLib.sol";
import {ConcreteV2RolesLib as RolesLib} from "../lib/Roles.sol";
import {IPredepostVaultOApp} from "../periphery/interface/IPredepostVaultOApp.sol";
import {ConcreteV2ConversionLib as ConversionLib} from "../lib/Conversion.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";
import {
    ConcreteCachedVaultStateStorageLib as CachedVaultStateLib
} from "../lib/storage/ConcreteCachedVaultStateStorageLib.sol";

/**
 * @title ConcretePredepositVaultImpl
 * @notice A vault implementation that extends ConcreteStandardVaultImpl with cross-chain share claiming via a standalone OApp.
 * @dev This is useful for pre-deposit phases where users can claim their shares on a different chain.
 *      Withdrawals should be disabled during the predeposit phase.
 *      Claims can only occur when deposits and withdrawals are locked.
 *      Claims should only occur when underlying assets are bridged to target chain.
 *      Typically self claims should be enabled only when assets are already bridged to target chain.
 *      In claims phase shares are duplicated until claimed on target chain and burned on source chain.
 *      The vault uses a separate OApp contract for cross-chain messaging.
 *
 * @custom:warning IMPORTANT: Assets deposited into this vault are intended to be bridged to a remote chain.
 *                 Users MUST have custody/control of their address on the destination chain to receive shares.
 *                 Shares are sent to the same address on the remote chain - ensure you control this address
 *                 before depositing or claiming. Loss of custody on the destination chain means loss of funds.
 */
contract ConcretePredepositVaultImpl is ConcreteStandardVaultImpl, IConcretePredepositVaultImpl {
    using ConversionLib for uint256;

    // Message type identifier for cross-chain claims
    uint16 public constant MSG_TYPE_CLAIM = 1;
    uint16 public constant MSG_TYPE_BATCH_CLAIM = 2;

    /// @notice Event emitted when OApp address is set
    event OAppSet(address indexed oapp);

    /**
     * @dev Constructor
     * @param factory The address of the factory
     */
    constructor(address factory) ConcreteStandardVaultImpl(factory) {}

    /**
     * @dev Initialization function that will be called when a proxy vault is deployed through `ConcreteFactory`.
     * @param initialVersion The initial version of the vault
     * @param owner The owner of the vault
     * @param data Encoded initialization data (allocateModule, asset, initialVaultManager, name, symbol)
     */
    function _initialize(uint64 initialVersion, address owner, bytes memory data) internal virtual override {
        (
            address allocateModuleAddr,
            address asset,
            address initialVaultManager,
            string memory name,
            string memory symbol
        ) = abi.decode(data, (address, address, address, string, string));

        // Call parent initialization
        super._initialize(
            initialVersion, owner, abi.encode(allocateModuleAddr, asset, initialVaultManager, name, symbol)
        );

        // Initialize self claims setting to false (can be enabled via setSelfClaimsEnabled)
        PDVLib.ConcretePredepositVaultImplStorage storage $ = PDVLib.fetch();
        $.selfClaimsEnabled = false;
    }

    /// @inheritdoc IConcretePredepositVaultImpl
    function claimOnTargetChain(bytes calldata options) external payable nonReentrant withYieldAccrual {
        PDVLib.ConcretePredepositVaultImplStorage storage $ = PDVLib.fetch();

        // Ensure self claims are enabled
        require($.selfClaimsEnabled, SelfClaimsDisabled());

        _validateClaimConditions($);

        // Get user's current share balance
        uint256 userShares = balanceOf(msg.sender);
        require(userShares != 0, NoSharesToClaim());

        // decrease cached totalAssets proportionally to the user's shares to maintain the share price
        uint256 assets = userShares.calcConvertToAssets(totalSupply(), cachedTotalAssets(), Math.Rounding.Floor, false);
        CachedVaultStateLib.fetch().cachedTotalAssets = cachedTotalAssets() - assets;

        _burn(msg.sender, userShares);

        // Store locked shares
        $.lockedShares[msg.sender] += userShares;

        bytes memory payload = abi.encode(MSG_TYPE_CLAIM, msg.sender, userShares);

        // Send the message via the OApp (quote and fee validation done internally)
        IPredepostVaultOApp($.oapp).send{value: msg.value}(payload, options, msg.sender);

        emit SharesClaimedOnTargetChain(msg.sender, userShares);
    }

    /// @inheritdoc IConcretePredepositVaultImpl
    function batchClaimOnTargetChain(bytes calldata addressesData, bytes calldata options)
        external
        payable
        nonReentrant
        withYieldAccrual
        onlyRole(RolesLib.VAULT_MANAGER)
    {
        PDVLib.ConcretePredepositVaultImplStorage storage $ = PDVLib.fetch();

        _validateClaimConditions($);

        // Decode addresses array
        address[] memory addresses = abi.decode(addressesData, (address[]));
        require(addresses.length > 0 && addresses.length <= 150, BadAddressArrayLength(addresses.length));

        uint256[] memory sharesArray = new uint256[](addresses.length);
        uint256 totalShares = 0;

        for (uint256 i = 0; i < addresses.length; i++) {
            address user = addresses[i];
            require(user != address(0), InvalidUserAddress());

            uint256 userShares = balanceOf(user);
            if (userShares == 0) continue; // Skip users with no shares, already claimed, duplicates in list

            // decrease cached totalAssets proportionally to the user's shares to maintain the share price
            uint256 assets =
                userShares.calcConvertToAssets(totalSupply(), cachedTotalAssets(), Math.Rounding.Floor, false);
            CachedVaultStateLib.fetch().cachedTotalAssets = cachedTotalAssets() - assets;

            _burn(user, userShares);

            // Store locked shares
            $.lockedShares[user] += userShares;

            // Store in batch arrays
            sharesArray[i] = userShares;
            totalShares += userShares;

            emit SharesClaimedOnTargetChain(user, userShares);
        }

        require(totalShares > 0, NoSharesInBatch());

        bytes memory payload = abi.encode(MSG_TYPE_BATCH_CLAIM, addresses, sharesArray);

        // Send the message via the OApp (quote and fee validation done internally)
        IPredepostVaultOApp($.oapp).send{value: msg.value}(payload, options, msg.sender);
    }

    /// @inheritdoc IConcretePredepositVaultImpl
    function getLockedShares(address user) external view returns (uint256) {
        return PDVLib.fetch().lockedShares[user];
    }

    /// @inheritdoc IConcretePredepositVaultImpl
    function setSelfClaimsEnabled(bool enabled) external onlyRole(RolesLib.VAULT_MANAGER) {
        PDVLib.ConcretePredepositVaultImplStorage storage $ = PDVLib.fetch();
        $.selfClaimsEnabled = enabled;

        emit SelfClaimsEnabledUpdated(enabled);
    }

    /// @inheritdoc IConcretePredepositVaultImpl
    function getSelfClaimsEnabled() external view returns (bool) {
        return PDVLib.fetch().selfClaimsEnabled;
    }

    /// @inheritdoc IConcretePredepositVaultImpl
    function setOApp(address oappAddress) external onlyRole(RolesLib.VAULT_MANAGER) {
        PDVLib.ConcretePredepositVaultImplStorage storage $ = PDVLib.fetch();
        $.oapp = oappAddress;

        emit OAppSet(oappAddress);
    }

    /// @inheritdoc IConcretePredepositVaultImpl
    function getOApp() external view returns (address) {
        return PDVLib.fetch().oapp;
    }

    /**
     * @dev Upgrade function that handles migration from ConcreteStandardVaultImpl to ConcretePredepositVaultImpl
     * @dev Sets selfClaimsEnabled to false by default (can be enabled via setSelfClaimsEnabled)
     */
    function _upgrade(
        uint64,
        /* oldVersion */
        uint64,
        /* newVersion */
        bytes calldata /* data */
    )
        internal
        virtual
        override
    {
        // Initialize self claims setting to false (can be enabled via setSelfClaimsEnabled)
        PDVLib.ConcretePredepositVaultImplStorage storage $ = PDVLib.fetch();
        $.selfClaimsEnabled = false;
    }

    /**
     * @dev Internal function to validate claim conditions
     * @param $ Storage reference to ConcretePredepositVaultImplStorage
     */
    function _validateClaimConditions(PDVLib.ConcretePredepositVaultImplStorage storage $) internal view {
        // Ensure OApp is set
        require($.oapp != address(0), OAppNotSet());

        // Ensure deposits are locked
        (uint256 maxDepositAmount,) = getDepositLimits();
        require(maxDepositAmount == 0, DepositsNotLocked());

        // Ensure withdrawals are locked
        (uint256 maxWithdrawAmount,) = getWithdrawLimits();
        require(maxWithdrawAmount == 0, WithdrawalsNotLocked());
    }
}
