// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICreditFacadeV3, MultiCall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {ICreditFacadeV3Multicall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3Multicall.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";

import {ISecuritizeRWAFactory} from "../interfaces/ISecuritizeRWAFactory.sol";
import {ISecuritizeWallet} from "../interfaces/ISecuritizeWallet.sol";
import {IRWAUnderlying} from "../interfaces/base/IRWAUnderlying.sol";

/// @title  Securitize Wallet
/// @author Gearbox Foundation
/// @notice A simple wallet contract that owns a credit account and allows investor to interact with it,
///         while also allowing Securitize to enforce compliance
contract SecuritizeWallet is ISecuritizeWallet {
    using SafeERC20 for ERC20;

    ISecuritizeRWAFactory internal immutable _FACTORY;
    IRWAUnderlying internal immutable _UNDERLYING;
    ICreditManagerV3 internal immutable _CREDIT_MANAGER;
    address internal immutable _CREDIT_ACCOUNT;

    modifier onlyFactory() {
        if (msg.sender != address(_FACTORY)) revert CallerIsNotFactoryException(msg.sender);
        _;
    }

    modifier onlyInvestor() {
        if (msg.sender != getInvestor()) revert CallerIsNotInvestorException(msg.sender, _CREDIT_ACCOUNT);
        _;
    }

    constructor(ISecuritizeRWAFactory factory, ICreditManagerV3 creditManager) {
        _FACTORY = factory;
        _UNDERLYING = IRWAUnderlying(creditManager.underlying());
        _CREDIT_MANAGER = creditManager;
        _CREDIT_ACCOUNT = _creditFacade().openCreditAccount(address(this), new MultiCall[](0), 0);
    }

    function getFactory() external view override returns (address) {
        return address(_FACTORY);
    }

    function getUnderlying() external view override returns (address) {
        return address(_UNDERLYING);
    }

    function getCreditManager() external view override returns (address) {
        return address(_CREDIT_MANAGER);
    }

    function getCreditAccount() external view override returns (address) {
        return _CREDIT_ACCOUNT;
    }

    function getInvestor() public view override returns (address) {
        return _FACTORY.getInvestor(_CREDIT_ACCOUNT);
    }

    function multicall(MultiCall[] calldata calls) external override onlyFactory {
        address investor = getInvestor();
        uint256 length = calls.length;
        for (uint256 i; i < length; ++i) {
            if (bytes4(calls[i].callData[:4]) == ICreditFacadeV3Multicall.addCollateral.selector) {
                (address token, uint256 amount) = abi.decode(calls[i].callData[4:], (address, uint256));
                _addCollateral(token, investor, amount);
            } else if (bytes4(calls[i].callData[:4]) == ICreditFacadeV3Multicall.addCollateralWithPermit.selector) {
                (address token, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
                    abi.decode(calls[i].callData[4:], (address, uint256, uint256, uint8, bytes32, bytes32));
                try IERC20Permit(token).permit(investor, address(this), amount, deadline, v, r, s) {} catch {}
                _addCollateral(token, investor, amount);
            } else if (bytes4(calls[i].callData[:4]) == ICreditFacadeV3Multicall.increaseDebt.selector) {
                uint256 amount = abi.decode(calls[i].callData[4:], (uint256));
                _UNDERLYING.beforeTokenBorrow(_CREDIT_ACCOUNT, amount);
            } else if (bytes4(calls[i].callData[:4]) == ICreditFacadeV3Multicall.setBotPermissions.selector) {
                revert ForbiddenCallException();
            }
        }
        _creditFacade().multicall(_CREDIT_ACCOUNT, calls);
    }

    function rescueToken(address token, address to) external override onlyInvestor {
        ERC20(token).safeTransfer(to, ERC20(token).balanceOf(address(this)));
    }

    function _addCollateral(address token, address investor, uint256 amount) internal {
        ERC20(token).safeTransferFrom(investor, address(this), amount);
        ERC20(token).forceApprove(address(_CREDIT_MANAGER), amount);
    }

    function _creditFacade() internal view returns (ICreditFacadeV3) {
        return ICreditFacadeV3(_CREDIT_MANAGER.creditFacade());
    }
}
