// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import 'forge-std/Script.sol';
import 'forge-std/console.sol';

import {ListaV3Factory} from '../src/core/ListaV3Factory.sol';
import {NonfungiblePositionManager} from '../src/periphery/NonfungiblePositionManager.sol';
import {SwapRouter} from '../src/periphery/SwapRouter.sol';

import {ProxyAdmin} from 'lib/openzeppelin-contracts/contracts/proxy/ProxyAdmin.sol';
import {TransparentUpgradeableProxy} from 'lib/openzeppelin-contracts/contracts/proxy/TransparentUpgradeableProxy.sol';

/// @title Deploy Lista V3 factory / NPM / SwapRouter
/// @notice Multi-chain deploy. WETH9 is resolved by chain id with built-in values for
/// common networks; on unknown chains the `WETH9` env var is required. Owner addresses
/// come from env. Run per chain with `--rpc-url $RPC` + either `--private-key`
/// or a `--ledger` / hardware signer.
///
/// Required env:
///   OWNER                 = factory owner (fee-tier admin)
///
/// Optional env (with defaults):
///   PROXY_ADMIN_OWNER     = owner of ProxyAdmin (defaults to OWNER)
///   TOKEN_DESCRIPTOR      = NFT position descriptor address (defaults to 0x0, disables tokenURI)
///   WETH9                 = WETH9 address (required on unknown chains; overrides built-ins)
///
/// Usage:
///   forge script script/Deploy.s.sol:Deploy --rpc-url $RPC --broadcast --verify
contract Deploy is Script {
    struct Deployment {
        address proxyAdmin;
        address factory;
        address npmImpl;
        address npmProxy;
        address swapRouter;
    }

    function run() external returns (Deployment memory out) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        address weth9 = _resolveWeth9(chainId);
        address owner = vm.envAddress('OWNER');
        address proxyAdminOwner = vm.envOr('PROXY_ADMIN_OWNER', owner);
        address tokenDescriptor = vm.envOr('TOKEN_DESCRIPTOR', address(0));

        require(owner != address(0), 'OWNER=0');
        require(proxyAdminOwner != address(0), 'PROXY_ADMIN_OWNER=0');
        require(weth9 != address(0), 'WETH9=0');

        console.log('--- Lista V3 deploy ---');
        console.log('chainId:', chainId);
        console.log('network:', _chainLabel(chainId));
        console.log('owner:', owner);
        console.log('proxyAdminOwner:', proxyAdminOwner);
        console.log('WETH9:', weth9);
        console.log('tokenDescriptor:', tokenDescriptor);

        vm.startBroadcast();

        ProxyAdmin proxyAdmin = new ProxyAdmin();
        // ProxyAdmin.owner() is set to msg.sender (the broadcaster) in its constructor.
        // Transfer only if a different owner was requested.
        if (proxyAdminOwner != proxyAdmin.owner()) {
            proxyAdmin.transferOwnership(proxyAdminOwner);
        }

        // Factory: plain deploy. owner = msg.sender (the broadcaster). If a separate
        // owner is required, the broadcaster should call factory.setOwner(owner) after.
        ListaV3Factory factory = new ListaV3Factory();
        if (owner != msg.sender) {
            factory.setOwner(owner);
        }

        // NPM: impl + proxy. factory/WETH9 are constructor immutables on the impl; every
        // future upgrade MUST re-pass the exact same (factory, WETH9) to the new impl.
        NonfungiblePositionManager npmImpl = new NonfungiblePositionManager(address(factory), weth9);
        npmImpl.initialize(address(0xdead));

        bytes memory npmInit = abi.encodeWithSelector(NonfungiblePositionManager.initialize.selector, tokenDescriptor);
        TransparentUpgradeableProxy npmProxy =
            new TransparentUpgradeableProxy(address(npmImpl), address(proxyAdmin), npmInit);

        // SwapRouter is not upgradeable; plain deploy against the factory.
        SwapRouter swapRouter = new SwapRouter(address(factory), weth9);

        vm.stopBroadcast();

        out = Deployment({
            proxyAdmin: address(proxyAdmin),
            factory: address(factory),
            npmImpl: address(npmImpl),
            npmProxy: address(npmProxy),
            swapRouter: address(swapRouter)
        });

        console.log('--- deployed ---');
        console.log('ProxyAdmin:', out.proxyAdmin);
        console.log('Factory:', out.factory);
        console.log('NPM impl:', out.npmImpl);
        console.log('NPM proxy:', out.npmProxy);
        console.log('SwapRouter:', out.swapRouter);
    }

    /// @dev Built-in WETH9 addresses keyed by chain id. Any explicit `WETH9` env var
    /// overrides. Add entries here when onboarding a new chain.
    function _resolveWeth9(uint256 chainId) internal returns (address) {
        address override_ = vm.envOr('WETH9', address(0));
        if (override_ != address(0)) return override_;

        if (chainId == 1) return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Ethereum — WETH
        if (chainId == 11155111) return 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14; // Sepolia — WETH (Uniswap canonical)
        if (chainId == 56) return 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // BNB Chain — WBNB
        if (chainId == 97) return 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd; // BNB Chain testnet — WBNB

        revert('WETH9 not set: pass WETH9=0x... or add chain id to _resolveWeth9');
    }

    function _chainLabel(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 1) return 'ethereum';
        if (chainId == 11155111) return 'sepolia';
        if (chainId == 56) return 'bnb';
        if (chainId == 97) return 'bnb-testnet';
        if (chainId == 31337) return 'anvil';
        return 'unknown';
    }
}
