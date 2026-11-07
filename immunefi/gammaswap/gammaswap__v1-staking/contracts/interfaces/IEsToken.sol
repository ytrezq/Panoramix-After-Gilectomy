// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "./IRestrictedToken.sol";

interface IEsToken is IRestrictedToken {
    function claimableToken() external view returns(address);
}
