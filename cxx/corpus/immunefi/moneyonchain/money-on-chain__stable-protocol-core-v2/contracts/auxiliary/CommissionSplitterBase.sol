// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { Governed } from "../governance/Governed.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
  @dev Contract that split his balance between two addresses based on a
  proportion defined by Governance.
 */
abstract contract CommissionSplitterBase is Governed, UUPSUpgradeable {
    // ------- Events -------

    event SplitExecuted(
        uint256 acTokenPctToRecipient1_,
        uint256 acTokenPctToRecipient2_,
        uint256 feeTokenPctToRecipient1_,
        uint256 feeTokenPctToRecipient2_
    );

    // ------- Storage -------

    // fee token
    IERC20 public feeToken;

    // address who receives acTokenPctToRecipient1
    address public acTokenAddressRecipient1;
    // address who receives the rest of the commissions (100% - acTokenPctToRecipient1)
    address public acTokenAddressRecipient2;
    // percentage of the acToken balance to send to acTokenAddressRecipient1 [PREC]
    uint256 public acTokenPctToRecipient1;

    // address who receives feeTokenPctToRecipient1
    address public feeTokenAddressRecipient1;
    // address who receives the rest of the commissions (100% - feeTokenPctToRecipient1)
    address public feeTokenAddressRecipient2;
    // percentage of the feeToken balance to send to acTokenAddressRecipient1 [PREC]
    uint256 public feeTokenPctToRecipient1;

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
    function __CommissionSplitter_init(
        address governorAddress_,
        IERC20 feeToken_,
        address acTokenAddressRecipient1_,
        address acTokenAddressRecipient2_,
        uint256 acTokenPctToRecipient1_,
        address feeTokenAddressRecipient1_,
        address feeTokenAddressRecipient2_,
        uint256 feeTokenPctToRecipient1_
    ) internal onlyInitializing {
        if (acTokenPctToRecipient1_ > PRECISION) revert InvalidValue();
        if (feeTokenPctToRecipient1_ > PRECISION) revert InvalidValue();
        __UUPSUpgradeable_init();
        __Governed_init(governorAddress_);

        feeToken = feeToken_;
        acTokenAddressRecipient1 = acTokenAddressRecipient1_;
        acTokenAddressRecipient2 = acTokenAddressRecipient2_;
        acTokenPctToRecipient1 = acTokenPctToRecipient1_;
        feeTokenAddressRecipient1 = feeTokenAddressRecipient1_;
        feeTokenAddressRecipient2 = feeTokenAddressRecipient2_;
        feeTokenPctToRecipient1 = feeTokenPctToRecipient1_;
    }

    // ------- Internal abstract Functions -------

    /**
     * @notice get the AC balance of the contract
     * @dev this function must be overridden by the AC implementation
     * @return balance of the contract
     */
    function _acBalanceOfSelf() internal view virtual returns (uint256);

    /**
     * @notice transfers AC to a recipient
     * @dev this function must be overridden by the AC implementation
     *  and revert if transfer fails.
     * @param recipient_ recipient address
     * @param amount_ amount to transfer
     */
    function _acTransfer(address recipient_, uint256 amount_) internal virtual;

    // ------- External Functions -------

    /**
     * @notice splits all the acToken and feeToken balances to the recipients addresses
     */
    function split() external {
        uint256 acTokenAmountToRecipient1;
        uint256 acTokenAmountToRecipient2;
        uint256 feeTokenAmountToRecipient1;
        uint256 feeTokenAmountToRecipient2;

        // splits collateral asset
        uint256 acTokenBalance = _acBalanceOfSelf();
        if (acTokenBalance > 0) {
            acTokenAmountToRecipient1 = _mulPrec(acTokenBalance, acTokenPctToRecipient1);
            acTokenAmountToRecipient2 = acTokenBalance - acTokenAmountToRecipient1;
            _acTransfer(acTokenAddressRecipient1, acTokenAmountToRecipient1);
            _acTransfer(acTokenAddressRecipient2, acTokenAmountToRecipient2);
        }

        // splits fee token
        uint256 feeTokenBalance = feeToken.balanceOf(address(this));
        if (feeTokenBalance > 0) {
            feeTokenAmountToRecipient1 = _mulPrec(feeTokenBalance, feeTokenPctToRecipient1);
            feeTokenAmountToRecipient2 = feeTokenBalance - feeTokenAmountToRecipient1;
            SafeERC20.safeTransfer(feeToken, feeTokenAddressRecipient1, feeTokenAmountToRecipient1);
            SafeERC20.safeTransfer(feeToken, feeTokenAddressRecipient2, feeTokenAmountToRecipient2);
        }

        emit SplitExecuted(
            acTokenAmountToRecipient1,
            acTokenAmountToRecipient2,
            feeTokenAmountToRecipient1,
            feeTokenAmountToRecipient2
        );
    }

    // ------- Only Authorized Changer Functions -------

    /** @notice sets new fee token
     * @param newFeeToken_ new fee token contract
     */
    function setFeeToken(IERC20 newFeeToken_) external onlyAuthorizedChanger {
        feeToken = newFeeToken_;
    }

    /** @notice sets new recipient1 for AC token
     * @param acTokenAddressRecipient1_ new recipient1 address
     */
    function setAcTokenAddressRecipient1(address acTokenAddressRecipient1_) external onlyAuthorizedChanger {
        acTokenAddressRecipient1 = acTokenAddressRecipient1_;
    }

    /** @notice sets new recipient2 for AC token
     * @param acTokenAddressRecipient2_ new recipient1 address
     */
    function setAcTokenAddressRecipient2(address acTokenAddressRecipient2_) external onlyAuthorizedChanger {
        acTokenAddressRecipient2 = acTokenAddressRecipient2_;
    }

    /** @notice sets new percentage of AC token for recipient1
     * @param acTokenPctToRecipient1_ new percentage for recipient1 [PREC]
     */
    function setAcTokenPctToRecipient1(uint256 acTokenPctToRecipient1_) external onlyAuthorizedChanger {
        if (acTokenPctToRecipient1_ > PRECISION) revert InvalidValue();
        acTokenPctToRecipient1 = acTokenPctToRecipient1_;
    }

    /** @notice sets new recipient1 for fee token
     * @param feeTokenAddressRecipient1_ new recipient1 address
     */
    function setFeeTokenAddressRecipient1(address feeTokenAddressRecipient1_) external onlyAuthorizedChanger {
        feeTokenAddressRecipient1 = feeTokenAddressRecipient1_;
    }

    /** @notice sets new recipient2 for fee token
     * @param feeTokenAddressRecipient2_ new recipient2 address
     */
    function setFeeTokenAddressRecipient2(address feeTokenAddressRecipient2_) external onlyAuthorizedChanger {
        feeTokenAddressRecipient2 = feeTokenAddressRecipient2_;
    }

    /** @notice sets new percentage of fee token for recipient1
     * @param feeTokenPctToRecipient1_ new percentage for recipient1 [PREC]
     */
    function setFeeTokenPctToRecipient1(uint256 feeTokenPctToRecipient1_) external onlyAuthorizedChanger {
        if (feeTokenPctToRecipient1_ > PRECISION) revert InvalidValue();
        feeTokenPctToRecipient1 = feeTokenPctToRecipient1_;
    }

    /**
     * @inheritdoc UUPSUpgradeable
     * @dev checks that the changer that will do the upgrade is currently authorized by governance to makes
     * changes within the system
     * @param newImplementation new implementation contract address(not used)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyAuthorizedChanger {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */

    // Purposely left unused to save some state space to allow for future upgrades
    // slither-disable-next-line unused-state
    uint256[50] private __gap;
}
