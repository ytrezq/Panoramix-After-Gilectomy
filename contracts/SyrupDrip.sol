// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ERC20Helper } from "../modules/erc20-helper/src/ERC20Helper.sol";
import { MerkleProof } from "../modules/open-zeppelin/contracts/utils/cryptography/MerkleProof.sol";

import { IGlobalsLike, IStakedSyrupLike } from "./interfaces/Interfaces.sol";
import { ISyrupDrip }                     from "./interfaces/ISyrupDrip.sol";

contract SyrupDrip is ISyrupDrip {

    /**************************************************************************************************************************************/
    /*** State Variables                                                                                                                ***/
    /**************************************************************************************************************************************/

    address public immutable override asset;
    address public immutable override globals;
    address public immutable override stakedSyrup;

    bytes32 public override root;

    uint256 public override deadline;
    uint256 public override maxId;

    mapping(uint256 => uint256) public override bitmaps;

    /**************************************************************************************************************************************/
    /*** Constructor                                                                                                                    ***/
    /**************************************************************************************************************************************/

    constructor(address asset_, address globals_, address stakedSyrup_) {
        asset       = asset_;
        globals     = globals_;
        stakedSyrup = stakedSyrup_;

        // Approve the staked syrup contract to transfer the asset.
        require(ERC20Helper.approve(asset_, stakedSyrup_, type(uint256).max), "SD:C:APPROVAL_FAILED");
    }

    /**************************************************************************************************************************************/
    /*** Modifiers                                                                                                                      ***/
    /**************************************************************************************************************************************/

    modifier onlyProtocolAdmins {
        address globals_ = globals;

        require(
            msg.sender == IGlobalsLike(globals_).governor() ||
            msg.sender == IGlobalsLike(globals_).operationalAdmin(),
            "SD:NOT_AUTHORIZED"
        );

        _;
    }

    /**************************************************************************************************************************************/
    /*** External Functions                                                                                                             ***/
    /**************************************************************************************************************************************/

    function allocate(bytes32 root_, uint256 deadline_, uint256 maxId_) external override onlyProtocolAdmins {
        require(deadline_ >= block.timestamp, "SD:A:INVALID_DEADLINE");
        require(maxId_ >= maxId,              "SD:A:INVALID_MAX_ID");

        root     = root_;
        deadline = deadline_;
        maxId    = maxId_;

        emit Allocated(root_, deadline_, maxId_);
    }

    function claim(uint256 id_, address owner_, uint256 claimAmount_, bytes32[] calldata proof_) external override {
        _claim(id_, owner_, claimAmount_, claimAmount_, proof_);
    }

    function claimAndStake(
        uint256   id_,
        address   owner_,
        uint256   claimAmount_,
        uint256   stakeAmount_,
        bytes32[] calldata proof_
    )
        external override
    {
        require(stakeAmount_ > 0,             "SD:CAS:ZERO_STAKE_AMOUNT");
        require(stakeAmount_ <= claimAmount_, "SD:CAS:INVALID_STAKE_AMOUNT");

        _claim(id_, owner_, claimAmount_, claimAmount_ - stakeAmount_, proof_);

        uint256 shares_ = IStakedSyrupLike(stakedSyrup).deposit(stakeAmount_, owner_);

        emit Staked(id_, owner_, stakeAmount_, shares_);
    }

    function reclaim(address to_, uint256 amount_) external override onlyProtocolAdmins {
        require(amount_ != 0,                              "SD:R:ZERO_AMOUNT");
        require(ERC20Helper.transfer(asset, to_, amount_), "SD:R:TRANSFER_FAIL");

        emit Reclaimed(to_, amount_);
    }

    /**************************************************************************************************************************************/
    /*** View Functions                                                                                                                 ***/
    /**************************************************************************************************************************************/

    // Checks if a token allocation has already been claimed.
    function isClaimed(uint256 id_) public view returns (bool isClaimed_) {
        uint256 key_  = id_ / 256;
        uint256 flag_ = id_ % 256;
        uint256 word_ = bitmaps[key_];
        uint256 mask_ = (1 << flag_);

        isClaimed_ = word_ & mask_ == mask_;
    }

    /**************************************************************************************************************************************/
    /*** Internal Functions                                                                                                             ***/
    /**************************************************************************************************************************************/

    function _claim(
        uint256   id_,
        address   owner_,
        uint256   claimAmount_,
        uint256   transferAmount_,
        bytes32[] calldata proof_
    )
        internal
    {
        require(!isClaimed(id_),             "SD:C:ALREADY_CLAIMED");
        require(block.timestamp <= deadline, "SD:C:EXPIRED_DEADLINE");

        bytes32 leaf_ = keccak256(bytes.concat(keccak256(abi.encode(id_, owner_, claimAmount_))));

        require(MerkleProof.verify(proof_, root, leaf_), "SD:C:INVALID_PROOF");

        _setClaimed(id_);

        if (transferAmount_ > 0) {
            require(ERC20Helper.transfer(asset, owner_, transferAmount_), "SD:C:TRANSFER_FAIL");
        }

        emit Claimed(id_, owner_, claimAmount_);
    }

    // Registers a token allocation as claimed.
    function _setClaimed(uint256 id_) internal {
        uint256 key_  = id_ / 256;
        uint256 flag_ = id_ % 256;

        bitmaps[key_] = bitmaps[key_] | (1 << flag_);
    }

}
