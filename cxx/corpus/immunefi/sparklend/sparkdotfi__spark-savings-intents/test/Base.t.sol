// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { Test } from "../lib/forge-std/src/Test.sol";

import { Ethereum } from "../lib/spark-address-registry/src/Ethereum.sol";

import { IERC20Like }   from "./interfaces/IERC20Like.sol";
import { IERC4626Like } from "./interfaces/IERC4626Like.sol";
import { IVaultLike }   from "./interfaces/IVaultLike.sol";

import { ISavingsVaultIntents } from "../src/interfaces/ISavingsVaultIntents.sol";
import { SavingsVaultIntents }  from "../src/SavingsVaultIntents.sol";

contract TestBase is Test {

    uint256 internal constant DEPOSIT_AMOUNT_USDC    = 1_000_000e6;
    uint256 internal constant MIN_INTENT_ASSETS_USDC = 10e6;
    uint256 internal constant MAX_INTENT_ASSETS_USDC = 100_000_000e6;

    uint256 internal constant DEPOSIT_AMOUNT_ETH    = 100e18;
    uint256 internal constant MIN_INTENT_ASSETS_ETH = 10e18;
    uint256 internal constant MAX_INTENT_ASSETS_ETH = 10_000e18;

    IERC4626Like internal sparkVaultUSDC;
    IERC4626Like internal sparkVaultETH;

    uint256 internal sparkVaultUSDCInitSupply;
    uint256 internal sparkVaultETHInitSupply;

    bytes32 internal defaultAdminRole;
    bytes32 internal relayerRole;

    address internal admin;
    address internal relayer;
    address internal unauthorized;
    address internal user;

    uint256 internal userSpUSDCShares;
    uint256 internal userSpETHShares;

    SavingsVaultIntents internal savingsVaultIntents;

    function setUp() public virtual {
        vm.createSelectFork(getChain("mainnet").rpcUrl, _getBlock());

        sparkVaultUSDC = IERC4626Like(Ethereum.SPARK_VAULT_V2_SPUSDC);
        sparkVaultETH  = IERC4626Like(Ethereum.SPARK_VAULT_V2_SPETH);

        admin        = makeAddr("admin");
        relayer      = makeAddr("relayer");
        user         = makeAddr("user");
        unauthorized = makeAddr("unauthorized");

        savingsVaultIntents = new SavingsVaultIntents(admin, relayer, 1 days);

        // Whitelisting sparkVaultUSDC
        vm.prank(admin);
        savingsVaultIntents.updateVaultConfig(
            address(sparkVaultUSDC),
            true,
            MIN_INTENT_ASSETS_USDC,
            MAX_INTENT_ASSETS_USDC
        );

        // Whitelisting sparkVaultETH
        vm.prank(admin);
        savingsVaultIntents.updateVaultConfig(
            address(sparkVaultETH),
            true,
            MIN_INTENT_ASSETS_ETH,
            MAX_INTENT_ASSETS_ETH
        );

        _userInitialSetup();

        // Vaults totalSupply at _getBlock() + above user initial deposit

        sparkVaultUSDCInitSupply = sparkVaultUSDC.totalSupply();
        sparkVaultETHInitSupply  = sparkVaultETH.totalSupply();
    }

    function _getBlock() internal virtual pure returns (uint256) {
        return 24319071; //  January 26, 2026
    }

    function _userInitialSetup() internal {
        // User deposits assets into vaults

        userSpUSDCShares = _depositToVault(user, sparkVaultUSDC, DEPOSIT_AMOUNT_USDC);
        userSpETHShares  = _depositToVault(user, sparkVaultETH,  DEPOSIT_AMOUNT_ETH);

        // User approval to savingsVaultIntent

        vm.startPrank(user);

        sparkVaultUSDC.approve(address(savingsVaultIntents), userSpUSDCShares);
        sparkVaultETH.approve(address(savingsVaultIntents),  userSpETHShares);

        vm.stopPrank();
    }

    function _depositToVault(
        address      account,
        IERC4626Like vault,
        uint256      assets
    )
        internal
        returns (uint256 shares)
    {
        address underlyingAsset = vault.asset();

        deal(underlyingAsset, account, assets);

        vm.prank(account);
        IERC20Like(underlyingAsset).approve(address(vault), assets);

        vm.prank(account);
        shares = vault.deposit(assets, account);
    }

    function _createRequest(
        address      account,
        IERC4626Like vault,
        uint256      shares_,
        uint256      deadline_
    )
        internal 
        returns (uint256 requestId) 
    {
        vm.prank(account);
        requestId = savingsVaultIntents.request({
            vault     : address(vault),
            shares    : shares_,
            recipient : account,
            deadline  : deadline_
        });
    }

    function _assertRequest(
        address      account,
        IERC4626Like vault,
        uint256      expectedRequestId,
        uint256      expectedShares,
        address      expectedRecipient,
        uint256      expectedDeadline
    )
        internal view
    {
        ( 
            uint256 requestId_,
            uint256 shares_,
            address recipient_,
            uint256 deadline_
        ) = savingsVaultIntents.withdrawRequests(account, address(vault));

        assertEq(requestId_, expectedRequestId);
        assertEq(shares_,    expectedShares);
        assertEq(recipient_, expectedRecipient);
        assertEq(deadline_,  expectedDeadline);
    }

    function _assertEmptyRequest(address account, IERC4626Like vault) internal view {
        _assertRequest({
            account           : account,
            vault             : vault,
            expectedRequestId : 0,
            expectedShares    : 0,
            expectedRecipient : address(0),
            expectedDeadline  : 0
        });
    }

}
