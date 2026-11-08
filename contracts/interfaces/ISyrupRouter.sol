// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface ISyrupRouter {

    /**
     *  @dev   Optional Deposit Data for off-chain processing.
     *  @param owner       The receiver of the shares.
     *  @param amount      The amount of assets to deposit.
     *  @param depositData Optional deposit data.
     */
    event DepositData(address indexed owner, uint256 amount, bytes32 depositData);

    /**
     *  @dev    The address of the underlying asset used by the ERC4626 Vault.
     *  @return asset The address of the underlying asset.
     */
    function asset() external view returns (address asset);

    /**
     *  @dev    Authorizes and deposits assets into the Vault.
     *  @param  bitmap_      The bitmap of the permission.
     *  @param  deadline_    The timestamp after which the `authorize` signature is no longer valid.
     *  @param  auth_v       ECDSA signature v component.
     *  @param  auth_r       ECDSA signature r component.
     *  @param  auth_s       ECDSA signature s component.
     *  @param  amount_      The amount of assets to deposit.
     *  @param  depositData_ Optional deposit data.
     *  @return shares_      The amount of shares minted.
     */
    function authorizeAndDeposit(
        uint256 bitmap_,
        uint256 deadline_,
        uint8   auth_v,
        bytes32 auth_r,
        bytes32 auth_s,
        uint256 amount_,
        bytes32 depositData_
    ) external returns (uint256 shares_);

    /**
     *  @dev    Authorizes and deposits assets into the Vault with a ERC-2612 `permit`.
     *  @param  bitmap_         The bitmap of the permission.
     *  @param  auth_deadline_  The timestamp after which the `authorize` signature is no longer valid.
     *  @param  auth_v          ECDSA signature v component of the authorization.
     *  @param  auth_r          ECDSA signature r component of the authorization.
     *  @param  auth_s          ECDSA signature s component of the authorization.
     *  @param  amount_         The amount of assets to deposit.
     *  @param  depositData_    Optional deposit data.
     *  @param  permit_deadline The timestamp after which the `permit` signature is no longer valid.
     *  @param  permit_v_       ECDSA signature v component of the token permit.
     *  @param  permit_r_       ECDSA signature r component of the token permit.
     *  @param  permit_s_       ECDSA signature s component of the token permit.
     *  @return shares_         The amount of shares minted.
     */
    function authorizeAndDepositWithPermit(
        uint256 bitmap_,
        uint256 auth_deadline_,
        uint8   auth_v,
        bytes32 auth_r,
        bytes32 auth_s,
        uint256 amount_,
        bytes32 depositData_,
        uint256 permit_deadline,
        uint8   permit_v_,
        bytes32 permit_r_,
        bytes32 permit_s_
    ) external returns (uint256 shares_);

    /**
     *  @dev    Mints `shares` to sender by depositing `assets` into the Vault.
     *  @param  assets      The amount of assets to deposit.
     *  @param  depositData Optional deposit data.
     *  @return shares      The amount of shares minted.
     */
    function deposit(uint256 assets, bytes32 depositData) external returns (uint256 shares);

    /**
     *  @dev    Does a ERC4626 `deposit` into a Maple Pool with a ERC-2612 `permit`.
     *  @param  amount     The amount of assets to deposit.
     *  @param  deadline   The timestamp after which the `permit` signature is no longer valid.
     *  @param  v          ECDSA signature v component.
     *  @param  r          ECDSA signature r component.
     *  @param  s          ECDSA signature s component.
     *  @param depositData Optional deposit data.
     *  @return shares     The amount of shares minted.
     */
    function depositWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s, bytes32 depositData)
        external returns (uint256 shares);

    /**
      *  @dev    Returns the nonce for the given owner.
      *  @param  owner_ The address of the owner account.
      *  @return nonce_ The nonce for the given owner.
     */
    function nonces(address owner_) external view returns (uint256 nonce_);

    /**
     *  @dev    The address of the ERC4626 Vault.
     *  @return pool The address of the ERC4626 Vault.
     */
    function pool() external view returns (address pool);

    /**
     *  @dev    The address of the Pool Manager.
     *  @return poolManager The address of the Pool Manager.
     */
    function poolManager() external view returns (address poolManager);

    /**
     *  @dev    The address of the Pool Permission Manager.
     *  @return poolPermissionManager The address of the Pool Permission Manager.
     */
    function poolPermissionManager() external view returns (address poolPermissionManager);

}

