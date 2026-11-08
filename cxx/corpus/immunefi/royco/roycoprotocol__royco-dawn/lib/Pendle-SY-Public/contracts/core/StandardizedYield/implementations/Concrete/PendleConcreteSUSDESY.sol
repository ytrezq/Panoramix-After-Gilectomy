// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "./PendleConcreteVaultSY.sol";

// @note: Concrete vault has 27 decimals !!!
contract PendleConcreteSUSDESY is PendleConcreteVaultSY {
    using PMath for uint256;

    // asset = SUSDE
    // yieldToken = concrete vault
    address public constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address public constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;

    constructor(address _concreteVault) PendleConcreteVaultSY(_concreteVault) {}

    function initialize(string memory _name, string memory _symbol) external virtual override initializer {
        __SYBaseUpg_init(_name, _symbol);
        _safeApproveInf(USDE, SUSDE);
        _safeApproveInf(SUSDE, yieldToken);
    }

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == yieldToken) {
            return amountDeposited;
        } else {
            if (tokenIn == USDE) {
                amountDeposited = IERC4626(SUSDE).deposit(amountDeposited, address(this));
            }
            return IERC4626(yieldToken).deposit(amountDeposited, address(this));
        }
    }

    function exchangeRate() public view virtual override returns (uint256) {
        return IERC4626(yieldToken).convertToAssets(PMath.ONE).mulDown(IERC4626(SUSDE).convertToAssets(PMath.ONE));
    }

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == yieldToken) return amountTokenToDeposit;
        else {
            if (tokenIn == USDE) amountTokenToDeposit = IERC4626(SUSDE).previewDeposit(amountTokenToDeposit);
            return IERC4626(yieldToken).previewDeposit(amountTokenToDeposit);
        }
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](3);
        res[0] = USDE;
        res[1] = SUSDE;
        res[2] = yieldToken;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == USDE || token == yieldToken || token == SUSDE;
    }

    function assetInfo()
        external
        view
        virtual
        override
        returns (AssetType assetType, address assetAddress, uint8 assetDecimals)
    {
        return (AssetType.TOKEN, USDE, IERC20Metadata(USDE).decimals());
    }
}
