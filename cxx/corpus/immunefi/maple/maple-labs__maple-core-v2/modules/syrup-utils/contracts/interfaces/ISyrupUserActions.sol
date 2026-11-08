// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface ISyrupUserActions {

    /**************************************************************************************************************************************/
    /*** Events                                                                                                                         ***/
    /**************************************************************************************************************************************/

    /**
     *  @dev   Emitted when a swap occurs.
     *  @param  owner     The address of the user that initiated the swap.
     *  @param  receiver  The address that received the swapped tokens.
     *  @param  tokenIn   The address of the token being swapped.
     *  @param  amountIn  The amount of the token being swapped.
     *  @param  tokenOut  The address of the token received.
     *  @param  amountOut The amount of the token received.
     */
    event Swap(address indexed owner, address indexed receiver, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);

    /**************************************************************************************************************************************/
    /*** State-Changing Functions                                                                                                       ***/
    /**************************************************************************************************************************************/

    /**
     *  @dev    Swaps SyrupUSDC LP token for DAI in a single transaction.
     *  @param  syrupUsdcIn  The amount of SyrupUSDC to swap.
     *  @param  minDaiOut    The minimum amount of DAI to receive.
     *  @param  swapDeadline The deadline for the swap.
     *  @param  receiver     The address to receive the DAI.
     *  @return daiOut       The amount of DAI received.
     */
    function swapToDai(uint256 syrupUsdcIn, uint256 minDaiOut, uint256 swapDeadline, address receiver) external returns (uint256 daiOut);

    /**
     *  @dev    Swaps SyrupUSDC LP token for DAI in a single transaction with permit.
     *  @param  syrupUsdcIn    The amount of SyrupUSDC to swap.
     *  @param  minDaiOut      The minimum amount of DAI to receive.
     *  @param  swapDeadline   The deadline for the swap.
     *  @param  receiver       The address to receive the DAI.
     *  @param  permitDeadline The deadline for the permit.
     *  @param  v              The v value of the permit signature.
     *  @param  r              The r value of the permit signature.
     *  @param  s              The s value of the permit signature.
     *  @return daiOut         The amount of DAI received.
     */
    function swapToDaiWithPermit(
        uint256 syrupUsdcIn,
        uint256 minDaiOut,
        uint256 swapDeadline,
        address receiver,
        uint256 permitDeadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 daiOut);

    /**
     *  @dev    Swaps SyrupUSDC LP token for USDC in a single transaction.
     *  @param  syrupUsdcIn  The amount of SyrupUSDC to swap.
     *  @param  minUsdcOut   The minimum amount of USDC to receive.
     *  @param  swapDeadline The deadline for the swap.
     *  @param  receiver     The address to receive the USDC.
     *  @return usdcOut      The amount of USDC received.
     */
    function swapToUsdc(uint256 syrupUsdcIn, uint256 minUsdcOut, uint256 swapDeadline, address receiver) external returns (uint256 usdcOut);

    /**
     *  @dev    Swaps SyrupUSDC LP token for USDC in a single transaction with permit.
     *  @param  syrupUsdcIn    The amount of SyrupUSDC to swap.
     *  @param  minUsdcOut     The minimum amount of USDC to receive.
     *  @param  swapDeadline   The deadline for the swap.
     *  @param  receiver       The address to receive the USDC.
     *  @param  permitDeadline The deadline for the permit.
     *  @param  v              The v value of the permit signature.
     *  @param  r              The r value of the permit signature.
     *  @param  s              The s value of the permit signature.
     *  @return usdcOut        The amount of USDC received.
     */
    function swapToUsdcWithPermit(
        uint256 syrupUsdcIn,
        uint256 minUsdcOut,
        uint256 swapDeadline,
        address receiver,
        uint256 permitDeadline,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 usdcOut);

    /**************************************************************************************************************************************/
    /*** View Functions                                                                                                                 ***/
    /**************************************************************************************************************************************/

    /**
     *  @dev    Returns the address of the Balancer Vault used for swapping.
     *  @return balVault The address of the Balancer Vault.
     */
    function BAL_VAULT() external view returns (address balVault);

    /**
     *  @dev    Returns the address of the DAI token.
     *  @return dai The address of the DAI token.
     */
    function dai() external view returns (address dai);

    /**
     *  @dev    Returns the id of the Balancer Pool used for swapping.
     *  @return poolId The id of the Balancer Pool.
     */
    function poolId() external view returns (bytes32 poolId);

    /**
     *  @dev    Returns the precision of the PSM contract.
     *  @return psmPrecision The precision of the PSM contract.
     */
    function PSM_PRECISION() external view returns (uint256 psmPrecision);

    /**
     *  @dev    Returns the address of the PSM contract.
     *  @return psm The address of the PSM contract.
     */
    function psm() external view returns (address psm);

    /**
     *  @dev    Returns the address of the SyrupUSDC LP token.
     *  @return syrupUsdc The address of the SyrupUSDC LP token.
     */
    function syrupUsdc() external view returns (address syrupUsdc);

    /**
     *  @dev    Returns the address of the USDC token.
     *  @return usdc The address of the USDC token.
     */
    function USDC() external view returns (address usdc);

    /**
     *  @dev    Returns the address of the sDAI token.
     *  @return sDai The address of the sDAI token.
     */
    function sDai() external view returns (address sDai);

}
