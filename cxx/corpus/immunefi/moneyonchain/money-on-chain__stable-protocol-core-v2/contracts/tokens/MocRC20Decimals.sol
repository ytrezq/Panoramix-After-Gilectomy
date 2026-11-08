// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { MocRC20 } from "./MocRC20.sol";
import { IGovernor } from "../governance/Governed.sol";

/**
 * @title MocRC20Decimals
 * @notice Moc ERC20 Token with custom decimals
 */
contract MocRC20Decimals is MocRC20 {
    // ------- Storage -------
    uint8 private _decimals;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice contract initializer
     * @dev grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `BURNER_ROLE` to `admin_` address.
     * @param name_ RC20 token name
     * @param symbol_ RC20 token symbol
     * @param decimals_ RC20 token decimals
     * @param admin_ address of the admin
     * @param governor_ address of the governor
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address admin_,
        IGovernor governor_
    ) external initializer {
        _decimals = decimals_;
        __MocRC20_init(name_, symbol_, admin_, governor_);
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the default value returned by this function, unless
     * it's overridden.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
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
