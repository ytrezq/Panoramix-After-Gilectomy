// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {
    ChainlinkAceIssuanceValidatorBase
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceIssuanceValidatorBase.sol";
import {ComponentHarnessMixin} from "test/harnesses/utils/ComponentHarnessMixin.sol";

/// @dev Minimal concrete subclass of the abstract issuance validator base, exposing a dummy
/// handler-gated, policy-protected entrypoint so the base's own logic can be tested in isolation.
contract ChainlinkAceIssuanceValidatorBaseHarness is ChainlinkAceIssuanceValidatorBase, ComponentHarnessMixin {
    constructor(address _shares) ComponentHarnessMixin(_shares) {}

    function exposed_protectedAction(uint256 _value) external onlyHandler runPolicy {}
}
