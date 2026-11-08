// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {
    ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator
} from "src/components/issuance/hooks/chainlink-ace/ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator.sol";
import {ComponentHarnessMixin} from "test/harnesses/utils/ComponentHarnessMixin.sol";

contract ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidatorHarness is
    ChainlinkAceERC7540LikeRedeemQueuePostExecuteRedeemRequestValidator,
    ComponentHarnessMixin
{
    constructor(address _shares) ComponentHarnessMixin(_shares) {}
}
