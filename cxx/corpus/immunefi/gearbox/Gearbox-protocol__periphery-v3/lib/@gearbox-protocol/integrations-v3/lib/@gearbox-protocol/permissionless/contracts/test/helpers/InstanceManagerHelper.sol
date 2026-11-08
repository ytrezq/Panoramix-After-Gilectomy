// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {BCRHelpers} from "./BCRHelpers.sol";
import {CCGHelper} from "./CCGHelper.sol";
import {AddressProvider} from "../../../contracts/instance/AddressProvider.sol";
import {InstanceManager} from "../../../contracts/instance/InstanceManager.sol";
import {BytecodeRepository} from "../../../contracts/global/BytecodeRepository.sol";
import {
    AP_INSTANCE_MANAGER,
    AP_BYTECODE_REPOSITORY,
    AP_PRICE_FEED_STORE,
    NO_VERSION_CONTROL
} from "../../../contracts/libraries/ContractLiterals.sol";
import {CrossChainCall} from "../../../contracts/interfaces/ICrossChainMultisig.sol";
import {IBytecodeRepository} from "../../../contracts/interfaces/IBytecodeRepository.sol";
import {IPriceFeedStore} from "../../../contracts/interfaces/IPriceFeedStore.sol";
import {IAddressProvider} from "../../../contracts/interfaces/IAddressProvider.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {console} from "forge-std/console.sol";
import {LibString} from "@solady/utils/LibString.sol";
import {VmSafe} from "forge-std/Vm.sol";

contract InstanceManagerHelper is BCRHelpers, CCGHelper {
    using LibString for bytes32;
    using LibString for uint256;
    // Core contracts

    InstanceManager internal instanceManager;

    constructor() {}

    function _isTestMode() internal pure virtual override(CCGHelper, BCRHelpers) returns (bool) {
        return false;
    }

    function _deployInstanceManager(VmSafe.Wallet[] memory _initialSigners, uint8 _threshold, address _dao) internal {
        _deployCCG(_initialSigners, _threshold, _dao);

        // Generate random private keys and derive addresses

        // Deploy InstanceManager owned by multisig
        instanceManager = new InstanceManager{salt: bytes32("SALT")}(address(multisig));
        bytecodeRepository = instanceManager.bytecodeRepository();
    }

    function _attachInstanceManager(address[] memory _initialSigners, uint8 _threshold, address _dao) internal {
        _attachCCG(_initialSigners, _threshold, _dao);
        address instanceManagerAddress = computeInstanceManagerAddress();

        if (instanceManagerAddress.code.length == 0) {
            revert("InstanceManager not deployed");
        }

        instanceManager = InstanceManager(instanceManagerAddress);
        bytecodeRepository = instanceManager.bytecodeRepository();
    }

    function computeInstanceManagerAddress() internal view returns (address) {
        bytes memory creationCode = abi.encodePacked(type(InstanceManager).creationCode, abi.encode(multisig));

        return Create2.computeAddress(
            bytes32("SALT"), keccak256(creationCode), address(0x4e59b44847b379578588920cA78FbF26c0B4956C)
        );
    }

    function _generateAddAuditorCall(address _auditor, string memory _name)
        internal
        view
        returns (CrossChainCall memory)
    {
        return _buildCrossChainCallDAO(
            bytecodeRepository, abi.encodeCall(IBytecodeRepository.addAuditor, (_auditor, _name))
        );
    }

    function _generateAllowSystemContractCall(bytes32 _bytecodeHash) internal view returns (CrossChainCall memory) {
        return _buildCrossChainCallDAO(
            bytecodeRepository, abi.encodeCall(IBytecodeRepository.allowSystemContract, (_bytecodeHash))
        );
    }

    function _generateAllowPublicContractCall(bytes32 _bytecodeHash) internal view returns (CrossChainCall memory) {
        return _buildCrossChainCallDAO(
            bytecodeRepository, abi.encodeCall(IBytecodeRepository.allowPublicContract, (_bytecodeHash))
        );
    }

    function _generateDeploySystemContractCall(bytes32 _contractName, uint256 _version, bool _saveVersion)
        internal
        view
        returns (CrossChainCall memory)
    {
        return CrossChainCall({
            chainId: 0,
            target: address(instanceManager),
            callData: abi.encodeCall(InstanceManager.deploySystemContract, (_contractName, _version, _saveVersion))
        });
    }

    function _generateAddPublicDomainCall(bytes32 domain) internal view returns (CrossChainCall memory) {
        return
            _buildCrossChainCallDAO(bytecodeRepository, abi.encodeCall(IBytecodeRepository.addPublicDomain, (domain)));
    }

    function _generateActivateCall(
        uint256 _chainId,
        address _instanceOwner,
        address _treasury,
        address _weth,
        address _gear
    ) internal view returns (CrossChainCall memory) {
        return CrossChainCall({
            chainId: _chainId,
            target: address(instanceManager),
            callData: abi.encodeCall(InstanceManager.activate, (_instanceOwner, _treasury, _weth, _gear))
        });
    }

    function _buildCrossChainCallDAO(address _target, bytes memory _callData)
        internal
        view
        returns (CrossChainCall memory)
    {
        return CrossChainCall({
            chainId: 0,
            target: address(instanceManager),
            callData: abi.encodeCall(InstanceManager.configureGlobal, (_target, _callData))
        });
    }

    function _allowPriceFeed(address _instanceOwner, address token, address _priceFeed) internal {
        address ap = instanceManager.addressProvider();
        address priceFeedStore = IAddressProvider(ap).getAddressOrRevert(AP_PRICE_FEED_STORE, NO_VERSION_CONTROL);
        _startPrankOrBroadcast(_instanceOwner);
        instanceManager.configureLocal(
            priceFeedStore, abi.encodeCall(IPriceFeedStore.allowPriceFeed, (token, _priceFeed))
        );
        _stopPrankOrBroadcast();
    }

    function _addPriceFeed(address _instanceOwner, address _priceFeed, uint32 _stalenessPeriod, string memory _name)
        internal
    {
        address ap = instanceManager.addressProvider();
        address priceFeedStore = IAddressProvider(ap).getAddressOrRevert(AP_PRICE_FEED_STORE, NO_VERSION_CONTROL);
        _startPrankOrBroadcast(_instanceOwner);
        instanceManager.configureLocal(
            priceFeedStore, abi.encodeCall(IPriceFeedStore.addPriceFeed, (_priceFeed, _stalenessPeriod, _name))
        );
        _stopPrankOrBroadcast();
    }
}
