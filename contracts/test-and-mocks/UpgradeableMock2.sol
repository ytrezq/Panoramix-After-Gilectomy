// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.0;

import {Governed} from "../moc-governance/Governance/Governed.sol";
import {IGovernor} from "../moc-governance/Governance/IGovernor.sol";
import {Initializable} from "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";

contract UpgradeableMock2 is Initializable, Governed {
    function initialize(IGovernor _governor) external initializer {
        Governed._initialize(_governor);
    }

    function getID() external pure returns (string memory) {
        return "UpgradeableMock2";
    }
}
