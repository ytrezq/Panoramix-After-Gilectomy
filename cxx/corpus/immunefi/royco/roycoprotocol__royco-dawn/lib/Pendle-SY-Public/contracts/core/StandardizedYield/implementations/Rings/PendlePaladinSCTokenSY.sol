// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import "../PendleERC4626UpgSYV2.sol";
import "../../../../interfaces/EtherFi/IVedaTeller.sol";
import "../../../../interfaces/Paladin/IPaladinWrapper.sol";

contract PendlePaladinSCTokenSY is PendleERC4626UpgSYV2 {
    address public immutable rawToken;
    address public immutable tellerSc;
    address public immutable scToken;
    address public immutable tellerStk;

    constructor(address _rawToken, address _tellerSc, address _wscToken) PendleERC4626UpgSYV2(_wscToken) {
        rawToken = _rawToken;
        tellerSc = _tellerSc;
        scToken = IVedaTeller(tellerSc).vault();
        tellerStk = IPaladinWrapper(yieldToken).teller();
    }

    function initialize(string memory _name, string memory _symbol) external override initializer {
        __SYBaseUpg_init(_name, _symbol);
        _safeApproveInf(rawToken, scToken);
        _safeApproveInf(scToken, asset);
        _safeApproveInf(asset, yieldToken);
    }

    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        if (tokenIn == rawToken) {
            (tokenIn, amountDeposited) = (scToken, IVedaTeller(tellerSc).deposit(rawToken, amountDeposited, 0));
        }
        if (tokenIn == scToken) {
            (tokenIn, amountDeposited) = (asset, IVedaTeller(tellerStk).deposit(scToken, amountDeposited, 0));
        }
        return super._deposit(tokenIn, amountDeposited);
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        return ArrayLib.create(rawToken, scToken, asset, yieldToken);
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == rawToken || token == scToken || token == yieldToken || token == asset;
    }
}
