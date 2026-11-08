// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IChangeContract } from "../../interfaces/IChangeContract.sol";
import { IMocRC20 } from "../../interfaces/IMocRC20.sol";
import { MocCore, PeggedTokenParams } from "../../core/MocCore.sol";
import { MocHelper } from "../../utils/MocHelper.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
  @title EditPeggedTokenChangerTemplate
  @notice This contract is a ChangeContract intended to be used with Moc Aeropulus 
  governance system. It allows the edition of an existent Pegged Token to the system.

  @dev IMPORTANT: This template provides a basic framework for Pegged Token params editions,
  but it's not intended to be use out of the box. Depending on the combination of params
  you need to edit, you'll need to generate new methods, disable others and adjust the 
  `PARAMS_CHANGED` config. In this example, only the priceProvider address is used as showcase.
  Also please notice that params values, are not verify on the target contract, so it's desirable
  that the changer itself do it. See `AditPeggedTokenChangerTemplate.sol` for reference.
 */
contract EditPeggedTokenChangerTemplate is IChangeContract, MocHelper, Ownable {
    error InvalidParamSetCount();

    // ------- Storage -------

    MocCore public immutable mocCore;
    IMocRC20 public immutable tpToEdit;
    PeggedTokenParams internal peggedTokenParams;
    uint256 public paramSet;
    uint256 private constant PARAMS_CHANGED = 1;

    /**
     * @notice Constructor
     * @param mocCore_ Address of the contract to edit the Pegged Token on
     * @param tpToEdit_ Pegged Token Address to edit, needs to belong to `mocCore_`
     */
    constructor(MocCore mocCore_, IMocRC20 tpToEdit_) {
        mocCore = mocCore_;
        tpToEdit = tpToEdit_;

        (, bool exists) = mocCore.peggedTokenIndex(address(tpToEdit));
        if (!exists) revert InvalidAddress();
    }

    /**
     * @notice contract initializer
     * @param priceProvider_  new pegged token price provider
     */
    function setPriceProvider(address priceProvider_) external onlyOwner {
        if (paramSet != 0) revert InvalidParamSetCount();
        // Increase param set to allow execution
        paramSet++;
        // Fetched the pegged Token index by token address
        (uint256 i, ) = mocCore.peggedTokenIndex(address(tpToEdit));
        // Fetched all values for the given index
        (, uint256 emaSf) = mocCore.tpEma(i);

        // Only edits the priceProvider, all the other values are taken from the contracts itself
        peggedTokenParams = PeggedTokenParams(
            // priceProviderAddress
            priceProvider_,
            // Pegged Token target coverage [PREC]
            mocCore.tpCtarg(i),
            // additional fee pct applied on mint [PREC]
            mocCore.tpMintFees(address(tpToEdit)),
            // additional fee pct applied on redeem [PREC]
            mocCore.tpRedeemFees(address(tpToEdit)),
            // Emma is not editable, only initialized
            0,
            // Pegged Token smoothing factor [PREC]
            emaSf
        );
    }

    /**
     * @notice Returns the Pegged Token Params configurations that's going to be edited
     */
    function getPeggedTokenParams() external view returns (PeggedTokenParams memory) {
        return peggedTokenParams;
    }

    /**
     * @notice Execute the changes.
     * @dev Should be called by the governor, but this contract does not check that explicitly
     * because it is not its responsibility in the current architecture
     */
    function execute() external {
        if (paramSet != PARAMS_CHANGED) revert InvalidParamSetCount();
        mocCore.editPeggedToken(tpToEdit, peggedTokenParams);
        // Blocks re-execution
        paramSet++;
    }
}
