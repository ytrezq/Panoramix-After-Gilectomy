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
  AccessControlEnumerable
} from "contracts/external/openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {
  IAdminSubscriptionChecker
} from "contracts/xManager/interfaces/IAdminSubscriptionChecker.sol";

/**
 * @title  AdminSubscriptionChecker
 * @author Ondo Finance
 * @notice This contract tracks and enforces individual subscription allowances for permissioned
 *         admins.
 */
contract AdminSubscriptionChecker is IAdminSubscriptionChecker, AccessControlEnumerable {
  /// Role that allows an address to configure the subscription allowance
  bytes32 public constant SUBSCRIPTION_ALLOWANCE_CONFIGURER =
    keccak256("SUBSCRIPTION_ALLOWANCE_CONFIGURER");

  /// Role that allows the RWA manager to check and update the subscription allowance
  bytes32 public constant RWA_MANAGER = keccak256("RWA_MANAGER");

  /**
   * @notice Mapping of addresses to their admin subscription allowance.
   *         Allowances are denominated in USD with 18 decimals.
   */
  mapping(address => uint256) public adminSubscriptionAllowance;

  /**
   * @notice Event emitted when an admin's subscription allowance is set
   * @param  admin The address of the admin for which the allowance was set
   * @param  limit The subscription allowance for the admin, denonimated in USD with 18 decimals
   */
  event AdminSubscriptionAllowanceSet(address indexed admin, uint256 limit);

  /**
   * @notice Event emitted when an admin's subscription allowance is used to mint an RWA
   * @param  admin          The address of the admin for which the allowance was updated
   * @param  remainingLimit The remaining subscription allowance for the admin, denominated in USD
   *                        with 18 decimals
   * @param  amountUsed     The amount by which the allowance was reduced, denominated in USD with
   *                        18 decimals
   */
  event AdminSubscriptionAllowanceUsed(
    address indexed admin, uint256 remainingLimit, uint256 amountUsed
  );

  /// Error emitted when an admin's subscription allowance is exceeded
  error SubscriptionAllowanceExceeded();

  /**
   * @param  admin The address that will be the default admin.
   */
  constructor(address admin) {
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
  }

  /**
   * @notice Sets the USD subscription allowance for an admin
   * @param  admin     The address of the admin
   * @param  usdAmount The amount of USD that the admin is subscribing for, denoted with 18 decimals
   */
  function checkAndUpdateAdminSubscriptionAllowance(address admin, uint256 usdAmount)
    external
    override
    onlyRole(RWA_MANAGER)
  {
    if (adminSubscriptionAllowance[admin] < usdAmount) {
      revert SubscriptionAllowanceExceeded();
    }
    adminSubscriptionAllowance[admin] -= usdAmount;
    emit AdminSubscriptionAllowanceUsed(admin, adminSubscriptionAllowance[admin], usdAmount);
  }

  /**
   * @notice Sets the subscription allowance for an admin.
   * @param  admin          The address of the admin.
   * @param  usdAllowance   The maximum amount of USD that the admin can subscribe, in 18 decimals
   */
  function setAdminSubscriptionAllowance(address admin, uint256 usdAllowance)
    public
    onlyRole(SUBSCRIPTION_ALLOWANCE_CONFIGURER)
  {
    adminSubscriptionAllowance[admin] = usdAllowance;
    emit AdminSubscriptionAllowanceSet(admin, usdAllowance);
  }
}
