// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../PendleERC20SYUpg.sol";
import "../../../../interfaces/Stone/IStoneVault.sol";
import "../../../../interfaces/Stone/IStoneBeraVault.sol";
import "../../../../interfaces/IPTokenWithSupplyCap.sol";

contract PendleBeraStoneVaultSY is PendleERC20SYUpg, IPTokenWithSupplyCap {
    using PMath for uint256;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public constant STONE = 0x7122985656e38BDC0302Db86685bb972b145bD3C;
    address public constant STONE_VAULT = 0xA62F9C5af106FeEE069F38dE51098D9d81B90572;

    address public constant BERA_STONE = 0x97Ad75064b20fb2B2447feD4fa953bF7F007a706;
    address public constant BERA_STONE_VAULT = 0x8f88aE3798E8fF3D0e0DE7465A0863C9bbB577f0;

    constructor() PendleERC20SYUpg(BERA_STONE) {}

    function initialize(string memory _name, string memory _symbol) external virtual override initializer {
        __SYBaseUpg_init(_name, _symbol);
        _safeApproveInf(WETH, BERA_STONE_VAULT);
        _safeApproveInf(STONE, BERA_STONE_VAULT);
    }

    /**
     * Deposit route:
     * - WETH -> beraSTONE
     * - ETH -> STONE -> beraSTONE
     * - STONE -> beraSTONE
     *
     * This is to make deposit routing can still even if STONE pauses WETH deposit to beraSTONE
     */
    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == BERA_STONE) {
            return amountDeposited;
        }

        if (tokenIn == NATIVE) {
            (tokenIn, amountDeposited) = (STONE, IStoneVault(STONE_VAULT).deposit{value: amountDeposited}());
        }
        return IStoneBeraVault(BERA_STONE_VAULT).deposit(tokenIn, amountDeposited, address(this));
    }

    // For ETH Deposit, this function would not be 100% accurate due to the delay in the share price (taking prior round's price)
    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == BERA_STONE) {
            return amountTokenToDeposit;
        }

        if (tokenIn == NATIVE) {
            // Ensure rID > 1 at deployment
            uint256 rID = IStoneVault(STONE_VAULT).latestRoundID() - 1;
            uint256 price = IStoneVault(STONE_VAULT).roundPricePerShare(rID);
            (tokenIn, amountTokenToDeposit) = (STONE, amountTokenToDeposit.divDown(price));
        }
        return IStoneBeraVault(BERA_STONE_VAULT).previewDeposit(tokenIn, amountTokenToDeposit);
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        return ArrayLib.create(NATIVE, WETH, STONE, BERA_STONE);
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == NATIVE || token == WETH || token == STONE || token == BERA_STONE;
    }

    function getAbsoluteSupplyCap() external view returns (uint256) {
        return IStoneBeraVault(BERA_STONE_VAULT).cap();
    }

    function getAbsoluteTotalSupply() external view returns (uint256) {
        return IERC20(yieldToken).totalSupply();
    }
}
