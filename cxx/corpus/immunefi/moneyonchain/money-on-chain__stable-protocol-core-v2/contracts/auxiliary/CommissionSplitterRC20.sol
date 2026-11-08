// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { CommissionSplitterBase } from "./CommissionSplitterBase.sol";

/**
  @dev Contract that split his balance between two addresses based on a
  proportion defined by Governance.
 */
contract CommissionSplitterRC20 is CommissionSplitterBase {
    // ------- Storage -------

    // collateral asset
    IERC20 public acToken;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ------- Initializer -------

    /**
     * @notice contract initializer
     * @param acToken_ collateral asset contract. Address(0) for coinbase
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
        IERC20 acToken_,
        address governorAddress_,
        IERC20 feeToken_,
        address acTokenAddressRecipient1_,
        address acTokenAddressRecipient2_,
        uint256 acTokenPctToRecipient1_,
        address feeTokenAddressRecipient1_,
        address feeTokenAddressRecipient2_,
        uint256 feeTokenPctToRecipient1_
    ) external initializer {
        acToken = acToken_;
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
        return acToken.balanceOf(address(this));
    }

    /**
     * @notice transfers AC to a recipient
     * @param recipient_ recipient address
     * @param amount_ amount to transfer
     */
    function _acTransfer(address recipient_, uint256 amount_) internal override {
        SafeERC20.safeTransfer(acToken, recipient_, amount_);
    }

    // ------- Only Authorized Changer Functions -------

    /** @notice sets new AC token. Address(0) for coinbase
     * @param newAcToken_ new AC token contract. Address(0) for coinbase
     */
    function setAcToken(IERC20 newAcToken_) external onlyAuthorizedChanger {
        acToken = newAcToken_;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */

    // Purposely left unused to save some state space to allow for future upgrades
    // slither-disable-next-line unused-state
    uint256[50] private __gap;
}
