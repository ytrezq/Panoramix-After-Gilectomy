// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILocker {
    // ----------- Events -----------
    event OperatorUpdated(address operator);
    event Executed(address indexed caller, address indexed to);

    // ----------- View Functions -----------
    function TOKEN() external view returns (address);
    function escrow() external view returns (address);
    function operator() external view returns (address);
    function owner() external view returns (address);
    function INCREASE_AMOUNT_SELECTOR() external view returns (bytes4);

    // ----------- Write Functions -----------
    function setOperator(address _operator) external;

    function safeExecute(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external returns (bool success, bytes memory result);

    function execute(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external returns (bool success, bytes memory result);

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}