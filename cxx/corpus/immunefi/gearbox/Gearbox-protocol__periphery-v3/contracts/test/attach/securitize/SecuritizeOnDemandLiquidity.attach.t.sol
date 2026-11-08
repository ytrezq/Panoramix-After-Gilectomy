// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {AttachTestBase} from "@gearbox-protocol/permissionless/contracts/test/suite/AttachTestBase.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {MultiCall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {ICreditFacadeV3Multicall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3Multicall.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";

import {
    ISecuritizeOnRampAdapter
} from "@gearbox-protocol/integrations-v3/contracts/interfaces/securitize/ISecuritizeOnRampAdapter.sol";
import {IERC4626Adapter} from "@gearbox-protocol/integrations-v3/contracts/interfaces/erc4626/IERC4626Adapter.sol";

import {ISecuritizeDegenNFT} from "../../../interfaces/ISecuritizeDegenNFT.sol";
import {ISecuritizeRWAFactory} from "../../../interfaces/ISecuritizeRWAFactory.sol";
import {IDSToken} from "../../../interfaces/external/securitize/IDSToken.sol";

import {SecuritizeAttachHelper} from "./SecuritizeAttachHelper.sol";

contract SecuritizeOnDemandLiquidityAttachTest is Test, SecuritizeAttachHelper {
    address public cUSDC;
    address public pool;
    address[] public creditManagers;
    address public liquidityProvider;

    VmSafe.Wallet public investor;
    address public depositor;

    function setUp() public {
        vm.skip(ADDRESS_PROVIDER.code.length == 0, "Not in an attach mode");
        vm.skip(block.chainid != 1, "Not Ethereum mainnet");
        // NOTE: even though we compile our contracts under Shanghai EVM version,
        // more recent one is usually needed to interact with third-party contracts
        vm.setEvmVersion("osaka");

        deployer = vm.createWallet("Fake Deployer");
        author = vm.createWallet("Fake Author");
        auditor = vm.createWallet("Fake Auditor");
        riskCurator = vm.createWallet("Fake Risk Curator");

        deal({token: USDC, to: riskCurator.addr, give: 100_000e6});

        securitize = makeAddr("securitize");
        investor = vm.createWallet("investor");
        depositor = makeAddr("depositor");

        _setUp();
        _setUpBytecode();
        _attachSecuritize();

        // NOTE: adding degen NFT as periphery contract is required to use it in the credit suite
        _addPeripheryContract(degenNFT);

        (cUSDC, pool, creditManagers, liquidityProvider) = _createMarketWithOnDemandRWAUnderlying(depositor);

        // NOTE: can't borrow in the same block as facade deployment
        vm.roll(block.number + 1);

        deal({token: USDC, to: depositor, give: 1_000_000e6});
        _omniPrank(depositor);
        ERC20(USDC).approve(liquidityProvider, 1_000_000e6);
    }

    function test_borrowing_via_securitize_factory() public repeatTestForEachDSToken {
        uint256 amount = _convertFromUSDC(60_000e6, dsTokens[idx]);

        _registerInvestor(investor.addr, dsTokens[idx]);
        _omniPrank(securitize);
        IDSToken(dsTokens[idx].token).issueTokens(investor.addr, amount);

        address wallet = ISecuritizeRWAFactory(factory).precomputeWalletAddress(creditManagers[idx], investor.addr);
        _omniPrank(investor);
        ERC20(dsTokens[idx].token).approve(wallet, amount);

        address creditFacade = ICreditManagerV3(creditManagers[idx]).creditFacade();
        address underlyingAdapter = ICreditManagerV3(creditManagers[idx]).contractToAdapter(cUSDC);

        MultiCall[] memory calls = new MultiCall[](5);
        calls[0] = MultiCall({
            target: creditFacade, callData: abi.encodeCall(ICreditFacadeV3Multicall.increaseDebt, (50_000e6))
        });
        calls[1] = MultiCall({target: underlyingAdapter, callData: abi.encodeCall(IERC4626Adapter.redeemDiff, (1))});
        calls[2] = MultiCall({
            target: creditFacade,
            callData: abi.encodeCall(
                ICreditFacadeV3Multicall.withdrawCollateral, (USDC, type(uint256).max, investor.addr)
            )
        });
        calls[3] = MultiCall({
            target: creditFacade,
            callData: abi.encodeCall(ICreditFacadeV3Multicall.addCollateral, (dsTokens[idx].token, amount))
        });
        calls[4] = MultiCall({
            target: creditFacade,
            callData: abi.encodeCall(ICreditFacadeV3Multicall.updateQuota, (dsTokens[idx].token, 55_000e6, 0))
        });

        address[] memory tokensToRegister = new address[](1);
        tokensToRegister[0] = dsTokens[idx].token;

        ISecuritizeDegenNFT.RegisterMessage[] memory signaturesToCache = new ISecuritizeDegenNFT.RegisterMessage[](1);
        signaturesToCache[0] = _signRegisterVaultMessage(investor, dsTokens[idx]);

        _omniPrank(investor);
        ISecuritizeRWAFactory(factory)
            .openCreditAccount(creditManagers[idx], calls, tokensToRegister, signaturesToCache);
    }

    function test_leverage_via_securitize_factory() public repeatTestForEachDSToken {
        vm.skip(dsTokens[idx].onRamp == address(0), "Skipping test for mock token with no on-ramp");

        _registerInvestor(investor.addr, dsTokens[idx]);
        deal({token: USDC, to: investor.addr, give: 10_000e6});

        address wallet = ISecuritizeRWAFactory(factory).precomputeWalletAddress(creditManagers[idx], investor.addr);
        _omniPrank(investor);
        ERC20(USDC).approve(wallet, 10_000e6);

        address creditFacade = ICreditManagerV3(creditManagers[idx]).creditFacade();
        address underlyingAdapter = ICreditManagerV3(creditManagers[idx]).contractToAdapter(cUSDC);
        address onRampAdapter = ICreditManagerV3(creditManagers[idx]).contractToAdapter(dsTokens[idx].onRamp);

        MultiCall[] memory calls = new MultiCall[](5);
        calls[0] = MultiCall({
            target: creditFacade, callData: abi.encodeCall(ICreditFacadeV3Multicall.increaseDebt, (50_000e6))
        });
        calls[1] = MultiCall({target: underlyingAdapter, callData: abi.encodeCall(IERC4626Adapter.redeemDiff, (1))});
        calls[2] = MultiCall({
            target: creditFacade, callData: abi.encodeCall(ICreditFacadeV3Multicall.addCollateral, (USDC, 10_000e6))
        });
        calls[3] =
            MultiCall({target: onRampAdapter, callData: abi.encodeCall(ISecuritizeOnRampAdapter.swapDiff, (1, 0))});
        calls[4] = MultiCall({
            target: creditFacade,
            callData: abi.encodeCall(ICreditFacadeV3Multicall.updateQuota, (dsTokens[idx].token, 55_000e6, 0))
        });

        address[] memory tokensToRegister = new address[](1);
        tokensToRegister[0] = dsTokens[idx].token;

        ISecuritizeDegenNFT.RegisterMessage[] memory signaturesToCache = new ISecuritizeDegenNFT.RegisterMessage[](1);
        signaturesToCache[0] = _signRegisterVaultMessage(investor, dsTokens[idx]);

        _omniPrank(investor);
        ISecuritizeRWAFactory(factory)
            .openCreditAccount(creditManagers[idx], calls, tokensToRegister, signaturesToCache);
    }
}
