// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { Governed, IGovernor } from "../governance/Governed.sol";
import { IRatioSource } from "../interfaces/IRatioSource.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MocTokenAllocator
 * @notice This contract is used to split the balance of the contract using the criteria provided by the ratio source.
 */
contract MocTokenAllocator is Governed, ReentrancyGuard, IRatioSource {
    address private constant COINBASE = address(0);
    // ------- Events -------
    event SplitExecuted(address token_, address[] recipients_, uint256[] amounts_);
    event EmergencyWithdraw(address token_, address to_, uint256 amount_);
    // ------- Custom Errors -------
    error TransferFailed();

    // ------- Storage -------

    // source of the ratio and addresses to distribute the tokens
    IRatioSource public ratioSource;

    /**
     * @notice constructor
     * @param governor_ address of the governor contract
     * @param ratioSource_ address of the ratio source contract
     */
    constructor(address governor_, address ratioSource_) {
        _disableInitializers();
        governor = IGovernor(governor_);
        ratioSource = IRatioSource(ratioSource_);
    }

    /**
     *@notice transfer tokens to the given address
     *@param token_ address of the token to be transferred
     *@param to_ address of the recipient
     *@param amount_ amount of tokens to be transferred
     */
    function _transfer(address token_, address to_, uint256 amount_) internal {
        if (amount_ > 0 && to_ != address(0)) {
            if (token_ == COINBASE) {
                // solhint-disable-next-line avoid-low-level-calls
                (bool success, ) = to_.call{ value: amount_ }("");
                if (!success) revert TransferFailed();
            } else {
                SafeERC20.safeTransfer(IERC20(token_), to_, amount_);
            }
        }
    }

    /**
     * @notice get the balance of the contract
     * @param token_ address of the token
     * @return balance of the contract
     */
    function balanceOfSelf(address token_) public view returns (uint256) {
        if (token_ == COINBASE) {
            return address(this).balance;
        } else {
            return IERC20(token_).balanceOf(address(this));
        }
    }

    /**
     * @notice split the balance of the contract using the criteria provided by the ratio source
     * @param token_ address of the token to be split
     */
    function split(address token_) external nonReentrant {
        (uint256[] memory ratios, address[] memory recipients) = ratioSource.getRatio();
        uint256[] memory amounts = new uint256[](ratios.length);
        uint256 totalAmount = balanceOfSelf(token_);

        // transfer the tokens
        for (uint256 i = 0; i < ratios.length; i = unchecked_inc(i)) {
            // [N] = [N] * [PREC] / [PREC]
            amounts[i] = _mulPrec(totalAmount, ratios[i]);
            _transfer(token_, recipients[i], amounts[i]);
        }
        emit SplitExecuted(token_, recipients, amounts);
    }

    /**
     * @inheritdoc IRatioSource
     */
    function getRatio() external view returns (uint256[] memory ratios, address[] memory recipients) {
        return ratioSource.getRatio();
    }

    // ------- Only Authorized Changer Functions -------

    /**
     * @notice withdraws the entire balance of the contract to the given address
     * @dev only the authorized changer can call this function
     * @param token_ address of the token to be withdrawn
     * @param to_ address of the recipient
     */
    function emergencyWithdraw(address token_, address to_) external onlyAuthorizedChanger {
        uint256 balance = balanceOfSelf(token_);
        _transfer(token_, to_, balance);
        emit EmergencyWithdraw(token_, to_, balance);
    }

    /**
     * @notice sets the ratio source address
     * @dev only the authorized changer can call this function
     * @param ratioSourceAddress_ address of the ratio source contract
     */
    function setRatioSource(address ratioSourceAddress_) external onlyAuthorizedChanger {
        ratioSource = IRatioSource(ratioSourceAddress_);
    }

    // @notice used to receive coinbase
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
