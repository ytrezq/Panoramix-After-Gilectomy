// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { stdJson } from "../../lib/forge-std/src/StdJson.sol";
import { VmSafe }  from "../../lib/forge-std/src/Vm.sol";

import { IAccessControl }                            from "../../lib/diamond-pau/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IAccessControls }                           from "../../lib/diamond-pau/src/interfaces/IAccessControls.sol";
import { IALMProxy }                                 from "../../lib/diamond-pau/src/interfaces/IALMProxy.sol";
import { IPAUFactory }                               from "../../lib/diamond-pau/src/interfaces/IPAUFactory.sol";
import { IBeacon }                                   from "../../lib/diamond-pau/src/interfaces/IBeacon.sol";
import { ICCTPFacet }                                from "../../lib/diamond-pau/src/facets/cctp/ICCTPFacet.sol";
import { Initializable }                             from "../../lib/diamond-pau/lib/oz-upgradeable/contracts/proxy/utils/Initializable.sol";
import { IEnumerableIntegrations as IEI }            from "../../lib/diamond-pau/src/interfaces/IEnumerableIntegrations.sol";
import { IMainnetControllerFull as IControllerFull } from "../../lib/diamond-pau/test/interfaces/IMainnetControllerFull.sol";
import { IRateLimits }                               from "../../lib/diamond-pau/src/interfaces/IRateLimits.sol";

import { IERC4626Facet } from "../../lib/diamond-pau/src/facets/erc4626/IERC4626Facet.sol";

import { PostDeployTestBase } from "../PostDeployTestBase.t.sol";

interface IDefaultPAUAssemblerLike {

    function pauFactory() external view returns (address);

    function administeredAgentFactory() external view returns (address);

}

abstract contract PostDeployTestBaseFull is PostDeployTestBase {

    using stdJson for string;

    IDefaultPAUAssemblerLike internal assembler;

    function _setUpAddresses(string memory json) internal override {
        super._setUpAddresses(json);

        assembler = IDefaultPAUAssemblerLike(json.readAddress(".defaultPAUAssembler"));
    }

    /**********************************************************************************************/
    /*** State Assertions                                                                       ***/
    /**********************************************************************************************/

    function _assertAdministeredAgentState() internal virtual view {
        assertEq(administeredAgent.adminCount(),   1);
        assertEq(administeredAgent.actorCount(),   1);
        assertEq(administeredAgent.grantorCount(), 1);
        assertEq(administeredAgent.revokerCount(), 1);

        assertEq(administeredAgent.getAdmin(0),   admin);
        assertEq(administeredAgent.getActor(0),   relayer);
        assertEq(administeredAgent.getGrantor(0), grantor);
        assertEq(administeredAgent.getRevoker(0), freezer);

        assertEq(administeredAgent.getIsAdmin(deployer),              false);
        assertEq(administeredAgent.getIsAdmin(address(assembler)),    false);
        assertEq(administeredAgent.getIsAdmin(address(agentFactory)), false);
    }

    function _assertAccessControlsState() internal view {
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, admin),     true);
        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);

        assertEq(accessControls.hasRole(ALLOCATOR_ROLE, address(administeredAgent)), true);
        assertEq(accessControls.getRoleMemberCount(ALLOCATOR_ROLE),                  1);

        // Neither the deployer nor the deploy infrastructure retains any role.

        assertEq(accessControls.hasRole(ALLOCATOR_ROLE,     deployer), false);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, deployer), false);

        assertEq(accessControls.hasRole(ALLOCATOR_ROLE,     address(assembler)), false);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, address(assembler)), false);

        assertEq(accessControls.hasRole(ALLOCATOR_ROLE,     address(pauFactory)), false);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, address(pauFactory)), false);
    }

    function _assertALMProxyState() internal view {
        assertEq(almProxy.hasRole(DEFAULT_ADMIN_ROLE, admin),               true);
        assertEq(almProxy.hasRole(CONTROLLER_ROLE,    address(controller)), true);

        assertEq(almProxy.hasRole(CONTROLLER_ROLE,    deployer), false);
        assertEq(almProxy.hasRole(DEFAULT_ADMIN_ROLE, deployer), false);

        assertEq(almProxy.hasRole(CONTROLLER_ROLE,    address(assembler)), false);
        assertEq(almProxy.hasRole(DEFAULT_ADMIN_ROLE, address(assembler)), false);

        assertEq(almProxy.hasRole(CONTROLLER_ROLE,    address(pauFactory)), false);
        assertEq(almProxy.hasRole(DEFAULT_ADMIN_ROLE, address(pauFactory)), false);
    }

    function _assertRateLimitsInitializationState() internal view {
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, admin),               true);
        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,    address(controller)), true);

        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,    deployer), false);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, deployer), false);

        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,    address(assembler)), false);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, address(assembler)), false);

        assertEq(rateLimits.hasRole(CONTROLLER_ROLE,    address(pauFactory)), false);
        assertEq(rateLimits.hasRole(DEFAULT_ADMIN_ROLE, address(pauFactory)), false);
    }

    /**********************************************************************************************/
    /*** Event test helpers                                                                     ***/
    /**********************************************************************************************/

    // Facet onboarding event helpers

    function _assertCCTPDomainParametersSetEvent(
        VmSafe.EthGetLogs memory log,
        uint32                   destinationDomain,
        address                  mintRecipient,
        uint32                   minFeeCapRate,
        uint32                   maxFeeCapRate
    ) internal pure {
        ( uint32 loggedMinFeeCapRate, uint32 loggedMaxFeeCapRate ) = abi.decode(log.data, (uint32, uint32));

        assertEq(log.topics[0],          ICCTPFacet.CCTPDomainParametersSet.selector);
        assertEq(uint256(log.topics[1]), uint256(destinationDomain));
        assertEq(log.topics[2],          bytes32(uint256(uint160(mintRecipient))));

        assertEq(loggedMinFeeCapRate, minFeeCapRate);
        assertEq(loggedMaxFeeCapRate, maxFeeCapRate);
    }

    function _assertERC4626MaxExchangeRateSetEvent(
        VmSafe.EthGetLogs memory log,
        address                  token,
        uint256                  maxExchangeRate
    ) internal pure {
        assertEq(log.topics[0],             IERC4626Facet.ERC4626MaxExchangeRateSet.selector);
        assertEq(_toAddress(log.topics[1]), token);

        assertEq(abi.decode(log.data, (uint256)), maxExchangeRate);
    }

}
