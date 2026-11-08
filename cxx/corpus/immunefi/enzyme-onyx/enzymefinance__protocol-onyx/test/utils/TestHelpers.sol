// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {PolicyEngine} from "@chainlink/policy-management/core/PolicyEngine.sol";
import {PolicyEngineFactory} from "@chainlink/policy-management/core/PolicyEngineFactory.sol";

import {
    ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator.sol";
import {
    ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator.sol";
import {
    ChainlinkAceSyncDepositHandlerPostDepositValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceSyncDepositHandlerPostDepositValidator.sol";
import {
    ChainlinkAceSyncRedeemHandlerPostRedeemValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceSyncRedeemHandlerPostRedeemValidator.sol";
import {
    ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidator.sol";
import {
    ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator.sol";
import {
    ChainlinkAceSharesMintHandlerPreMintValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceSharesMintHandlerPreMintValidator.sol";
import {
    ChainlinkAceSharesBurnHandlerPreBurnValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceSharesBurnHandlerPreBurnValidator.sol";
import {
    ChainlinkAceIssuanceValidatorBase
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceIssuanceValidatorBase.sol";
import {
    ChainlinkAceSharesTransferValidator
} from "src/components/shares-transfer-validators/ChainlinkAceSharesTransferValidator.sol";
import {ComponentBeaconFactory} from "src/factories/ComponentBeaconFactory.sol";
import {Global} from "src/global/Global.sol";
import {IFeeHandler} from "src/interfaces/IFeeHandler.sol";
import {IPositionTracker} from "src/components/value/position-trackers/IPositionTracker.sol";
import {IValuationHandler} from "src/interfaces/IValuationHandler.sol";
import {IAddressList} from "src/infra/lists/address-list/IAddressList.sol";
import {Shares} from "src/shares/Shares.sol";

import {BlankFeeHandler, BlankPositionTracker} from "test/mocks/Blanks.sol";

import {Constants} from "test/utils/Constants.sol";

contract TestHelpers is Constants, Test {
    // OZ Initializable storage location (erc7201:openzeppelin.storage.Initializable)
    bytes32 internal constant INITIALIZABLE_STORAGE_LOCATION =
        0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    /// @dev Re-enables initializers on a directly-deployed implementation, whose constructor
    /// calls `_disableInitializers()`. Tests init such contracts directly rather than via a proxy.
    function reenableInitializers(address _contract) internal {
        vm.store(_contract, INITIALIZABLE_STORAGE_LOCATION, bytes32(0));
    }

    function createShares() internal returns (Shares shares_) {
        address owner = makeAddr("owner");
        string memory name = "Test Shares";
        string memory symbol = "TST";
        bytes32 valueAsset = keccak256("USD");

        shares_ = new Shares();
        reenableInitializers(address(shares_));
        shares_.init({_owner: owner, _name: name, _symbol: symbol, _valueAsset: valueAsset});
    }

    function deployPolicyEngine(bool _defaultAllow) internal returns (address engine_) {
        return deployPolicyEngine(_defaultAllow, bytes32(0));
    }

    function deployPolicyEngine(bool _defaultAllow, bytes32 _uniqueId) internal returns (address engine_) {
        address implementation = address(new PolicyEngine());
        PolicyEngineFactory factory = new PolicyEngineFactory();
        engine_ = factory.createPolicyEngine({
            implementation: implementation,
            uniqueEngineId: _uniqueId,
            policyEngineDefaultAllow: _defaultAllow,
            initialOwner: makeAddr("policyEngineOwner")
        });
    }

    function deployChainlinkAceSharesTransferValidator(address _shares, address _policyEngine)
        internal
        returns (address validator_)
    {
        Global global = new Global();
        global.init({_owner: address(this)});

        ComponentBeaconFactory factory = new ComponentBeaconFactory(address(global));
        factory.setImplementation(address(new ChainlinkAceSharesTransferValidator()));

        validator_ = factory.deployProxy({
            _shares: _shares, _initData: abi.encodeCall(ChainlinkAceSharesTransferValidator.init, (_policyEngine))
        });
    }

    function deployChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator(
        address _shares,
        address _handler,
        address _policyEngine
    ) internal returns (address validator_) {
        return __deployChainlinkAceIssuanceValidator({
            _implementation: address(new ChainlinkAceERC7540LikeDepositQueuePreRequestDepositValidator()),
            _shares: _shares,
            _handler: _handler,
            _policyEngine: _policyEngine
        });
    }

    function deployChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator(
        address _shares,
        address _handler,
        address _policyEngine
    ) internal returns (address validator_) {
        return __deployChainlinkAceIssuanceValidator({
            _implementation: address(new ChainlinkAceERC7540LikeRedeemQueuePreRequestRedeemValidator()),
            _shares: _shares,
            _handler: _handler,
            _policyEngine: _policyEngine
        });
    }

    function deployChainlinkAceSyncDepositHandlerPostDepositValidator(
        address _shares,
        address _handler,
        address _policyEngine
    ) internal returns (address validator_) {
        return __deployChainlinkAceIssuanceValidator({
            _implementation: address(new ChainlinkAceSyncDepositHandlerPostDepositValidator()),
            _shares: _shares,
            _handler: _handler,
            _policyEngine: _policyEngine
        });
    }

    function deployChainlinkAceSyncRedeemHandlerPostRedeemValidator(
        address _shares,
        address _handler,
        address _policyEngine
    ) internal returns (address validator_) {
        return __deployChainlinkAceIssuanceValidator({
            _implementation: address(new ChainlinkAceSyncRedeemHandlerPostRedeemValidator()),
            _shares: _shares,
            _handler: _handler,
            _policyEngine: _policyEngine
        });
    }

    function deployChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidator(
        address _shares,
        address _handler,
        address _policyEngine
    ) internal returns (address validator_) {
        return __deployChainlinkAceIssuanceValidator({
            _implementation: address(new ChainlinkAceERC7540LikeDepositQueuePostExecuteDepositRequestValidator()),
            _shares: _shares,
            _handler: _handler,
            _policyEngine: _policyEngine
        });
    }

    function deployChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator(
        address _shares,
        address _handler,
        address _policyEngine
    ) internal returns (address validator_) {
        return __deployChainlinkAceIssuanceValidator({
            _implementation: address(new ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator()),
            _shares: _shares,
            _handler: _handler,
            _policyEngine: _policyEngine
        });
    }

    function deployChainlinkAceSharesMintHandlerPreMintValidator(
        address _shares,
        address _handler,
        address _policyEngine
    ) internal returns (address validator_) {
        return __deployChainlinkAceIssuanceValidator({
            _implementation: address(new ChainlinkAceSharesMintHandlerPreMintValidator()),
            _shares: _shares,
            _handler: _handler,
            _policyEngine: _policyEngine
        });
    }

    function deployChainlinkAceSharesBurnHandlerPreBurnValidator(
        address _shares,
        address _handler,
        address _policyEngine
    ) internal returns (address validator_) {
        return __deployChainlinkAceIssuanceValidator({
            _implementation: address(new ChainlinkAceSharesBurnHandlerPreBurnValidator()),
            _shares: _shares,
            _handler: _handler,
            _policyEngine: _policyEngine
        });
    }

    function __deployChainlinkAceIssuanceValidator(
        address _implementation,
        address _shares,
        address _handler,
        address _policyEngine
    ) private returns (address validator_) {
        Global global = new Global();
        global.init({_owner: address(this)});

        ComponentBeaconFactory factory = new ComponentBeaconFactory(address(global));
        factory.setImplementation(_implementation);

        validator_ = factory.deployProxy({
            _shares: _shares,
            _initData: abi.encodeCall(ChainlinkAceIssuanceValidatorBase.init, (_handler, _policyEngine))
        });
    }

    // MOCKS: FUNCTION CALLS

    function addressList_mockIsInList(address _addressList, address _item, bool _isInList) internal {
        vm.mockCall(_addressList, abi.encodeWithSelector(IAddressList.isInList.selector, _item), abi.encode(_isInList));
    }

    function feeHandler_mockGetTotalValueOwed(address _feeHandler, uint256 _totalValueOwed) internal {
        vm.mockCall(_feeHandler, IFeeHandler.getTotalValueOwed.selector, abi.encode(_totalValueOwed));
    }

    function feeHandler_mockSettleEntranceFeeGivenGrossShares(address _feeHandler, uint256 _feeSharesAmount) internal {
        vm.mockCall(_feeHandler, IFeeHandler.settleEntranceFeeGivenGrossShares.selector, abi.encode(_feeSharesAmount));
    }

    function feeHandler_mockSettleEntranceFeeGivenGrossShares(
        address _feeHandler,
        uint256 _feeSharesAmount,
        uint256 _grossSharesAmount
    ) internal {
        vm.mockCall(
            _feeHandler,
            abi.encodeWithSelector(IFeeHandler.settleEntranceFeeGivenGrossShares.selector, _grossSharesAmount),
            abi.encode(_feeSharesAmount)
        );
    }

    function feeHandler_mockSettleExitFeeGivenGrossShares(address _feeHandler, uint256 _feeSharesAmount) internal {
        vm.mockCall(_feeHandler, IFeeHandler.settleExitFeeGivenGrossShares.selector, abi.encode(_feeSharesAmount));
    }

    function feeHandler_mockSettleExitFeeGivenGrossShares(
        address _feeHandler,
        uint256 _feeSharesAmount,
        uint256 _grossSharesAmount
    ) internal {
        vm.mockCall(
            _feeHandler,
            abi.encodeWithSelector(IFeeHandler.settleExitFeeGivenGrossShares.selector, _grossSharesAmount),
            abi.encode(_feeSharesAmount)
        );
    }

    function positionTracker_mockGetPositionValue(address _positionTracker, int256 _value) internal {
        vm.mockCall(_positionTracker, IPositionTracker.getPositionValue.selector, abi.encode(_value));
    }

    function valuationHandler_mockGetDefaultSharePrice(address _valuationHandler, uint256 _defaultSharePrice) internal {
        vm.mockCall(_valuationHandler, IValuationHandler.getDefaultSharePrice.selector, abi.encode(_defaultSharePrice));
    }

    function valuationHandler_mockGetSharePrice(address _valuationHandler, uint256 _sharePrice, uint256 _timestamp)
        internal
    {
        vm.mockCall(_valuationHandler, IValuationHandler.getSharePrice.selector, abi.encode(_sharePrice, _timestamp));
    }

    function valuationHandler_mockGetShareValue(address _valuationHandler, uint256 _shareValue, uint256 _timestamp)
        internal
    {
        vm.mockCall(_valuationHandler, IValuationHandler.getShareValue.selector, abi.encode(_shareValue, _timestamp));
    }

    function shares_mockSharePrice(address _shares, uint256 _sharePrice, uint256 _timestamp) internal {
        vm.mockCall(_shares, Shares.sharePrice.selector, abi.encode(_sharePrice, _timestamp));
    }

    // MOCKS: CONTRACTS

    function setMockFeeHandler(address _shares, uint256 _totalValueOwed) internal returns (address feeHandler_) {
        feeHandler_ = address(new BlankFeeHandler());

        vm.prank(Shares(_shares).owner());
        Shares(_shares).setFeeHandler(feeHandler_);

        feeHandler_mockGetTotalValueOwed({_feeHandler: feeHandler_, _totalValueOwed: _totalValueOwed});
    }

    // NETWORK SELECTION

    function createSelectEthereumFork() internal {
        vm.createSelectFork("mainnet", ETHEREUM_BLOCK_LATEST);
    }

    function createSelectBaseChainFork() internal {
        vm.createSelectFork("base", BASE_BLOCK_LATEST);
    }

    function createSelectArbitrumFork() internal {
        vm.createSelectFork("arbitrum", ARBITRUM_BLOCK_LATEST);
    }

    function createSelectPlumeFork() internal {
        vm.createSelectFork(vm.envString("ETHEREUM_NODE_PLUME"), PLUME_BLOCK_LATEST);
    }

    function createSelectMegaEthFork() internal {
        vm.createSelectFork(vm.envString("ETHEREUM_NODE_MEGA_ETH"), MEGA_ETH_BLOCK_LATEST);
    }

    function createSelectEthereumSepoliaFork() internal {
        vm.createSelectFork(vm.envString("ETHEREUM_NODE_ETHEREUM_SEPOLIA"), ETHEREUM_SEPOLIA_BLOCK_LATEST);
    }

    function createSelectRaylsFork() internal {
        vm.createSelectFork(vm.envString("ETHEREUM_NODE_RAYLS"), RAYLS_BLOCK_LATEST);
    }

    function createSelectBnbSmartChainFork() internal {
        vm.createSelectFork(vm.envString("ETHEREUM_NODE_BNB_SMART_CHAIN"), BNB_SMART_CHAIN_BLOCK_LATEST);
    }

    // MISC

    function increaseSharesSupply(address _shares, uint256 _increaseAmount) internal {
        // Mint shares to create desired supply
        address mintTo = makeAddr("increaseSharesSupply:mintTo");
        deal({token: _shares, to: mintTo, give: _increaseAmount, adjust: true});
    }
}
