// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./PendleMellowVaultSYBaseV2Upg.sol";

contract PendleMellowSUSDESY is PendleMellowVaultSYBaseV2Upg {
    error MellowVaultHasInvalidAssets();
    error SupplyCapExceeded(uint256 totalSupply, uint256 supplyCap);

    using PMath for uint256;

    // solhint-disable immutable-vars-naming
    address public immutable erc4626;
    address public immutable erc4626Asset;

    constructor(address _erc4626, address _vault) PendleMellowVaultSYBaseV2Upg(_vault) {
        erc4626 = _erc4626;
        erc4626Asset = IERC4626(_erc4626).asset();
    }

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == erc4626Asset) {
            (tokenIn, amountDeposited) = (erc4626, IERC4626(erc4626).deposit(amountDeposited, address(this)));
        }
        return super._deposit(tokenIn, amountDeposited);
    }

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == erc4626Asset) {
            (tokenIn, amountTokenToDeposit) = (erc4626, IERC4626(erc4626).previewDeposit(amountTokenToDeposit));
        }
        return super._previewDeposit(tokenIn, amountTokenToDeposit);
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        return ArrayLib.create(erc4626Asset, erc4626, vault);
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == erc4626Asset || token == erc4626 || token == vault;
    }

    function assetInfo()
        external
        view
        virtual
        override
        returns (AssetType assetType, address assetAddress, uint8 assetDecimals)
    {
        return (AssetType.TOKEN, erc4626Asset, IERC20Metadata(erc4626Asset).decimals());
    }

    function exchangeRate() public view virtual override returns (uint256 res) {
        return IERC4626(erc4626).convertToAssets(IERC4626(vault).convertToAssets(PMath.ONE));
    }
}
