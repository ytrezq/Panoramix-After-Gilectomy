// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

/* solhint-disable max-line-length */
import {IERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20PermitUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ERC20VotesUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import {DaoAuthorizableUpgradeable} from
    "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IERC20MintableUpgradeable} from "./IERC20MintableUpgradeable.sol";

/* solhint-enable max-line-length */

/// @title GovernanceERC20
/// @author Aragon X
/// @notice An [OpenZeppelin `Votes`](https://docs.openzeppelin.com/contracts/4.x/api/governance#Votes)
/// compatible [ERC-20](https://eips.ethereum.org/EIPS/eip-20) token, used for voting and managed by a DAO.
/// @custom:security-contact sirt@aragon.org
contract GovernanceERC20 is
    IERC20MintableUpgradeable,
    Initializable,
    ERC165Upgradeable,
    ERC20VotesUpgradeable,
    DaoAuthorizableUpgradeable
{
    /// @notice The permission identifier to mint new tokens
    bytes32 public constant MINT_PERMISSION_ID = keccak256("MINT_PERMISSION");

    /// @notice Whether mint() has been permanently disabled.
    bool private mintingFrozen;

    /// @notice Whether mint() should enable self delegation if the receiver has no delegate.
    bool private ensureDelegationOnMint;

    /// @notice The settings for the initial mint of the token.
    /// @param receivers The receivers of the tokens. On initialization only.
    /// @param amounts The amounts of tokens to be minted for each receiver. On initialization only.
    /// @param ensureDelegationOnMint Whether mint() calls should self delegate if the receiver doesn't have one.
    /// @dev The lengths of `receivers` and `amounts` must match.
    struct MintSettings {
        address[] receivers;
        uint256[] amounts;
        bool ensureDelegationOnMint;
    }

    /// @notice Emitted when minting is frozen permanently
    event MintingFrozen();

    /// @notice Thrown if the number of receivers and amounts specified in the mint settings do not match.
    /// @param receiversArrayLength The length of the `receivers` array.
    /// @param amountsArrayLength The length of the `amounts` array.
    error MintSettingsArrayLengthMismatch(uint256 receiversArrayLength, uint256 amountsArrayLength);

    /// @notice Thrown when attempting to mint when minting is permanently disabled
    error MintingIsFrozen();

    /// @notice Calls the initialize function.
    /// @param _dao The managing DAO.
    /// @param _name The name of the [ERC-20](https://eips.ethereum.org/EIPS/eip-20) governance token.
    /// @param _symbol The symbol of the [ERC-20](https://eips.ethereum.org/EIPS/eip-20) governance token.
    /// @param _mintSettings The token mint settings struct containing the `receivers`, the `amounts` and `ensureDelegationOnMint`.
    constructor(IDAO _dao, string memory _name, string memory _symbol, MintSettings memory _mintSettings) {
        initialize(_dao, _name, _symbol, _mintSettings);
    }

    /// @notice Initializes the contract and mints tokens to a list of receivers.
    /// @param _dao The managing DAO.
    /// @param _name The name of the [ERC-20](https://eips.ethereum.org/EIPS/eip-20) governance token.
    /// @param _symbol The symbol of the [ERC-20](https://eips.ethereum.org/EIPS/eip-20) governance token.
    /// @param _mintSettings The token mint settings struct containing the `receivers`, the `amounts` and `ensureDelegationOnMint`.
    function initialize(IDAO _dao, string memory _name, string memory _symbol, MintSettings memory _mintSettings)
        public
        initializer
    {
        // Check mint settings
        if (_mintSettings.receivers.length != _mintSettings.amounts.length) {
            revert MintSettingsArrayLengthMismatch({
                receiversArrayLength: _mintSettings.receivers.length,
                amountsArrayLength: _mintSettings.amounts.length
            });
        }

        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __DaoAuthorizableUpgradeable_init(_dao);

        // Mint
        ensureDelegationOnMint = _mintSettings.ensureDelegationOnMint;

        for (uint256 i; i < _mintSettings.receivers.length;) {
            address receiver = _mintSettings.receivers[i];
            if (_mintSettings.ensureDelegationOnMint) {
                _delegate(receiver, receiver);
            }
            _mint(receiver, _mintSettings.amounts[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(IERC20Upgradeable).interfaceId
            || _interfaceId == type(IERC20PermitUpgradeable).interfaceId
            || _interfaceId == type(IERC20MetadataUpgradeable).interfaceId
            || _interfaceId == type(IVotesUpgradeable).interfaceId
            || _interfaceId == type(IERC20MintableUpgradeable).interfaceId || super.supportsInterface(_interfaceId);
    }

    /// @notice Mints tokens to an address.
    /// @param to The address receiving the tokens.
    /// @param amount The amount of tokens to be minted.
    function mint(address to, uint256 amount) public virtual override auth(MINT_PERMISSION_ID) {
        if (getMintingFrozen()) {
            revert MintingIsFrozen();
        }

        if (getEnsureDelegationOnMint() && delegates(to) == address(0)) {
            _delegate(to, to);
        }
        _mint(to, amount);
    }

    /// @notice Disables the mint() function permanently
    function freezeMinting() public virtual auth(MINT_PERMISSION_ID) {
        if (getMintingFrozen()) return;

        mintingFrozen = true;
        emit MintingFrozen();
    }

    /// @notice Returns true if the ability to mint tokens has been frozen
    function getMintingFrozen() public view virtual returns (bool) {
        return mintingFrozen;
    }

    /// @notice Whether mint() enables self delegation if the receiver has no delegate.
    function getEnsureDelegationOnMint() public view virtual returns (bool) {
        return ensureDelegationOnMint;
    }
}
