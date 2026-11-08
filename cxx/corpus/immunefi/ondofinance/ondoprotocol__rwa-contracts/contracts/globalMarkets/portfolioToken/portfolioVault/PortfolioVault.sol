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

import {
  IPortfolioVault
} from "contracts/globalMarkets/portfolioToken/portfolioVault/IPortfolioVault.sol";
import {
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {
  ReentrancyGuardTransient
} from "contracts/external/openzeppelin/contracts/security/ReentrancyGuardTransient.sol";
import {IERC20} from "contracts/external/openzeppelin/contracts/token/IERC20.sol";
import {SafeERC20} from "contracts/external/openzeppelin/contracts/token/SafeERC20.sol";

/**
 * @title  PortfolioVault
 * @author Ondo Finance
 * @notice Per-portfolio-token custody contract. Deposits are immediately
 *         forwarded to an external custody address; withdrawals push tokens from
 *         the vault's own balance to the caller. Only addresses with
 *         ORCHESTRATOR_ROLE can deposit or withdraw; no allowances are issued
 *         by the vault.
 *
 *         Not upgradeable — replacement is a new deploy plus
 *         `PortfolioOrchestrator.setVaultAddress`.
 */
contract PortfolioVault is IPortfolioVault, AccessControlEnumerable, ReentrancyGuardTransient {
  using SafeERC20 for IERC20;

  /// Role granted to the PortfolioOrchestrator(s) permitted to deposit / withdraw.
  bytes32 public constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

  /// The external custody destination that receives forwarded deposits.
  address public immutable custodyAddress;

  /// The portfolio token this vault serves (for traceability / off-chain indexing).
  address public immutable portfolioToken;

  /**
   * @notice Event emitted when tokens are deposited and forwarded to custody
   * @param  token       The token that was forwarded
   * @param  destination The custody address that received the tokens
   * @param  amount      The amount forwarded, in the token's native decimals
   */
  event Deposited(address indexed token, address indexed destination, uint256 amount);

  /**
   * @notice Event emitted when tokens are withdrawn from the vault to the caller
   * @param  token     The token that was withdrawn
   * @param  recipient The address that received the tokens (the orchestrator caller)
   * @param  amount    The amount withdrawn, in the token's native decimals
   */
  event Withdrawn(address indexed token, address indexed recipient, uint256 amount);

  /**
   * @notice Event emitted when tokens are rescued from the contract via `retrieveTokens`
   * @param  token     The address of the token that was retrieved
   * @param  recipient The address that received the tokens
   * @param  amount    The amount retrieved, in the token's native decimals
   */
  event TokensRetrieved(address indexed token, address indexed recipient, uint256 amount);

  /// Error emitted when a withdrawal is requested for more than the vault's balance
  error InsufficientBalance(address token, uint256 requested, uint256 available);

  /// Error emitted when the orchestrator address provided to the constructor is zero
  error OrchestratorAddressCantBeZero();

  /// Error emitted when the custody address provided to the constructor is zero
  error CustodyAddressCantBeZero();

  /// Error emitted when the portfolio token address provided to the constructor is zero
  error PortfolioTokenAddressCantBeZero();

  /// Error emitted when the default admin address provided to the constructor is zero
  error DefaultAdminZeroAddress();

  /**
   * @param _defaultAdmin   The DEFAULT_ADMIN_ROLE grantee (gates `retrieveTokens`
   *                        and grant/revoke of ORCHESTRATOR_ROLE)
   * @param _orchestrator   The initial ORCHESTRATOR_ROLE grantee
   * @param _custodyAddress The external custody address that receives deposits
   * @param _portfolioToken The portfolio token this vault serves
   */
  constructor(
    address _defaultAdmin,
    address _orchestrator,
    address _custodyAddress,
    address _portfolioToken
  ) {
    if (_defaultAdmin == address(0)) revert DefaultAdminZeroAddress();
    if (_orchestrator == address(0)) revert OrchestratorAddressCantBeZero();
    if (_custodyAddress == address(0)) revert CustodyAddressCantBeZero();
    if (_portfolioToken == address(0)) revert PortfolioTokenAddressCantBeZero();

    custodyAddress = _custodyAddress;
    portfolioToken = _portfolioToken;

    _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
    _grantRole(ORCHESTRATOR_ROLE, _orchestrator);
  }

  /**
   * @notice Pull `amount` of `token` from the caller and forward it on to the
   *         external custody address. The caller must have approved the vault for
   *         at least `amount` prior to the call. Token movement is performed
   *         entirely by the vault — the caller only grants the allowance and
   *         triggers the transfer.
   * @param  token  The token to pull and forward
   * @param  amount The amount to pull and forward
   */
  function deposit(address token, uint256 amount)
    external
    nonReentrant
    onlyRole(ORCHESTRATOR_ROLE)
  {
    IERC20(token).safeTransferFrom(msg.sender, custodyAddress, amount);
    emit Deposited(token, custodyAddress, amount);
  }

  /**
   * @notice Send `amount` of `token` from this vault to the caller. Reverts
   *         with `InsufficientBalance` if the vault hasn't yet been funded
   *         with at least `amount` of `token`.
   * @param  token  The token to withdraw
   * @param  amount The amount to withdraw to the caller
   */
  function withdraw(address token, uint256 amount)
    external
    nonReentrant
    onlyRole(ORCHESTRATOR_ROLE)
  {
    uint256 available = IERC20(token).balanceOf(address(this));
    if (available < amount) revert InsufficientBalance(token, amount, available);
    IERC20(token).safeTransfer(msg.sender, amount);
    emit Withdrawn(token, msg.sender, amount);
  }

  /**
   * @notice Rescue tokens locked in this contract (e.g. airdrops, stuck dust).
   * @param  token  The address of the token
   * @param  to     The address of the recipient
   * @param  amount The amount of token to transfer
   */
  function retrieveTokens(address token, address to, uint256 amount)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    IERC20(token).safeTransfer(to, amount);
    emit TokensRetrieved(token, to, amount);
  }
}
