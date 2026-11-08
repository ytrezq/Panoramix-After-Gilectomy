// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CommissionSplitterBase } from "./CommissionSplitterBase.sol";

/**
  @dev Contract that split his balance between two addresses based on a
  proportion defined by Governance.
 */
contract CommissionSplitterCoinbase is CommissionSplitterBase {
    // ------- Custom Errors -------
    error TransferFailed();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ------- Initializer -------

    /**
     * @notice contract initializer
     * @param governorAddress_ governor address
     * @param feeToken_ fee token contract
     * @param acTokenAddressRecipient1_ address who receives acTokenPctToRecipient1
     * @param acTokenAddressRecipient2_ address who receives (100% - acTokenPctToRecipient1)
     * @param acTokenPctToRecipient1_ percentage of the acToken balance to send to acTokenAddressRecipient1 [PREC]
     * @param feeTokenAddressRecipient1_ address who receives feeTokenPctToRecipient1
     * @param feeTokenAddressRecipient2_ address who receives (100% - feeTokenPctToRecipient1)
     * @param feeTokenPctToRecipient1_ percentage of the feeToken balance to send to acTokenAddressRecipient1 [PREC]
     */
    // slither-disable missing-zero-check
    function initialize(
        address governorAddress_,
        IERC20 feeToken_,
        address acTokenAddressRecipient1_,
        address acTokenAddressRecipient2_,
        uint256 acTokenPctToRecipient1_,
        address feeTokenAddressRecipient1_,
        address feeTokenAddressRecipient2_,
        uint256 feeTokenPctToRecipient1_
    ) external initializer {
        __CommissionSplitter_init(
            governorAddress_,
            feeToken_,
            acTokenAddressRecipient1_,
            acTokenAddressRecipient2_,
            acTokenPctToRecipient1_,
            feeTokenAddressRecipient1_,
            feeTokenAddressRecipient2_,
            feeTokenPctToRecipient1_
        );
    }

    // ------- Internal Functions -------

    /**
     * @notice get the AC balance of the contract
     * @return balance of the contract
     */
    function _acBalanceOfSelf() internal view override returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice transfers AC to a recipient
     * @param recipient_ recipient address
     * @param amount_ amount to transfer
     */
    function _acTransfer(address recipient_, uint256 amount_) internal override {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = recipient_.call{ value: amount_ }("");
        if (!success) revert TransferFailed();
    }

    // receive coinbase to split the commissions
    receive() external payable {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */

    // Purposely left unused to save some state space to allow for future upgrades
    // slither-disable-next-line unused-state
    uint256[50] private __gap;
}
