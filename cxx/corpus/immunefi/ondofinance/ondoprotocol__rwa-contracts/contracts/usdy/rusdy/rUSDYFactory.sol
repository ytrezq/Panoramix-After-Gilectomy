/**
 * SPDX-License-Identifier: BUSL-1.1
 *
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
 *
 */
pragma solidity 0.8.33;

// Proxy admin contract used in OZ upgrades plugin
import {ProxyAdmin} from "contracts/external/openzeppelin/contracts/proxy/ProxyAdmin.sol";
import {TokenProxy} from "contracts/Proxy.sol";
import {rUSDY} from "contracts/usdy/rusdy/rUSDY.sol";
import {IMulticall} from "contracts/interfaces/IMulticall.sol";

/**
 * @title rUSDYFactory
 * @author Ondo Finance
 * @notice This contract serves as a Factory for the upgradable rUSDY token contract.
 *         Upon calling `deployrUSDY` the `guardian` address (set in constructor) will
 *         deploy the following:
 *         1) rUSDY - The implementation contract, ERC20 contract with the initializer disabled
 *         2) ProxyAdmin - OZ ProxyAdmin contract, used to upgrade the proxy instance.
 *                         @notice Owner is set to `guardian` address.
 *         3) TransparentUpgradeableProxy - OZ, proxy contract. Admin is set to `address(proxyAdmin)`.
 *                                          `_logic' is set to `address(rUSDY)`.
 * @notice `guardian` address in constructor is a msig.
 */
contract rUSDYFactory is IMulticall {
  bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);

  address internal immutable GUARDIAN;
  rUSDY public rUSDYImplementation;
  ProxyAdmin public rUSDYProxyAdmin;
  TokenProxy public rUSDYProxy;

  bool public initialized = false;

  constructor(address _guardian) {
    GUARDIAN = _guardian;
  }

  /**
   * @dev This function will deploy an upgradable instance of rUSDY
   *
   * @param blocklist     The address of the blocklist
   * @param sanctionsList The address of the sanctions list
   * @param usdy          The address of USDY
   *
   * @return address The address of the proxy contract.
   * @return address The address of the proxyAdmin contract.
   * @return address The address of the implementation contract.
   *
   * @notice 1) Will grant DEFAULT_ADMIN, PAUSER_ROLE, BURNER_ROLE, and CONFIGURER_ROLE to `guardian`
   *            address, as specified in rUSDY constructor.
   *         2) Will transfer ownership of the proxyAdmin to guardian
   *            address.
   *
   */
  function deployrUSDY(address blocklist, address sanctionsList, address usdy, address oracle)
    external
    onlyGuardian
    returns (address, address, address)
  {
    require(!initialized, "RUSDYFactory: rUSDY already deployed");
    rUSDYImplementation = new rUSDY();
    rUSDYProxyAdmin = new ProxyAdmin();
    rUSDYProxy = new TokenProxy(address(rUSDYImplementation), address(rUSDYProxyAdmin), "");
    rUSDY rUSDYProxied = rUSDY(address(rUSDYProxy));
    rUSDYProxied.initialize(blocklist, sanctionsList, usdy, GUARDIAN, oracle);

    rUSDYProxyAdmin.transferOwnership(GUARDIAN);
    assert(rUSDYProxyAdmin.owner() == GUARDIAN);
    initialized = true;
    emit rUSDYDeployed(
      address(rUSDYProxy),
      address(rUSDYProxyAdmin),
      address(rUSDYImplementation),
      rUSDYProxied.name(),
      rUSDYProxied.symbol()
    );
    return (address(rUSDYProxy), address(rUSDYProxyAdmin), address(rUSDYImplementation));
  }

  /**
   * @notice Allows for arbitrary batched calls
   *
   * @dev All external calls made through this function will
   *      msg.sender == contract address
   *
   * @param exCallData Struct consisting of
   *       1) target - contract to call
   *       2) data - data to call target with
   *       3) value - eth value to call target with
   */
  function multiexcall(ExCallData[] calldata exCallData)
    external
    payable
    override
    onlyGuardian
    returns (bytes[] memory results)
  {
    results = new bytes[](exCallData.length);
    for (uint256 i = 0; i < exCallData.length; ++i) {
      (bool success, bytes memory ret) =
        address(exCallData[i].target).call{value: exCallData[i].value}(exCallData[i].data);
      require(success, "Call Failed");
      results[i] = ret;
    }
  }

  /**
   * @dev Event emitted when upgradable rUSDY is deployed
   *
   * @param proxy             The address for the proxy contract
   * @param proxyAdmin        The address for the proxy admin contract
   * @param implementation    The address for the implementation contract
   */
  event rUSDYDeployed(
    address proxy, address proxyAdmin, address implementation, string name, string ticker
  );

  modifier onlyGuardian() {
    require(msg.sender == GUARDIAN, "rUSDYFactory: You are not the Guardian");
    _;
  }
}
