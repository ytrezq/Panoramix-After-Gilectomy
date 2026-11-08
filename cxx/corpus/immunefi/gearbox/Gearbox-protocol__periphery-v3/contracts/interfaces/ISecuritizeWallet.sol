// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MultiCall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";

interface ISecuritizeWallet {
    // ------ //
    // ERRORS //
    // ------ //

    error CallerIsNotFactoryException(address caller);
    error CallerIsNotInvestorException(address caller, address creditAccount);
    error ForbiddenCallException();

    // ------- //
    // GETTERS //
    // ------- //

    function getFactory() external view returns (address);
    function getCreditManager() external view returns (address);
    function getCreditAccount() external view returns (address);
    function getUnderlying() external view returns (address);
    function getInvestor() external view returns (address);

    // ------------ //
    // USER ACTIONS //
    // ------------ //

    function multicall(MultiCall[] calldata calls) external;
    function rescueToken(address token, address to) external;
}
