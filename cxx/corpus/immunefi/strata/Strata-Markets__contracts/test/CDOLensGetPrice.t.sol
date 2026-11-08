// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {CDOLens, IChainlinkPriceFeed} from "../contracts/lens/CDOLens.sol";

/**
 * @title CDOLens getPrice Fork Test
 * @notice Deploys CDOLens on a mainnet fork, configures the USDe/USD Chainlink feed,
 *         and calls getPrice for srUSDe and jrUSDe tranches.
 */
contract CDOLensGetPriceTest is Test {
    CDOLens public lens;

    address constant USDe = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address constant SR_USDe = 0x3d7d6fdf07EE548B939A80edbc9B2256d0cdc003;
    address constant JR_USDe = 0xC58D044404d8B14e953C115E67823784dEA53d8F;

    // Chainlink USDe/USD feed on Ethereum mainnet
    address constant USDE_USD_FEED = 0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        // Deploy CDOLens behind a proxy
        CDOLens impl = new CDOLens();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(CDOLens.initialize.selector, address(this))
        );
        lens = CDOLens(address(proxy));

        // Configure the Chainlink feed for USDe
        lens.setPriceFeed(USDe, IChainlinkPriceFeed(USDE_USD_FEED));
    }

    function test_getPrice_srUSDe() public view {
        uint256 price = lens.getPrice(IERC4626(SR_USDe));
        console2.log("srUSDe USD price (18 dec):", price);
        assertGt(price, 0, "srUSDe price should be > 0");
    }

    function test_getPrice_jrUSDe() public view {
        uint256 price = lens.getPrice(IERC4626(JR_USDe));
        console2.log("jrUSDe USD price (18 dec):", price);
        assertGt(price, 0, "jrUSDe price should be > 0");
    }

    function test_getPrice_reverts_without_feed() public {
        address randomVault = address(0xdead);
        vm.expectRevert("Price feed not set");
        lens.getPrice(IERC4626(randomVault));
    }
}
