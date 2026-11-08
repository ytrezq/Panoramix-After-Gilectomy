// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocQueueBasefeeMock } from "./MocQueueBasefeeMock.sol";
import { MocCore, MocOperations } from "../queue/MocQueue.sol";
import { UpgradableMock } from "./upgradeability/MocUpgradeMocks.sol";

/**
 * @title MocQueueMock: Allows Deferral execution without error handling
 * @dev Intended to allow Deferral testing using behaviors, including error tests
 */
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract MocQueueMock is MocQueueBasefeeMock, UpgradableMock {
    function _executeMintTC(MocOperations bucket_, uint256 operId_) internal override {
        MocCore.MintTCParams memory params = operationsMintTC[operId_];
        (uint256 _qACtotalNeeded, , MocCore.FeeCalcs memory _feeCalcs) = bucket_.execMintTC(params);
        _onDeferredTCMinted(operId_, params, _qACtotalNeeded, _feeCalcs);
    }

    function _executeRedeemTC(MocOperations bucket_, uint256 operId_) internal override {
        MocCore.RedeemTCParams memory params = operationsRedeemTC[operId_];
        (uint256 _qACRedeemed, , MocCore.FeeCalcs memory _feeCalcs) = bucket_.execRedeemTC(params);
        _onDeferredTCRedeemed(operId_, params, _qACRedeemed, _feeCalcs);
    }

    function _executeMintTP(MocOperations bucket_, uint256 operId_) internal override {
        MocCore.MintTPParams memory params = operationsMintTP[operId_];
        (uint256 _qACtotalNeeded, , MocCore.FeeCalcs memory _feeCalcs) = bucket_.execMintTP(params);
        _onDeferredTPMinted(operId_, params, _qACtotalNeeded, _feeCalcs);
    }

    function _executeRedeemTP(MocOperations bucket_, uint256 operId_) internal override {
        MocCore.RedeemTPParams memory params = operationsRedeemTP[operId_];
        (uint256 _qACRedeemed, , MocCore.FeeCalcs memory _feeCalcs) = bucket_.execRedeemTP(params);
        _onDeferredTPRedeemed(operId_, params, _qACRedeemed, _feeCalcs);
    }

    function _executeMintTCandTP(MocOperations bucket_, uint256 operId_) internal override {
        MocCore.MintTCandTPParams memory params = operationsMintTCandTP[operId_];
        (
            uint256 _qACtoMintTC,
            uint256 _qACtoMintTP,
            uint256 _qACtoSpent,
            uint256 _qTCMinted,
            ,
            MocCore.FeeCalcs memory _feeCalcs
        ) = bucket_.execMintTCandTP(params);
        _onDeferredTCandTPMinted(operId_, params, _qTCMinted, _qACtoMintTC, _qACtoMintTP, _qACtoSpent, _feeCalcs);
    }

    function _executeRedeemTCandTP(MocOperations bucket_, uint256 operId_) internal override {
        MocCore.RedeemTCandTPParams memory params = operationsRedeemTCandTP[operId_];
        (
            uint256 _qACtoRedeemTC,
            uint256 _qACtoRedeemTP,
            uint256 _qACtoReceive,
            uint256 _qTPRedeemed,
            ,
            MocCore.FeeCalcs memory _feeCalcs
        ) = bucket_.execRedeemTCandTP(params);
        _onDeferredTCandTPRedeemed(
            operId_,
            params,
            _qTPRedeemed,
            _qACtoRedeemTC,
            _qACtoRedeemTP,
            _qACtoReceive,
            _feeCalcs
        );
    }

    function _executeSwapTCforTP(MocOperations bucket_, uint256 operId_) internal override {
        MocCore.SwapTCforTPParams memory params = operationsSwapTCforTP[operId_];
        (, uint256 qTPMinted, , MocCore.FeeCalcs memory _feeCalcs) = bucket_.execSwapTCforTP(params);
        _onDeferredTCforTPSwapped(operId_, params, qTPMinted, _feeCalcs);
    }

    function _executeSwapTPforTC(MocOperations bucket_, uint256 operId_) internal override {
        MocCore.SwapTPforTCParams memory params = operationsSwapTPforTC[operId_];
        (, uint256 qTCMinted, , MocCore.FeeCalcs memory _feeCalcs) = bucket_.execSwapTPforTC(params);
        _onDeferredTPforTCSwapped(operId_, params, qTCMinted, _feeCalcs);
    }

    function _executeSwapTPforTP(MocOperations bucket_, uint256 operId_) internal override {
        MocCore.SwapTPforTPParams memory params = operationsSwapTPforTP[operId_];
        (, uint256 qTPMinted, , MocCore.FeeCalcs memory _feeCalcs) = bucket_.execSwapTPforTP(params);
        _onDeferredTPforTPSwapped(operId_, params, qTPMinted, _feeCalcs);
    }

    function getCustomMockValue() external view override returns (uint256) {
        return newVariable + execCost[OperType.mintTC];
    }
}
