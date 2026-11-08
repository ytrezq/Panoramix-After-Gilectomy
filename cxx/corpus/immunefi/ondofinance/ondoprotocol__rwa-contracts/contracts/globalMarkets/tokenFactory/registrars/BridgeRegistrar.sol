// SPDX-License-Identifier: BUSL-1.1
/*
      ▄▄█████████▄
   ╓██▀└ ,╓▄▄▄, '▀██▄
  ██▀ ▄██▀▀╙╙▀▀██▄ └██µ           ,,       ,,      ,     ,,,            ,,,
 ██ ,██¬ ▄████▄  ▀█▄ ╙█▄      ▄███▀▀███▄   ███▄    ██  ███▀▀▀███▄    ▄███▀▀███,
██  ██ ╒█▀'   ╙█▌ ╙█▌ ██     ▐██      ███  █████,  ██  ██▌    └██▌  ██▌     └██▌
██ ▐█▌ ██      ╟█  █▌ ╟█     ██▌      ▐██  ██ └███ ██  ██▌     ╟██ j██       ╟██
╟█  ██ ╙██    ▄█▀ ▐█▌ ██     ╙██      ██▌  ██   ╙████  ██▌    ▄██▀  ██▌     ,██▀
 ██ "██, ╙▀▀███████████⌐      ╙████████▀   ██     ╙██  ███████▀▀     ╙███████▀`
  ██▄ ╙▀██▄▄▄▄▄,,,                ¬─                                    '─¬
   ╙▀██▄ '╙╙╙▀▀▀▀▀▀▀▀
      ╙▀▀██████R⌐
 */
pragma solidity 0.8.33;

import {IRegistrar} from "contracts/globalMarkets/tokenFactory/registrars/IRegistrar.sol";
import {
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {Pausable} from "contracts/external/openzeppelin/contracts/security/Pausable.sol";
import {IERC20Metadata} from "contracts/external/openzeppelin/contracts/token/IERC20Metadata.sol";
import {IOndoOwner} from "contracts/external/layerzero/IOndoOwner.sol";
import {
  IAccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/IAccessControlEnumerable.sol";

/**
 * @title  BridgeRegistrar
 * @author Ondo Finance
 * @notice This contract is responsible for registering new tokens with the GM bridge
 *         system. It handles the registration of new tokens with determinstic IDs and
 *         granting the freshly deployed OFT contract the minter role to allow bridging.
 */
contract BridgeRegistrar is IRegistrar, AccessControlEnumerable, Pausable {
  /// Role for the token factory that can register new tokens
  bytes32 public constant TOKEN_FACTORY_ROLE = keccak256("TOKEN_FACTORY_ROLE");
  /// Role allowed to pause the registrar
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  /// Role allowed to unpause the registrar
  bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

  /// Address of the `OndoOwner` contract that manages GM bridge configurations
  IOndoOwner public ondoBridgeOwner;

  /**
   * @notice Emitted when the `ondoBridgeOwner` address is updated
   * @param  oldOndoBridgeOwner The old owner address
   * @param  newOndoBridgeOwner The new owner address
   */
  event OndoBridgeOwnerSet(address indexed oldOndoBridgeOwner, address indexed newOndoBridgeOwner);

  /**
   * @notice Emitted when a new token is registered
   * @param token   The address of the token that was registered following a deployment
   * @param tokenId The LayerZero specific ID of the token
   */
  event TokenRegistered(address indexed token, bytes32 indexed tokenId);

  /// Error thrown when attempting to pass in zero address for guardian
  error GuardianCantBeZero();

  /// Error thrown when attempting to set the `ondoBridgeOwner` to zero address
  error OndoBridgeOwnerCantBeZero();

  /// Error thrown when attempting to register a token with zero address
  error TokenAddressCantBeZero();

  /**
   * @notice Constructor to initialize the contract with the Ondo Bridge Owner
   * @param  guardian         The address of the admin account that begins with the default admin role
   * @param  _ondoBridgeOwner The address of the Ondo Bridge Owner contract
   */
  constructor(address guardian, address _ondoBridgeOwner) {
    if (guardian == address(0)) revert GuardianCantBeZero();
    if (_ondoBridgeOwner == address(0)) revert OndoBridgeOwnerCantBeZero();
    ondoBridgeOwner = IOndoOwner(_ondoBridgeOwner);

    _grantRole(DEFAULT_ADMIN_ROLE, guardian);
    _grantRole(PAUSER_ROLE, guardian);
    _grantRole(UNPAUSER_ROLE, guardian);
  }

  /**
   * @notice Pauses the registrar, disabling registration
   */
  function pause() external onlyRole(PAUSER_ROLE) {
    _pause();
  }

  /**
   * @notice Unpauses the registrar, enabling registration
   */
  function unpause() external onlyRole(UNPAUSER_ROLE) {
    _unpause();
  }

  /**
   * @notice Registers a new token with the GM Token bridge
   * @param  token The address of the token to register
   * @dev    Only callable by accounts with TOKEN_FACTORY_ROLE
   */
  function register(address token) external override onlyRole(TOKEN_FACTORY_ROLE) whenNotPaused {
    if (token == address(0)) revert TokenAddressCantBeZero();

    // The token ID is a chain agnostic identifier for the token. We use the keccak256 hash of the
    // token's symbol and name, as for initial deployments we want this to be calculated the same
    // on any chain.
    bytes32 tokenId =
      keccak256(abi.encode(IERC20Metadata(token).symbol(), IERC20Metadata(token).name()));

    // This will register the token with the Messenger and deploy a new OFT contract to handle mints
    address oft = ondoBridgeOwner.registerToken(tokenId, token);

    // Grant minter role to the new OFT that will mint the token for inbound bridges
    IAccessControlEnumerable(token).grantRole(keccak256("MINTER_ROLE"), oft);

    emit TokenRegistered(token, tokenId);
  }

  /**
   * @notice Sets or updates the Ondo Bridge Owner contract address
   * @param  _ondoBridgeOwner The new Ondo Bridge Owner contract address
   */
  function setOndoBridgeOwner(address _ondoBridgeOwner) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_ondoBridgeOwner == address(0)) {
      revert OndoBridgeOwnerCantBeZero();
    }

    emit OndoBridgeOwnerSet(address(ondoBridgeOwner), _ondoBridgeOwner);
    ondoBridgeOwner = IOndoOwner(_ondoBridgeOwner);
  }
}
