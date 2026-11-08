// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {ITokenP, IERC20Permit} from "contracts/interfaces/ITokenP.sol";
import {CommonErrorsLib } from "contracts/libraries/CommonErrorsLib.sol";

import {EIP3009} from "./EIP3009.sol";
import {TokenP_EventsLib as EventsLib} from "./EventsLib.sol";
import {TokenP_ErrorsLib as ErrorsLib} from "./ErrorsLib.sol";


/// @title TokenP
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice Base contract for Parallel Tokens (TokenP)
/// @dev By default, TokenP are ERC-20 tokens with 18 decimals
contract TokenP is ITokenP, ERC20PermitUpgradeable, AccessManagedUpgradeable, UUPSUpgradeable, EIP3009 {
     //-------------------------------------------
    // Storage
    //-------------------------------------------

    /// @notice Gap for future upgrades
    uint256[50] private __gap;

    //-------------------------------------------
    // Constructor
    //-------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    function initialize(string memory name_, string memory symbol_, address _accessManager) external initializer {
        require(_accessManager != address(0), CommonErrorsLib.AddressZero());
        __UUPSUpgradeable_init();
        __ERC20Permit_init(name_);
        __ERC20_init(name_, symbol_);
        __AccessManaged_init(_accessManager);
    }

    //-------------------------------------------
    // External functions
    //-------------------------------------------

    /// @notice Allows anyone to burn stablecoins
    /// @param amount Amount of stablecoins to burn
    /// @dev This function can typically be called if there is a settlement mechanism to burn stablecoins
    function burnStablecoin(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    //-------------------------------------------
    // Minter role only functions
    //-------------------------------------------

    /// @inheritdoc ITokenP
    function burnSelf(uint256 amount, address burner) external restricted {
        _burn(burner, amount);
    }

    /// @inheritdoc ITokenP
    function burnFrom(uint256 amount, address burner, address sender) external restricted {
        if (burner != sender) {
            _spendAllowance(burner, sender, amount);
        }
        _burn(burner, amount);
    }

    /// @inheritdoc ITokenP
    function mint(address account, uint256 amount) external restricted {
        _mint(account, amount);
    }

    //-------------------------------------------
    // Restricted functions
    //-------------------------------------------

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal virtual override restricted {}

    //-------------------------------------------
    // Overrides functions
    //-------------------------------------------

    /// @inheritdoc ERC20PermitUpgradeable
    function nonces(address owner) public view virtual override(ERC20PermitUpgradeable, IERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }

    //-------------------------------------------
    // Required overrides
    //-------------------------------------------

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view override(ERC20PermitUpgradeable, EIP3009, IERC20Permit) returns (bytes32) {
        return _domainSeparator();
    }
}
