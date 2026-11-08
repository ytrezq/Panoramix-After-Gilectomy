// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { ArbitrumERC20Forwarder } from "src/forwarders/ArbitrumERC20Forwarder.sol";

contract ArbitrumERC20ForwarderExecutor {

    uint256 internal constant GAS_LIMIT       = 100_000;
    uint256 internal constant MAX_FEE_PER_GAS = 1 gwei;
    uint256 internal constant BASE_FEE        = 1 gwei;

    function sendMessageL1toL2(
        address l1CrossDomain,
        address target,
        bytes memory message
    ) public {
        ArbitrumERC20Forwarder.sendMessageL1toL2(
            l1CrossDomain,
            target,
            message,
            GAS_LIMIT,
            MAX_FEE_PER_GAS,
            BASE_FEE
        );
    }

}
