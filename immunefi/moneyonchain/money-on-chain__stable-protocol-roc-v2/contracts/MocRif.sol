// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocCARC20 } from "moc-main-latest/contracts/collateral/rc20/MocCARC20.sol";

/**
  @title MocRif
  @notice A mocCore implementation using RIF as Collateral 
 */
contract MocRif is MocCARC20 {
    /**
     * @notice One time only specific function to migrate block numbers to timestamps
     * @param nextEmaCalculation_ The next time the EMA will be calculated
     * @param nextTCInterestPayment_ The next time the TC interest will be paid
     * @param nextSettlementTime_ The next time the settlement will be performed
     * @param lastOperationTimeStamp_ The last time the operation was performed
     */
    function migrateTimestamps(
        uint256 nextEmaCalculation_,
        uint256 nextTCInterestPayment_,
        uint256 nextSettlementTime_,
        uint256 lastOperationTimeStamp_
    ) external onlyAuthorizedChanger {
        nextEmaCalculation = nextEmaCalculation_;
        nextTCInterestPayment = nextTCInterestPayment_;
        nextSettlementTime = nextSettlementTime_;
        lastOperationTimeStamp = lastOperationTimeStamp_;
    }
}
