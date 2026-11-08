// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LibString} from "@solady/utils/LibString.sol";

import {BytecodeRepository} from "../global/BytecodeRepository.sol";
import {ProxyCall} from "../helpers/ProxyCall.sol";
import {IInstanceManager} from "../interfaces/IInstanceManager.sol";
import {
    AP_BYTECODE_REPOSITORY,
    AP_CROSS_CHAIN_GOVERNANCE,
    AP_CROSS_CHAIN_GOVERNANCE_PROXY,
    AP_GEAR_STAKING,
    AP_GEAR_TOKEN,
    AP_INSTANCE_MANAGER,
    AP_INSTANCE_MANAGER_PROXY,
    AP_TREASURY,
    AP_TREASURY_PROXY,
    AP_WETH_TOKEN,
    NO_VERSION_CONTROL
} from "../libraries/ContractLiterals.sol";

import {AddressProvider} from "./AddressProvider.sol";

/// @title Instance manager
contract InstanceManager is Ownable, IInstanceManager {
    using LibString for string;
    using LibString for bytes32;

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_INSTANCE_MANAGER;

    /// @notice Address provider
    address public immutable override addressProvider;

    /// @notice Bytecode repository
    address public immutable override bytecodeRepository;

    /// @notice Instance manager proxy
    address public immutable override instanceManagerProxy;

    /// @notice Treasury proxy
    address public immutable override treasuryProxy;

    /// @notice Cross-chain governance proxy
    address public immutable override crossChainGovernanceProxy;

    /// @notice Whether the instance is activated
    bool public override isActivated;

    /// @notice Pending governance
    address public override pendingGovernance;

    /// @dev Reverts if caller is not cross-chain governance
    modifier onlyCrossChainGovernance() {
        if (msg.sender != _getAddressOrRevert(AP_CROSS_CHAIN_GOVERNANCE, NO_VERSION_CONTROL)) {
            revert CallerIsNotCrossChainGovernanceException(msg.sender);
        }
        _;
    }

    /// @dev Reverts if caller is not pending governance
    modifier onlyPendingGovernance() {
        if (msg.sender != pendingGovernance) revert CallerIsNotPendingGovernanceException(msg.sender);
        _;
    }

    /// @dev Reverts if caller is not the DAO treasury
    modifier onlyTreasury() {
        if (msg.sender != _getAddressOrRevert(AP_TREASURY, NO_VERSION_CONTROL)) {
            revert CallerIsNotTreasuryException(msg.sender);
        }
        _;
    }

    /// @notice Constructor
    /// @param owner_ Contract owner (upon contract creation, must be cross-chain governance)
    constructor(address owner_) {
        instanceManagerProxy = address(new ProxyCall());
        treasuryProxy = address(new ProxyCall());
        crossChainGovernanceProxy = address(new ProxyCall());

        bytecodeRepository = address(new BytecodeRepository(crossChainGovernanceProxy));
        addressProvider = address(new AddressProvider(address(this)));

        _setAddress(AP_BYTECODE_REPOSITORY, address(bytecodeRepository), false);
        _setAddress(AP_CROSS_CHAIN_GOVERNANCE, owner_, false);

        _setAddress(AP_INSTANCE_MANAGER_PROXY, instanceManagerProxy, false);
        _setAddress(AP_TREASURY_PROXY, treasuryProxy, false);
        _setAddress(AP_CROSS_CHAIN_GOVERNANCE_PROXY, crossChainGovernanceProxy, false);
        _setAddress(AP_INSTANCE_MANAGER, address(this), false);

        _transferOwnership(owner_);
    }

    /// @notice Returns the instance owner
    function owner() public view override(Ownable, IInstanceManager) returns (address) {
        return super.owner();
    }

    // ------------- //
    // CONFIGURATION //
    // ------------- //

    /// @notice Activates the instance, setting the instance owner and saving the treasury, WETH and GEAR addresses
    /// @dev GEAR can be zero in case it's not deployed on given chain yet. It can later be set using `setGlobalAddress`.
    /// @dev Can only be called once by the cross-chain governance
    function activate(address instanceOwner, address treasury, address weth, address gear)
        external
        override
        onlyOwner
    {
        if (isActivated) return;
        transferOwnership(instanceOwner);

        _setAddress(AP_TREASURY, treasury, false);
        _setAddress(AP_WETH_TOKEN, weth, false);
        if (gear != address(0)) _setAddress(AP_GEAR_TOKEN, gear, false);
        isActivated = true;
    }

    /// @notice Deploys a system contract and saves its address in the address provider
    /// @dev System contracts must accept address provider as the only constructor argument
    /// @dev Reverts if caller is not the cross-chain governance
    function deploySystemContract(bytes32 contractType_, uint256 version_, bool saveVersion)
        external
        override
        onlyCrossChainGovernance
    {
        address newSystemContract = contractType_ == AP_GEAR_STAKING && version_ == 3_10 && _isLegacyChain()
            ? _getLegacyGearStakingAddress()
            : _deploySystemContract(contractType_, version_);

        _setAddress(contractType_, newSystemContract, saveVersion);
    }

    /// @notice Allows cross-chain governance to set a global address in the address provider
    /// @dev `key` must start with the "GLOBAL::" prefix
    function setGlobalAddress(bytes32 key, address addr, bool saveVersion) external override onlyCrossChainGovernance {
        _setAddressWithPrefix(key, "GLOBAL::", addr, saveVersion);
    }

    /// @notice Allows instance owner to set a local address in the address provider
    /// @dev `key` must start with the "LOCAL::" prefix
    function setLocalAddress(bytes32 key, address addr, bool saveVersion) external override onlyOwner {
        _setAddressWithPrefix(key, "LOCAL::", addr, saveVersion);
    }

    /// @notice Allows cross-chain governance to configure global contracts such as bytecode repository, GEAR staking, etc.
    function configureGlobal(address target, bytes calldata data) external override onlyCrossChainGovernance {
        ProxyCall(crossChainGovernanceProxy).proxyCall(target, data);
    }

    /// @notice Allows instance owner to configure local contracts such as price feed store, bot list, etc.
    function configureLocal(address target, bytes calldata data) external override onlyOwner {
        ProxyCall(instanceManagerProxy).proxyCall(target, data);
    }

    /// @notice Allows DAO treasury to configure financial contracts such as fee splitters
    function configureTreasury(address target, bytes calldata data) external override onlyTreasury {
        ProxyCall(treasuryProxy).proxyCall(target, data);
    }

    /// @notice Sets `newCrossChainGovernance` as the pending cross-chain governance
    /// @dev Can only be called by the current cross-chain governance
    function setPendingGovernance(address newGovernance) external override onlyCrossChainGovernance {
        pendingGovernance = newGovernance;
        emit SetPendingGovernance(newGovernance);
    }

    /// @notice Accepts the cross-chain governance role
    /// @dev Can only be called by the pending governance
    function acceptGovernance() external override onlyPendingGovernance {
        _setAddress(AP_CROSS_CHAIN_GOVERNANCE, msg.sender, false);
        pendingGovernance = address(0);
        emit AcceptGovernance(msg.sender);
    }

    // --------- //
    // INTERNALS //
    // --------- //

    /// @dev Internal wrapper around address provider's `getAddressOrRevert` to reduce code size
    function _getAddressOrRevert(bytes32 key, uint256 ver) internal view returns (address) {
        return AddressProvider(addressProvider).getAddressOrRevert(key, ver);
    }

    /// @dev Internal wrapper around address provider's `setAddress` to reduce code size
    function _setAddress(bytes32 key, address value, bool saveVersion) internal {
        AddressProvider(addressProvider).setAddress(key, value, saveVersion);
    }

    /// @dev Sets address in the address provider, ensuring that `key` starts with `prefix`
    function _setAddressWithPrefix(bytes32 key, string memory prefix, address addr, bool saveVersion) internal {
        if (!key.fromSmallString().startsWith(prefix)) revert InvalidKeyException(key);
        _setAddress(key, addr, saveVersion);
    }

    /// @dev Deploys a system contract and returns its address
    function _deploySystemContract(bytes32 contractType_, uint256 version_) internal returns (address) {
        bytes memory result = ProxyCall(crossChainGovernanceProxy).proxyCall(
            address(bytecodeRepository),
            abi.encodeCall(BytecodeRepository.deploy, (contractType_, version_, abi.encode(addressProvider), 0))
        );
        return abi.decode(result, (address));
    }

    /// @dev Whether there is a legacy instance on this chain
    function _isLegacyChain() internal view returns (bool) {
        return block.chainid == 1 || block.chainid == 10 || block.chainid == 146 || block.chainid == 42161;
    }

    /// @dev Returns the address of the legacy GEAR staking contract on this chain
    function _getLegacyGearStakingAddress() internal view returns (address) {
        if (block.chainid == 1) {
            return 0x2fcbD02d5B1D52FC78d4c02890D7f4f47a459c33;
        } else if (block.chainid == 10) {
            return 0x8D2622f1CA3B42b637e2ff6753E6b69D3ab9Adfd;
        } else if (block.chainid == 146) {
            return 0xe88846b6C85AA67688e453c7eaeeeb40F51e1F0a;
        } else if (block.chainid == 42161) {
            return 0xf3599BEfe8E79169Afd5f0b7eb0A1aA322F193D9;
        } else {
            revert();
        }
    }
}
