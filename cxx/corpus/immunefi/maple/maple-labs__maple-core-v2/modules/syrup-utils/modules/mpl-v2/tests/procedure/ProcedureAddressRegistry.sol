// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { MapleAddressRegistry } from "../../modules/address-registry/contracts/MapleAddressRegistry.sol";

contract ProcedureAddressRegistry is MapleAddressRegistry {

    address migrator                = address(0x7b0267C13B994cdb58b8ED3a65b7A09a07432A76);
    address mplv2Implementation     = address(0x2feb650302d54C227Bb56361005CA3Ec7265a40D);
    address mplv2Initializer        = address(0x7f3C3636208A18c7941BF051807db56864061465);
    address mplv2Proxy              = address(0x1915A8dE08A92b846dF7C845e140E4b0714820bd); 
    address recapitalizationClaimer = address(0x6b1A78C1943b03086F7Ee53360f9b0672bD60818);
    address recapitalizationModule  = address(0x7D75cF9Aab6cB9598bB6d9Bd81BaAA288cecA9Bf);

}
