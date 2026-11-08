// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { ERC20Helper } from "../modules/erc20-helper/src/ERC20Helper.sol";

import { ISyrupRouter } from "./interfaces/ISyrupRouter.sol";

import {
    IERC20Like,
    IPoolLike,
    IPoolManagerLike,
    IPoolPermissionManagerLike
} from "./interfaces/Interfaces.sol";

/*

███████╗██╗   ██╗██████╗ ██╗   ██╗██████╗     ██████╗  ██████╗ ██╗   ██╗████████╗███████╗██████╗
██╔════╝╚██╗ ██╔╝██╔══██╗██║   ██║██╔══██╗    ██╔══██╗██╔═══██╗██║   ██║╚══██╔══╝██╔════╝██╔══██╗
███████╗ ╚████╔╝ ██████╔╝██║   ██║██████╔╝    ██████╔╝██║   ██║██║   ██║   ██║   █████╗  ██████╔╝
╚════██║  ╚██╔╝  ██╔══██╗██║   ██║██╔═══╝     ██╔══██╗██║   ██║██║   ██║   ██║   ██╔══╝  ██╔══██╗
███████║   ██║   ██║  ██║╚██████╔╝██║         ██║  ██║╚██████╔╝╚██████╔╝   ██║   ███████╗██║  ██║
╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝         ╚═╝  ╚═╝ ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝╚═╝  ╚═╝

*/

contract SyrupRouter is ISyrupRouter {

    address public immutable override asset;
    address public immutable override pool;
    address public immutable override poolManager;
    address public immutable override poolPermissionManager;

    mapping(address => uint256) public override nonces;

    constructor(address pool_) {
        pool = pool_;

        // Get the addresses of all the associated contracts.
        address asset_ = asset = IPoolLike(pool_).asset();
        address poolManager_ = poolManager = IPoolLike(pool_).manager();

        poolPermissionManager = IPoolManagerLike(poolManager_).poolPermissionManager();

        // Perform an infinite approval.
        require(ERC20Helper.approve(asset_, pool_, type(uint256).max), "SR:C:APPROVE_FAIL");
    }

    /**************************************************************************************************************************************/
    /*** External Functions                                                                                                             ***/
    /**************************************************************************************************************************************/

    function authorizeAndDeposit(
        uint256 bitmap_,
        uint256 deadline_,
        uint8   auth_v,
        bytes32 auth_r,
        bytes32 auth_s,
        uint256 amount_,
        bytes32 depositData_
    )
        external override returns (uint256 shares_)
    {
        _authorize(deadline_, bitmap_, auth_v, auth_r, auth_s);

        shares_ = _deposit(msg.sender, amount_, depositData_);
    }

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
    )
        external override returns (uint256 shares_)
    {
        _authorize(auth_deadline_, bitmap_, auth_v, auth_r, auth_s);
        _permit(asset, permit_deadline, amount_, permit_v_, permit_r_, permit_s_);

        shares_ = _deposit(msg.sender, amount_, depositData_);
    }

    function deposit(uint256 amount_, bytes32 depositData_) external override returns (uint256 shares_) {
        shares_ = _deposit(msg.sender, amount_, depositData_);
    }

    function depositWithPermit(
        uint256 amount_,
        uint256 deadline_,
        uint8   v_,
        bytes32 r_,
        bytes32 s_,
        bytes32 depositData_
    )
        external override returns (uint256 shares_)
    {
        _permit(asset, deadline_, amount_, v_, r_, s_);

        shares_ = _deposit(msg.sender, amount_, depositData_);
    }

    /**************************************************************************************************************************************/
    /*** Internal Functions                                                                                                             ***/
    /**************************************************************************************************************************************/

    function _authorize(uint256 deadline_, uint256 bitmap_, uint8 v_, bytes32 r_, bytes32 s_) internal {
        require(deadline_ >= block.timestamp, "SR:A:EXPIRED");

        // Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}.
        require(
            uint256(s_) <= uint256(0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) &&
            (v_ == 27 || v_ == 28),
            "SR:A:MALLEABLE"
        );

        bytes32 digest_ = keccak256(abi.encodePacked(
            "\x19\x01",
            block.chainid,  // Chain id + address(this) serves as domain separator to avoid replay attacks.
            address(this),
            msg.sender,
            nonces[msg.sender]++,
            bitmap_,
            deadline_
        ));

        address recoveredAddress_ = ecrecover(digest_, v_, r_, s_);

        IPoolPermissionManagerLike ppm_ = IPoolPermissionManagerLike(poolPermissionManager);

        // Any valid permission admin can authorize the deposit.
        require(recoveredAddress_ != address(0) && ppm_.permissionAdmins(recoveredAddress_), "SR:A:NOT_PERMISSION_ADMIN");

        address[] memory lender = new address[](1);
        uint256[] memory bitmap = new uint256[](1);

        lender[0] = msg.sender;
        bitmap[0] = bitmap_;

        ppm_.setLenderBitmaps(lender, bitmap);
    }

    function _deposit(address owner_, uint256 amount_, bytes32 depositData_) internal returns (uint256 shares_) {
        // Check the owner has permission to deposit into the pool.
        require(
            IPoolPermissionManagerLike(poolPermissionManager).hasPermission(poolManager, owner_, "P:deposit"),
            "SR:D:NOT_AUTHORIZED"
        );

        // Pull assets from the owner to the router.
        require(ERC20Helper.transferFrom(asset, owner_, address(this), amount_), "SR:D:TRANSFER_FROM_FAIL");

        // Deposit assets into the pool and receive the shares personally.
        address pool_ = pool;

        shares_ = IPoolLike(pool_).deposit(amount_, address(this));

        // Route shares back to the caller.
        require(ERC20Helper.transfer(pool_, owner_, shares_), "SR:D:TRANSFER_FAIL");

        emit DepositData(owner_, amount_, depositData_);
    }

    function _permit(address asset_, uint256 deadline_, uint256 amount_, uint8 v_, bytes32 r_, bytes32 s_) internal {
        uint256 allowance_ = IERC20Like(asset_).allowance(msg.sender, address(this));

        if (allowance_ < amount_) {
            IERC20Like(asset_).permit(msg.sender, address(this), amount_, deadline_, v_, r_, s_);
        }
    }

}
