// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IAddressProvider} from "@gearbox-protocol/permissionless/contracts/interfaces/IAddressProvider.sol";
import {IMarketConfigurator} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfigurator.sol";
import {IContractsRegister} from "@gearbox-protocol/permissionless/contracts/interfaces/IContractsRegister.sol";
import {IMarketConfiguratorFactory} from
    "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfiguratorFactory.sol";
import {
    AP_MARKET_CONFIGURATOR_FACTORY,
    NO_VERSION_CONTROL
} from "@gearbox-protocol/permissionless/contracts/libraries/ContractLiterals.sol";

import {ICreditAccountV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditAccountV3.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";

import {AP_DEFILLAMA_COMPRESSOR} from "../libraries/Literals.sol";

import {DefillamaCreditAccountData, DefillamaTokenInfo, DefillamaPoolData} from "../types/Defillama.sol";
import {IDefillamaCompressor} from "../interfaces/IDefillamaCompressor.sol";

/// @title  Credit account compressor
/// @notice Allows to fetch data on all credit accounts matching certain criteria in an efficient manner
/// @dev    The contract is not gas optimized and is thus not recommended for on-chain use
/// @dev    Querying functions try to process as many accounts as possible and stop when they get close to gas limit
contract DefillamaCompressor is IDefillamaCompressor {
    struct Pool {
        address addr;
        address configurator;
    }

    /// @notice Contract version
    uint256 public constant override version = 3_10;

    /// @notice Contract type
    bytes32 public constant override contractType = AP_DEFILLAMA_COMPRESSOR;

    address public immutable addressProvider;

    /// @notice Constructor
    /// @param  addressProvider_ Address provider contract address
    constructor(address addressProvider_) {
        addressProvider = addressProvider_;
    }

    function getPools(address[] memory configurators) external view returns (DefillamaPoolData[] memory pools) {
        return _getPools(configurators);
    }

    function getPools() external view returns (DefillamaPoolData[] memory pools) {
        address mcFactory =
            IAddressProvider(addressProvider).getAddressOrRevert(AP_MARKET_CONFIGURATOR_FACTORY, NO_VERSION_CONTROL);
        address[] memory configurators = IMarketConfiguratorFactory(mcFactory).getMarketConfigurators();
        return _getPools(configurators);
    }

    function getCreditManagers(address[] memory configurators)
        external
        view
        returns (address[] memory creditManagers)
    {
        return _getCreditManagers(configurators);
    }

    function getCreditManagers() external view returns (address[] memory creditManagers) {
        address mcFactory =
            IAddressProvider(addressProvider).getAddressOrRevert(AP_MARKET_CONFIGURATOR_FACTORY, NO_VERSION_CONTROL);
        address[] memory configurators = IMarketConfiguratorFactory(mcFactory).getMarketConfigurators();
        return _getCreditManagers(configurators);
    }

    /// @notice Returns data for credit accounts in a given `creditManager`
    function getCreditAccounts(address creditManager)
        external
        view
        returns (DefillamaCreditAccountData[] memory data)
    {
        return _getCreditAccounts(creditManager, 0, type(uint256).max);
    }

    /// @dev Same as above but with limit and offset
    function getCreditAccounts(address creditManager, uint256 offset, uint256 limit)
        external
        view
        returns (DefillamaCreditAccountData[] memory data)
    {
        return _getCreditAccounts(creditManager, offset, limit);
    }

    // --------- //
    // INTERNALS //
    // --------- //

    function _getCreditAccounts(address creditManager, uint256 offset, uint256 limit)
        internal
        view
        returns (DefillamaCreditAccountData[] memory data)
    {
        uint256 len = ICreditManagerV3(creditManager).creditAccountsLen();

        if (offset >= len) {
            return new DefillamaCreditAccountData[](0);
        }
        address[] memory creditAccounts =
            ICreditManagerV3(creditManager).creditAccounts(offset, Math.min(len - offset, limit));

        data = new DefillamaCreditAccountData[](creditAccounts.length);
        for (uint256 i; i < creditAccounts.length; ++i) {
            data[i] = _getCreditAccountData(creditAccounts[i], creditManager);
        }
    }

    /// @dev Data loading implementation
    function _getCreditAccountData(address creditAccount, address creditManager)
        internal
        view
        returns (DefillamaCreditAccountData memory data)
    {
        data.creditAccount = creditAccount;

        (uint256 debt,,,, uint256 enabledTokensMask,,,) =
            ICreditManagerV3(creditManager).creditAccountInfo(creditAccount);
        data.debt = debt;
        // ignore tokens on zero-debt accounts
        if (debt == 0) {
            return data;
        }

        uint256 maxTokens = ICreditManagerV3(creditManager).collateralTokensCount();

        // the function is called for every account, so allocating an array of size `maxTokens` and trimming it
        // might cause issues with memory expansion and we must count the precise number of tokens in advance
        uint256 numTokens;
        uint256 returnedTokensMask;
        for (uint256 k; k < maxTokens; ++k) {
            uint256 mask = 1 << k;
            if (enabledTokensMask & mask == 0) {
                address token = ICreditManagerV3(creditManager).getTokenByMask(mask);
                try IERC20(token).balanceOf(creditAccount) returns (uint256 balance) {
                    if (balance <= 1) continue;
                } catch {
                    continue;
                }
            }
            ++numTokens;
            returnedTokensMask |= mask;
        }

        data.tokens = new DefillamaTokenInfo[](numTokens);
        uint256 i;
        while (returnedTokensMask != 0) {
            uint256 mask = returnedTokensMask & uint256(-int256(returnedTokensMask));
            address token = ICreditManagerV3(creditManager).getTokenByMask(mask);
            data.tokens[i].token = token;

            try IERC20(token).balanceOf(creditAccount) returns (uint256 balance) {
                data.tokens[i].balance = balance;
            } catch {}

            returnedTokensMask ^= mask;
            ++i;
        }
    }

    function _getPools(address[] memory configurators) internal view returns (DefillamaPoolData[] memory pools) {
        Pool[] memory _pools = _getPoolsInternal(configurators);
        pools = new DefillamaPoolData[](_pools.length);
        for (uint256 i; i < _pools.length; ++i) {
            Pool memory pool = _pools[i];
            pools[i] = DefillamaPoolData({
                pool: pool.addr,
                underlying: IPoolV3(pool.addr).asset(),
                totalBorrowed: IPoolV3(pool.addr).totalBorrowed(),
                availableLiquidity: IPoolV3(pool.addr).availableLiquidity()
            });
        }
    }

    function _getCreditManagers(address[] memory configurators)
        internal
        view
        returns (address[] memory creditManagers)
    {
        Pool[] memory pools = _getPoolsInternal(configurators);

        // rough estimate of maximum number of credit managers
        uint256 max;
        for (uint256 i; i < pools.length; ++i) {
            address cr = IMarketConfigurator(pools[i].configurator).contractsRegister();
            max += IContractsRegister(cr).getCreditManagers(pools[i].addr).length;
        }

        // allocate the array with maximum potentially needed size (total number of credit managers can be assumed
        // to be relatively small and the function is only called once, so memory expansion cost is not an issue)
        creditManagers = new address[](max);
        uint256 num;
        for (uint256 i; i < pools.length; ++i) {
            address cr = IMarketConfigurator(pools[i].configurator).contractsRegister();
            address[] memory managers = IContractsRegister(cr).getCreditManagers(pools[i].addr);
            for (uint256 j; j < managers.length; ++j) {
                creditManagers[num++] = managers[j];
            }
        }
        // trim the array to its actual size
        assembly {
            mstore(creditManagers, num)
        }
    }

    function _getPoolsInternal(address[] memory configurators) internal view returns (Pool[] memory pools) {
        uint256 numPools;
        for (uint256 i; i < configurators.length; ++i) {
            address contractsRegister = IMarketConfigurator(configurators[i]).contractsRegister();
            numPools += IContractsRegister(contractsRegister).getPools().length;
        }

        pools = new Pool[](numPools);
        uint256 num;

        for (uint256 i; i < configurators.length; ++i) {
            address contractsRegister = IMarketConfigurator(configurators[i]).contractsRegister();
            address[] memory poolsMC = IContractsRegister(contractsRegister).getPools();
            for (uint256 j; j < poolsMC.length; ++j) {
                address pool = poolsMC[j];

                pools[num++] = Pool({addr: pool, configurator: configurators[i]});
            }
        }
    }
}
