// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MultiCall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {IRWAFactory} from "./base/IRWAFactory.sol";
import {ISecuritizeDegenNFT} from "./ISecuritizeDegenNFT.sol";

interface ISecuritizeRWAFactory is IRWAFactory {
    // ------ //
    // ERRORS //
    // ------ //

    error InvalidCreditManagerException(address creditManager);
    error InvalidUnderlyingTokenException(address underlying);
    error TooManyCreditAccountsException(address investor);
    error ZeroAddressException();

    // ------- //
    // GETTERS //
    // ------- //

    function getDegenNFT() external view returns (address);

    // ------------ //
    // USER ACTIONS //
    // ------------ //

    function precomputeWalletAddress(address creditManager, address investor) external view returns (address);
    function openCreditAccount(
        address creditManager,
        MultiCall[] calldata calls,
        address[] calldata tokensToRegister,
        ISecuritizeDegenNFT.RegisterMessage[] calldata signaturesToCache
    ) external returns (address creditAccount, address wallet);
    function multicall(
        address creditAccount,
        MultiCall[] calldata calls,
        address[] calldata tokensToRegister,
        ISecuritizeDegenNFT.RegisterMessage[] calldata signaturesToCache
    ) external;
}
