// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IBeacon }                 from "../lib/diamond-pau/src/interfaces/IBeacon.sol";
import { IEnumerableIntegrations } from "../lib/diamond-pau/src/interfaces/IEnumerableIntegrations.sol";

import { IFacet } from "../lib/diamond-pau/src/facets/IFacet.sol";

import { ICCTPFacet } from "../lib/diamond-pau/src/facets/cctp/ICCTPFacet.sol";

/**
 * @title  BeaconConfig
 * @notice Library used to configure facet integrations at the beacons.
 */
library BeaconConfig {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    /// @notice Integration identifier for the CCTP facet.
    bytes32 internal constant CCTP_INTEGRATION = "CCTP_FACET";

    /**********************************************************************************************/
    /*** CCTP Integration                                                                       ***/
    /**********************************************************************************************/

    /**
     * @notice Configures the CCTP facet integration on the beacon.
     * @param  beacon Address of the Sky Diamond PAU Beacon.
     * @param  facet  Address of the deployed CCTPFacet contract.
     */
    function setCCTPIntegration(address beacon, address facet) internal {
        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](10);

        wires[0] = IEnumerableIntegrations.Wire(
            ICCTPController.cctp_setDomainParameters.selector,
            ICCTPFacet.setDomainParameters.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            ICCTPController.cctp_transfer.selector,
            ICCTPFacet.transfer.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            ICCTPController.cctp_toCCTPRateLimitKey.selector,
            ICCTPFacet.toCCTPRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            ICCTPController.cctp_getDomainParameters.selector,
            ICCTPFacet.getDomainParameters.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            ICCTPController.cctp_getToDomainRateLimitKey.selector,
            ICCTPFacet.getToDomainRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            ICCTPController.cctp_VERSION.selector,
            IFacet.VERSION.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            ICCTPController.cctp_DESTINATION_CALLER.selector,
            ICCTPFacet.DESTINATION_CALLER.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            ICCTPController.cctp_MIN_FINALITY_THRESHOLD.selector,
            ICCTPFacet.MIN_FINALITY_THRESHOLD.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            ICCTPController.cctp_cctp.selector,
            ICCTPFacet.cctp.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            ICCTPController.cctp_usdc.selector,
            ICCTPFacet.usdc.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : facet,
            wires : wires
        });

        IBeacon(beacon).setIntegration(CCTP_INTEGRATION, config);
    }

}

interface ICCTPController {

    function cctp_VERSION() external pure returns (string memory);

    function cctp_DESTINATION_CALLER() external pure returns (bytes32);

    function cctp_MIN_FINALITY_THRESHOLD() external pure returns (uint32);

    function cctp_cctp() external view returns (address);

    function cctp_usdc() external view returns (address);

    function cctp_setDomainParameters(
        uint32  destinationDomain,
        bytes32 recipient,
        uint32  minFeeCapRate,
        uint32  maxFeeCapRate
    ) external;

    function cctp_transfer(uint256 usdcAmount, uint32 destinationDomain, uint64 feeCapRate)
        external;

    function cctp_toCCTPRateLimitKey() external pure returns (bytes32 key);

    function cctp_getDomainParameters(uint32 destinationDomain)
        external
        view
        returns (bytes32 mintRecipient, uint32 minFeeCapRate, uint32 maxFeeCapRate);

    function cctp_getToDomainRateLimitKey(uint32 destinationDomain)
        external
        pure
        returns (bytes32 key);

}
