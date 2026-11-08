// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

// prettier-ignore
import {ERC20UpgradeSafe} from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol";

import {Initializable} from "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import {IGovernor} from "../moc-governance/Governance/IGovernor.sol";
import {Governed} from "../moc-governance/Governance/Governed.sol";
import {IMintableERC20} from "../IMintableERC20.sol";

contract GovernedERC20 is Initializable, Governed, ERC20UpgradeSafe, IMintableERC20 {
    /**
      @notice Initialize the contract with the basic settings
      @dev This initialize replaces the constructor but it is not called automatically.
      It is necessary because of the upgradeability of the contracts
      @param _governor Governor address
     */
    function initialize(IGovernor _governor) external initializer {
        Governed._initialize(_governor);
        __ERC20_init("TESTMOC", "TMOC");
        _setupDecimals(18);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements
     *
     * - `to` cannot be the zero address.
     */
    function mint(address account, uint256 amount) external override onlyAuthorizedChanger {
        _mint(account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function burn(address account, uint256 amount) external onlyAuthorizedChanger {
        _burn(account, amount);
    }
}
