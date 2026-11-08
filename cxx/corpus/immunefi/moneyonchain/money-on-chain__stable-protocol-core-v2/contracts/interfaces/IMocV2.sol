// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

interface IMocV2 {
    /**
     * @notice GLOBAL Coverage
     * @return [PREC]
     */
    function getCglb() external view returns (uint256);

    /**
     * @notice Target coverage for complete system
     * @return [PREC]
     */
    function calcCtargemaCA() external view returns (uint256);

    /**
     * @notice Amount of AC in the system
     * @return [N]
     */
    function getTotalACavailable() external view returns (uint256);

    /**
     * @notice get amount of Pegged Token minted and price provider
     */
    function pegContainer(uint256 i_) external view returns (uint256, address);

    /**
     * @notice get locked AC
     * @return [N]
     */
    function getLckAC() external view returns (uint256);

    /**
     * @notice get amount of Pegged Tokens
     */
    function getTpAmount() external view returns (uint256);

    /**
     * @notice get Pegged Token address
     */
    function tpTokens(uint256 i_) external view returns (address);
}
