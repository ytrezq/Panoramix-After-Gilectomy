// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IOFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";

/// @title IBridgeableTokenP
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Interface for the canonical `TokenP` contracts
/// @dev This interface only contains functions useful for bridge tokens to interact with the canonical token
interface IBridgeableTokenP is IOFT {
    /// @notice Allow user to swap Lz token (OFT) to principalToken if the amount is within the mint limit.
    /// @dev when the user swap OFT token to principalToken, the OFT token will be burned and the principalToken will be
    /// minted to the user.
    /// @param _to The address to credit the principalToken to.
    /// @param _amount The amount of OFT token to swap.
    /// @return The amount of principalToken actually minted.
    function swapLzTokenToPrincipalToken(address _to, uint256 _amount) external returns(uint256);
}
