// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IDSRegistryService {
    // ------------- //
    // ATTRIBUTE IDS //
    // ------------- //

    function NONE() external view returns (uint8);
    function KYC_APPROVED() external view returns (uint8);
    function ACCREDITED() external view returns (uint8);
    function QUALIFIED() external view returns (uint8);
    function PROFESSIONAL() external view returns (uint8);

    // ---------------- //
    // ATTRIBUTE VALUES //
    // ---------------- //

    function PENDING() external view returns (uint8);
    function APPROVED() external view returns (uint8);
    function REJECTED() external view returns (uint8);

    // ------- //
    // GETTERS //
    // ------- //

    function isInvestor(string calldata investorId) external view returns (bool);
    function getInvestor(address wallet) external view returns (string memory);
    function isWallet(address wallet) external view returns (bool);

    // ------- //
    // ACTIONS //
    // ------- //

    function registerInvestor(string calldata investorId, string calldata collisionHash) external;
    function addWallet(address wallet, string calldata investorId) external;
    function setCountry(string calldata investorId, string calldata country) external;
    function setAttribute(
        string calldata investorId,
        uint8 attributeId,
        uint256 value,
        uint256 expiry,
        string calldata proof
    ) external;
}
