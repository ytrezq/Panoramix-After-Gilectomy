// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IListaDAO {
    function locked(address token, address usr) external view returns (uint256);
}
