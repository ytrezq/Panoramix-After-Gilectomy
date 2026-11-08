// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ICDOComponent } from "./ICDOComponent.sol";
import { IMetaVault } from "./IMetaVault.sol";
import { IStrataCDO } from "./IStrataCDO.sol";

interface ITranche is ICDOComponent, IMetaVault {

    /// @dev Reverts when user-specified redemption parameters don't match current exit mode settings,
    ///      protecting against mode slippage before transaction execution
    struct TRedemptionParams {
        IStrataCDO.TExitMode exitMode;
        uint256 exitFee;
        uint32 cooldownSeconds;
    }

    error RedemptionParamsMismatch(TRedemptionParams requested, TRedemptionParams current);

    function configure () external;
    function burnSharesAsFee(uint256 shares, address owner) external returns (uint256);
}
