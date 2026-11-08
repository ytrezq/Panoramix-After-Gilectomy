// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocUpgradable } from "../governance/MocUpgradable.sol";
import { MocMultiCollateralGuard } from "../multiCollateral/MocMultiCollateralGuard.sol";

/**
 * @title MocQueue Execution Fee: Handles Queuing execution fees
 */
abstract contract MocQueueExecFees is MocUpgradable {
    // Set of Deferrable Operation Types
    enum OperType {
        none, // avoid using zero as Type
        mintTC,
        redeemTC,
        mintTP,
        redeemTP,
        mintTCandTP,
        redeemTCandTP,
        swapTCforTP,
        swapTPforTC,
        swapTPforTP
    }

    // ------- Custom Errors -------

    // Wrong amount of coinbase set as execution fee
    error WrongExecutionFee(uint256 expectedValue);
    // Failure on Executor payment address coinbase transfer
    error ExecutionFeePaymentFailed();

    // ------- Structs -------

    struct InitializeMocQueueExecCostsParams {
        // absolute coinbase execution fee applied on Collateral Tokens mint
        uint256 tcMintExecCost;
        // absolute coinbase execution fee applied on Collateral Tokens redeem
        uint256 tcRedeemExecCost;
        // absolute coinbase execution fee applied on Pegged Tokens mint
        uint256 tpMintExecCost;
        // absolute coinbase execution fee applied on Pegged Tokens redeem
        uint256 tpRedeemExecCost;
        // absolute coinbase execution fee applied on swap a Pegged Token for another Pegged Token
        uint256 swapTPforTPExecCost;
        // absolute coinbase execution fee applied on swap a Pegged Token for Collateral Token
        uint256 swapTPforTCExecCost;
        // absolute coinbase execution fee applied on swap Collateral Token for a Pegged Token
        uint256 swapTCforTPExecCost;
        // absolute coinbase execution fee applied on redeem Collateral Token and Pegged Token in one operations
        uint256 redeemTCandTPExecCost;
        // absolute coinbase execution fee applied on mint Collateral Token and Pegged Token in one operation
        uint256 mintTCandTPExecCost;
    }

    // source for all buckets to determine the overall state of the multi-collateral system
    MocMultiCollateralGuard public mocMultiCollateralGuard;
    // OperType => Avg Execution cost per Operation
    mapping(OperType => uint256) public execCost;

    // ------- Initializer -------

    function __MocQueueExecFees_init(
        InitializeMocQueueExecCostsParams calldata mocQueueExecCostsParams_
    ) internal onlyInitializing {
        _setExecutionCosts(mocQueueExecCostsParams_);
    }

    // ------- Abstract Functions -------

    /**
     * @notice true if the queue is empty
     */
    function isEmpty() public view virtual returns (bool isEmpty);

    // ------- Internal Functions -------

    /**
     * @notice returns the network basefee
     */
    function _getBaseFee() internal view virtual returns (uint256) {
        return block.basefee;
    }

    /**
     * @notice sets Execution Fees absolute values for each operation type
     */
    function _setExecutionCosts(InitializeMocQueueExecCostsParams calldata mocQueueExecCostsParams_) internal {
        execCost[OperType.mintTC] = mocQueueExecCostsParams_.tcMintExecCost;
        execCost[OperType.redeemTC] = mocQueueExecCostsParams_.tcRedeemExecCost;
        execCost[OperType.mintTP] = mocQueueExecCostsParams_.tpMintExecCost;
        execCost[OperType.redeemTP] = mocQueueExecCostsParams_.tpRedeemExecCost;
        execCost[OperType.swapTPforTP] = mocQueueExecCostsParams_.swapTPforTPExecCost;
        execCost[OperType.swapTPforTC] = mocQueueExecCostsParams_.swapTPforTCExecCost;
        execCost[OperType.swapTCforTP] = mocQueueExecCostsParams_.swapTCforTPExecCost;
        execCost[OperType.redeemTCandTP] = mocQueueExecCostsParams_.redeemTCandTPExecCost;
        execCost[OperType.mintTCandTP] = mocQueueExecCostsParams_.mintTCandTPExecCost;
    }

    /**
     * @notice get execution fee for the operation requested
     * @dev only used for coinbase flavor
     * @param operType_ operation type registered
     * @return currentExecFee execution fee required for the operation
     */
    function getExecFee(OperType operType_) public view returns (uint256 currentExecFee) {
        unchecked {
            currentExecFee = execCost[operType_] * _getBaseFee();
        }
    }

    // ------- External Functions -------

    /**
     * @notice verifies that the execution fee for the operation is in range
     *  reverts if value sent is not enough to pay the execution fee or out of 10x range
     * @param operType_ operation type registered
     * @param execFee_ maximum execution fee the user is willing to accept
     */
    function verifyExecFeeRC20(OperType operType_, uint256 execFee_) external view {
        uint256 currentExecFee = getExecFee(operType_);
        if (currentExecFee > execFee_) revert WrongExecutionFee(currentExecFee);
        // If the value sent is 10x higher than network required, we assumed user error
        if (execFee_ > currentExecFee * 10) revert WrongExecutionFee(currentExecFee);
    }

    /**
     * @notice verifies that the execution fee for the operation is in range
     *  reverts if value sent is not enough to pay the execution fee
     * @param operType_ operation type registered
     * @param qACTotal_ maximum AC the user is willing to spend for the operation, including the execution fee
     * @return qACmax maximum AC the user is willing to spend for the operation, excluding the execution fee
     * @return currentExecFee execution fee for the given operation
     */
    function verifyExecFeeCoinbase(
        OperType operType_,
        uint256 qACTotal_
    ) external view returns (uint256 qACmax, uint256 currentExecFee) {
        currentExecFee = getExecFee(operType_);
        if (qACTotal_ < currentExecFee) revert WrongExecutionFee(currentExecFee);
        // for redeem operations, the coinbase overpaid is not used, so we need to revert if it is too high
        if (operType_ == OperType.redeemTC || operType_ == OperType.redeemTP || operType_ == OperType.redeemTCandTP) {
            // If the value sent is 10x higher than network required, we assumed user error
            if (qACTotal_ > currentExecFee * 10) revert WrongExecutionFee(currentExecFee);
            return (0, qACTotal_);
        }
        qACmax = qACTotal_ - currentExecFee;
    }

    // ------- Only Authorized Changer Functions -------

    /**
     * @notice Updates executions fees with absolute values for each operation type
     * @dev When the changer is executed there could be pending operations on the queue, thats means that
     *  users have already paid for those operations, so, two situations could occur:
     *  1. If execution fees are decreased, the executor will receive all the new fees and the
     *       remaining funds will stay in this contract
     *  2. If execution fees are increased, the executor will receive less fees, unless this contract has funds
     *       remaining from another execution fee update (1.) or previously sent by another address
     * @param mocQueueExecCostsParams_ new execution fees
     */
    function updateExecutionCosts(
        InitializeMocQueueExecCostsParams calldata mocQueueExecCostsParams_
    ) external onlyAuthorizedChanger {
        _setExecutionCosts(mocQueueExecCostsParams_);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
