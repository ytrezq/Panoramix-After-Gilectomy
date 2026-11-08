
pragma solidity ^0.8.4;

// Pulled from https://etherscan.io/address/0xA188EEC8F81263234dA3622A406892F3D630f98c#code
interface PsmLike {
    function psm() external view returns (address);
    function gem() external view returns (address);
    function vat() external view returns (address);
    function daiJoin() external view returns (address);
    function pocket() external view returns (address);
    function tin() external view returns (uint256);
    function tout() external view returns (uint256);
    function buf() external view returns (uint256);
    function sellGem(address, uint256) external returns (uint256);
    function buyGem(address, uint256) external returns (uint256);
    function ilk() external view returns (bytes32);
    function vow() external view returns (address);
}