// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IChangeContract } from "../../interfaces/IChangeContract.sol";
import { PeggedTokenParams } from "../../core/MocCore.sol";
import { MocOperations } from "../../core/MocOperations.sol";
import { MocMultiCollateralGuard } from "../../multiCollateral/MocMultiCollateralGuard.sol";
import { MocHelper } from "../../utils/MocHelper.sol";
import { MocRC20 } from "../../tokens/MocRC20.sol";

/**
 * @title AddPeggedTokenChangerTemplate
 * @notice This contract is a ChangeContract intended to be used with Moc Aeropulus
 * governance system. It allows the addition of a new Pegged Token to the system.
 * @dev This template only considers adding MocRC20, they are governed and use EnumerableAccessControl for roles.
    For any other type of Pegged Token it must be modified to achieve similar validations
 */
contract AddPeggedTokenChangerTemplate is IChangeContract, MocHelper {
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 private constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;

    error UnequalLength();
    error BucketDoesNotExist();
    error BucketParamDuplicated();
    error TPTotalSupplyNotZero();
    error InvalidRoles();
    error InvalidGovernor();

    // ------- Structs -------
    struct Params {
        MocOperations bucket;
        PeggedTokenParams peggedTokenParams;
    }

    // ------- Storage -------
    MocMultiCollateralGuard public immutable mocMultiCollateralGuard;
    MocRC20 public immutable peggedToken;
    Params[] internal paramsArray;

    /**
     * @notice Constructor
     * @param mocMultiCollateralGuard_ Address of the MocMultiCollateralGuard contract
     *  peggedToken_ Pegged Token to add
     *  paramsArray_ Array of all the buckets with its corresponding TP parameters
     */
    constructor(MocMultiCollateralGuard mocMultiCollateralGuard_, MocRC20 peggedToken_, Params[] memory paramsArray_) {
        mocMultiCollateralGuard = mocMultiCollateralGuard_;
        peggedToken = peggedToken_;
        paramsArray = paramsArray_;

        // validate changer conditions. Reverts if something is wrong
        validateChanger(mocMultiCollateralGuard_, peggedToken_, paramsArray_);
    }

    /**
     * @notice Returns the Pegged Token Params configurations that's going to be added
     */
    function getPeggedTokenParams(uint256 i_) external view returns (Params memory) {
        return paramsArray[i_];
    }

    /**
     * @notice Returns the Pegged Token Params configurations length
     */
    function getPeggedTokenParamsAmount() external view returns (uint256) {
        return paramsArray.length;
    }

    /**
     * @notice Execute the changes.
     * @dev Should be called by the governor, but this contract does not check that explicitly
     * because it is not its responsibility in the current architecture
     */
    function execute() external {
        // validate changer conditions. Reverts if something is wrong
        validateChanger(mocMultiCollateralGuard, peggedToken, paramsArray);

        for (uint256 i = 0; i < paramsArray.length; i++) {
            MocOperations bucket = paramsArray[i].bucket;
            bucket.addPeggedToken(peggedToken, paramsArray[i].peggedTokenParams);
            // Now the new Pegged Token will be minted and redeemed by all the buckets
            peggedToken.grantRole(BURNER_ROLE, address(bucket));
            peggedToken.grantRole(MINTER_ROLE, address(bucket));
        }
    }

    /**
     * @notice validate changer conditions. Reverts if something is wrong
     * @param mocMultiCollateralGuard_ Address of the MocMultiCollateralGuard contract
     *  peggedToken_ Pegged Token to add
     *  paramsArray_ Array of all the buckets with its corresponding TP parameters
     */
    function validateChanger(
        MocMultiCollateralGuard mocMultiCollateralGuard_,
        MocRC20 peggedToken_,
        Params[] memory paramsArray_
    ) public view {
        if (mocMultiCollateralGuard_.getBucketAmount() != paramsArray_.length) revert UnequalLength();
        if (mocMultiCollateralGuard_.governor() != peggedToken_.governor()) revert InvalidGovernor();
        if (peggedToken_.totalSupply() > 0) revert TPTotalSupplyNotZero();

        bool validMinterRole;
        bool validBurnerRole;
        bool validAdminRole;
        for (uint256 i = 0; i < paramsArray_.length; i++) {
            (, bool exists, ) = mocMultiCollateralGuard_.bucketIndex(paramsArray_[i].bucket);
            if (!exists) revert BucketDoesNotExist();

            // revert if a bucket is twice on the params array
            for (uint256 j = i + 1; j < paramsArray_.length; j++) {
                if (paramsArray_[i].bucket == paramsArray_[j].bucket) revert BucketParamDuplicated();
            }

            if (peggedToken.governor() != paramsArray_[i].bucket.governor()) revert InvalidGovernor();
            if (paramsArray_[i].peggedTokenParams.tpCtarg < ONE) revert InvalidValue();
            _checkLessThanOne(paramsArray_[i].peggedTokenParams.tpMintFee);
            _checkLessThanOne(paramsArray_[i].peggedTokenParams.tpRedeemFee);
            if (paramsArray_[i].peggedTokenParams.tpEmaSf >= ONE) revert InvalidValue();

            // true if any of the buckets has the TP roles
            validMinterRole = validMinterRole || peggedToken.hasRole(MINTER_ROLE, address(paramsArray_[i].bucket));
            validBurnerRole = validBurnerRole || peggedToken.hasRole(BURNER_ROLE, address(paramsArray_[i].bucket));
            validAdminRole = validAdminRole || peggedToken.hasRole(DEFAULT_ADMIN_ROLE, address(paramsArray_[i].bucket));
        }

        // true if only a bucket has Minter Role
        validMinterRole = validMinterRole && peggedToken.getRoleMemberCount(MINTER_ROLE) == 1;
        // true if only a bucket has Burner Role
        validBurnerRole = validBurnerRole && peggedToken.getRoleMemberCount(BURNER_ROLE) == 1;
        // true if only a bucket has Admin Role
        validAdminRole = validAdminRole && peggedToken.getRoleMemberCount(DEFAULT_ADMIN_ROLE) == 1;
        if ((!validMinterRole || !validBurnerRole || !validAdminRole)) revert InvalidRoles();
    }
}
