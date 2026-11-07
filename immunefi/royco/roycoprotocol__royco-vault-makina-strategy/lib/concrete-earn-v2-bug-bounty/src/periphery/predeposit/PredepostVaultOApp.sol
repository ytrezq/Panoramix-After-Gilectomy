// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {
    OAppUpgradeable,
    Origin,
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/oapp-evm-upgradeable/contracts/oapp/OAppUpgradeable.sol";
import {PredepostVaultOAppStorageLib as StorageLib} from "../lib/PredepostVaultOAppStorageLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title PredepostVaultOApp
 * @notice Standalone OApp contract for ConcretePredepositVaultImpl to send cross-chain messages
 * @dev Only the authorized vault can send messages through this OApp
 */
contract PredepostVaultOApp is OAppUpgradeable {
    // Message type identifiers for cross-chain claims
    uint16 public constant MSG_TYPE_CLAIM = 1;
    uint16 public constant MSG_TYPE_BATCH_CLAIM = 2;

    /// @notice Error thrown when caller is not the authorized vault
    error NotAuthorizedVault();

    /// @notice Error thrown when addresses array is empty
    error EmptyAddressesArray();

    /// @notice Error thrown when insufficient fee is provided
    error InsufficientFee(uint256 required, uint256 provided);

    /// @notice Emitted when vault address is set
    event VaultSet(address indexed vault);

    /// @notice Emitted when destination endpoint ID is set
    event DstEidSet(uint32 indexed dstEid);

    /**
     * @dev Constructor
     * @param lzEndpoint The address of the LayerZero endpoint
     */
    constructor(address lzEndpoint) OAppUpgradeable(lzEndpoint) {
        _disableInitializers();
    }

    /**
     * @notice Initialize the OApp
     * @param vaultAddress The address of the vault that will use this OApp
     * @param owner The owner/delegate of the OApp
     */
    function initialize(address vaultAddress, address owner) external initializer {
        require(vaultAddress != address(0), InvalidDelegate());

        StorageLib.PredepostVaultOAppStorage storage $ = StorageLib.fetch();
        $.vault = vaultAddress;

        __Ownable_init(owner);
        __OApp_init(owner);

        emit VaultSet(vaultAddress);
    }

    /**
     * @notice Returns the vault address
     * @return The address of the authorized vault
     */
    function vault() external view returns (address) {
        return StorageLib.fetch().vault;
    }

    /**
     * @notice Returns the destination endpoint ID
     * @return The destination endpoint ID
     */
    function dstEid() external view returns (uint32) {
        return StorageLib.fetch().dstEid;
    }

    /**
     * @notice Set the destination endpoint ID
     * @param _dstEid The destination endpoint ID
     * @dev Only callable by owner
     */
    function setDstEid(uint32 _dstEid) external onlyOwner {
        StorageLib.PredepostVaultOAppStorage storage $ = StorageLib.fetch();
        $.dstEid = _dstEid;
        emit DstEidSet(_dstEid);
    }

    /**
     * @notice Send a LayerZero message (only callable by vault)
     * @dev Quotes the fee internally and validates msg.value is sufficient
     * @dev Uses the stored dstEid
     * @param payload Message payload
     * @param options LayerZero options
     * @param refundAddress Address to refund excess fee
     */
    function send(bytes calldata payload, bytes calldata options, address refundAddress)
        external
        payable
        returns (MessagingReceipt memory receipt)
    {
        StorageLib.PredepostVaultOAppStorage storage $ = StorageLib.fetch();

        require(msg.sender == $.vault, NotAuthorizedVault());

        // Quote the fee internally using stored dstEid
        MessagingFee memory fee = _quote($.dstEid, payload, options, false);

        // Validate sufficient fee provided
        require(msg.value >= fee.nativeFee, InsufficientFee(fee.nativeFee, msg.value));

        return _lzSend($.dstEid, payload, options, MessagingFee(msg.value, 0), payable(refundAddress));
    }

    /**
     * @notice Quote the fee for sending a message (view function - no vault restriction)
     * @dev Uses the stored dstEid
     * @param payload Message payload
     * @param options LayerZero options
     * @param payInLzToken Whether to pay in LZ token
     * @return fee The estimated messaging fee
     */
    function quote(bytes calldata payload, bytes calldata options, bool payInLzToken)
        external
        view
        returns (MessagingFee memory fee)
    {
        StorageLib.PredepostVaultOAppStorage storage $ = StorageLib.fetch();
        return _quote($.dstEid, payload, options, payInLzToken);
    }

    /**
     * @notice Quote the fee for claiming shares on target chain
     * @param user The user address to claim for
     * @param options LayerZero messaging options
     * @param payInLzToken Whether to pay in LZ token
     * @return fee The estimated messaging fee
     */
    function quoteClaimOnTargetChain(address user, bytes calldata options, bool payInLzToken)
        external
        view
        returns (MessagingFee memory fee)
    {
        StorageLib.PredepostVaultOAppStorage storage $ = StorageLib.fetch();

        // Get user's current share balance from vault for size estimation
        uint256 userShares = IERC20($.vault).balanceOf(user);

        // Encode the message for fee estimation
        bytes memory payload = abi.encode(MSG_TYPE_CLAIM, user, userShares);

        return _quote($.dstEid, payload, options, payInLzToken);
    }

    /**
     * @notice Quote the fee for batch claiming shares on target chain
     * @param addressesData Encoded array of addresses to claim for
     * @param options LayerZero messaging options
     * @param payInLzToken Whether to pay in LZ token
     * @return fee The estimated messaging fee
     */
    function quoteBatchClaimOnTargetChain(bytes calldata addressesData, bytes calldata options, bool payInLzToken)
        external
        view
        returns (MessagingFee memory fee)
    {
        StorageLib.PredepostVaultOAppStorage storage $ = StorageLib.fetch();

        // Decode addresses array
        address[] memory addresses = abi.decode(addressesData, (address[]));
        require(addresses.length > 0, EmptyAddressesArray());

        // Build arrays for fee estimation
        uint256[] memory sharesArray = new uint256[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            sharesArray[i] = i; //actual value is not important for fee estimation
        }

        // Encode the message for fee estimation
        bytes memory payload = abi.encode(MSG_TYPE_BATCH_CLAIM, addresses, sharesArray);

        return _quote($.dstEid, payload, options, payInLzToken);
    }

    /**
     * @dev Internal function to handle incoming LayerZero messages
     * @dev This OApp only sends messages and does not expect to receive any
     */
    function _lzReceive(
        Origin calldata, /*_origin*/
        bytes32, /*_guid*/
        bytes calldata, /*_message*/
        address, /*_executor*/
        bytes calldata /*_extraData*/
    )
        internal
        virtual
        override
    {
        revert("PredepostVaultOApp: not expecting messages");
    }
}
