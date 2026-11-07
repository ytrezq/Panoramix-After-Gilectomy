// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IHook} from "../../src/interface/IHook.sol";

contract StandardHookV1Mock is IHook {
    error NotImplemented();
    error DepositLimitExceeded(uint256 assets, uint256 depositLimit);
    error NotOwner();

    uint256 public depositLimit;

    constructor(uint256 _depositLimit) {
        depositLimit = _depositLimit;
    }

    // USER ACTION HOOKS

    function preDeposit(
        address,
        /* sender */
        uint256 assets,
        address,
        /* receiver */
        uint256 /* totalAssets */
    )
        external
        view
    {
        if (assets > depositLimit) revert DepositLimitExceeded(assets, depositLimit);
    }

    function preMint(
        address,
        /* sender */
        uint256,
        /* shares */
        address,
        /* receiver */
        uint256 /* totalAssets */
    )
        external
        pure
    {
        // call the sender
        revert NotImplemented();
    }

    function preWithdraw(
        address sender,
        uint256, /* assets */
        address, /* receiver */
        address owner,
        uint256 /* totalAssets */
    )
        external
        pure
    {
        // check sender is owner
        if (sender != owner) revert NotOwner();
    }

    function preRedeem(
        address sender,
        uint256, /* shares */
        address, /* receiver */
        address owner,
        uint256 /* totalAssets */
    )
        external
        pure
    {
        // check sender is owner
        if (sender != owner) revert NotOwner();
    }

    function postDeposit(
        address, /* sender */
        uint256, /* assets */
        uint256, /* shares */
        address, /* receiver */
        uint256 /* totalAssets */
    )
        external
        pure
    {
        // not implemented
        revert NotImplemented();
    }

    function postMint(
        address, /* sender */
        uint256 assets,
        uint256, /* shares */
        address, /* receiver */
        uint256 /* totalAssets */
    )
        external
        view
    {
        // check deposit limit
        if (assets > depositLimit) revert DepositLimitExceeded(assets, depositLimit);
    }

    function postWithdraw(
        address, /* sender */
        uint256, /* assets */
        uint256, /* shares */
        address, /* receiver */
        uint256 /* totalAssets */
    )
        external
        pure
    {
        // not implemented
        revert NotImplemented();
    }

    function postRedeem(
        address, /* sender */
        uint256, /* assets */
        uint256, /* shares */
        address, /* receiver */
        uint256 /* totalAssets */
    )
        external
        pure
    {
        // not implemented
        revert NotImplemented();
    }
}
