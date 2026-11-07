/**
 * SPDX-License-Identifier: BUSL-1.1
 *       ▄▄█████████▄
 *    ╓██▀└ ,╓▄▄▄, '▀██▄
 *   ██▀ ▄██▀▀╙╙▀▀██▄ └██µ           ,,       ,,      ,     ,,,            ,,,
 *  ██ ,██¬ ▄████▄  ▀█▄ ╙█▄      ▄███▀▀███▄   ███▄    ██  ███▀▀▀███▄    ▄███▀▀███,
 * ██  ██ ╒█▀'   ╙█▌ ╙█▌ ██     ▐██      ███  █████,  ██  ██▌    └██▌  ██▌     └██▌
 * ██ ▐█▌ ██      ╟█  █▌ ╟█     ██▌      ▐██  ██ └███ ██  ██▌     ╟██ j██       ╟██
 * ╟█  ██ ╙██    ▄█▀ ▐█▌ ██     ╙██      ██▌  ██   ╙████  ██▌    ▄██▀  ██▌     ,██▀
 *  ██ "██, ╙▀▀███████████⌐      ╙████████▀   ██     ╙██  ███████▀▀     ╙███████▀`
 *   ██▄ ╙▀██▄▄▄▄▄,,,                ¬─                                    '─¬
 *    ╙▀██▄ '╙╙╙▀▀▀▀▀▀▀▀
 *       ╙▀▀██████R⌐
 */
pragma solidity 0.8.33;

// Proxy admin contract used in OZ upgrades plugin
import {ProxyAdmin} from "contracts/external/openzeppelin/contracts/proxy/ProxyAdmin.sol";
import {TokenProxy} from "contracts/Proxy.sol";
import {USDon} from "contracts/globalMarkets/USDon.sol";

/**
 * @title USDonFactory
 * @author Ondo Finance
 * @notice This contract serves as a Factory for the upgradable USDon token contract.
 *         Upon calling `deployUSDon` the `guardian` address (set in constructor) will
 *         deploy the following:
 *         1) USDon - The implementation contract, ERC20 contract with the initializer disabled
 *         2) ProxyAdmin - OZ ProxyAdmin contract, used to upgrade the proxy instance.
 *                         @notice Owner is set to `guardian` address.
 *         3) TransparentUpgradeableProxy - OZ, proxy contract. Admin is set to `address(proxyAdmin)`.
 *                                          `_logic' is set to `address(cash)`.
 *
 *         Following the above mentioned deployment, the address of the USDon_Factory contract will:
 *         i) Grant the `DEFAULT_ADMIN_ROLE` & PAUSER_ROLE to the `guardian` address
 *         ii) Revoke the `MINTER_ROLE`, `PAUSER_ROLE` & `DEFAULT_ADMIN_ROLE` from address(this).
 *         iii) Transfer ownership of the ProxyAdmin to that of the `guardian` address.
 */
contract USDon_Factory {
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
  bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);

  address internal immutable GUARDIAN;
  USDon public usdonImplementation;
  ProxyAdmin public usdonProxyAdmin;
  TokenProxy public usdonProxy;

  bool public initialized = false;

  constructor(address _guardian) {
    GUARDIAN = _guardian;
  }

  /**
   * @dev This function will deploy an upgradable instance of USDon
   *
   * @param name           The name of the USDon token
   * @param ticker         The ticker of the USDon token
   * @param complianceView The address of the compliance view contract.
   *
   * @return address The address of the proxy contract.
   * @return address The address of the proxyAdmin contract.
   * @return address The address of the implementation contract.
   *
   * @notice 1) Will automatically revoke all deployer roles granted to
   *            address(this).
   *         2) Will grant DEFAULT_ADMIN to `guardian`
   *            address specified in constructor.
   *         3) Will transfer ownership of the proxyAdmin to guardian
   *            address.
   *
   */
  function deployUSDon(string calldata name, string calldata ticker, address complianceView)
    external
    onlyGuardian
    returns (address, address, address)
  {
    require(!initialized, "USDon_Factory: USDon already deployed");
    usdonImplementation = new USDon();
    usdonProxyAdmin = new ProxyAdmin();
    usdonProxy = new TokenProxy(address(usdonImplementation), address(usdonProxyAdmin), "");
    USDon usdonProxied = USDon(address(usdonProxy));
    usdonProxied.initialize(name, ticker, complianceView);

    usdonProxied.grantRole(DEFAULT_ADMIN_ROLE, GUARDIAN);

    usdonProxied.revokeRole(MINTER_ROLE, address(this));
    usdonProxied.revokeRole(PAUSER_ROLE, address(this));
    usdonProxied.revokeRole(DEFAULT_ADMIN_ROLE, address(this));

    usdonProxyAdmin.transferOwnership(GUARDIAN);
    assert(usdonProxyAdmin.owner() == GUARDIAN);
    initialized = true;
    emit USDonDeployed(
      address(usdonProxied),
      address(usdonProxyAdmin),
      address(usdonImplementation),
      name,
      ticker,
      complianceView
    );

    return (address(usdonProxied), address(usdonProxyAdmin), address(usdonImplementation));
  }

  /**
   * @notice Event emitted when upgradable USDon is deployed
   * @param  proxy             The address for the proxy contract
   * @param  proxyAdmin        The address for the proxy admin contract
   * @param  implementation    The address for the implementation contract
   * @param  name              The name of the USDon token
   * @param  ticker            The ticker of the USDon token
   * @param  complianceView    The address of the compliance view contract
   */
  event USDonDeployed(
    address proxy,
    address proxyAdmin,
    address implementation,
    string name,
    string ticker,
    address complianceView
  );

  /**
   * @notice Modifier to restrict access to the guardian address
   */
  modifier onlyGuardian() {
    require(msg.sender == GUARDIAN, "USDonFactory: You are not the Guardian");
    _;
  }
}
