// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {ChainlinkAcePolicyProtectedBase} from "src/infra/chainlink-ace/ChainlinkAcePolicyProtectedBase.sol";
import {ComponentHarnessMixin} from "test/harnesses/utils/ComponentHarnessMixin.sol";

contract ChainlinkAcePolicyProtectedBaseHarness is ChainlinkAcePolicyProtectedBase, ComponentHarnessMixin {
    constructor(address _shares) ComponentHarnessMixin(_shares) {}

    function exposed__PolicyProtectedBase_init(address _policyEngine) external initializer {
        __PolicyProtectedBase_init(_policyEngine);
    }

    function exposed_protectedAction(uint256 _value) external runPolicy {}
}
