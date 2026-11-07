/**
 * This smart contract code is Copyright 2017 TokenMarket Ltd. For more information see https://tokenmarket.net
 *
 * Licensed under the Apache License, version 2.0: https://github.com/TokenMarketNet/ico/blob/master/LICENSE.txt
 */

pragma solidity ^0.4.6;

import "./CrowdsaleExt.sol";
import "./ReleasableToken.sol";

/**
 * A finalize agent that does nothing.
 *
 * - Token transfer must be manually released by the owner
 */
contract NullFinalizeAgentExt is FinalizeAgent {

  CrowdsaleExt public crowdsale;

  function NullFinalizeAgentExt(CrowdsaleExt _crowdsale) {
    crowdsale = _crowdsale;
  }

  /** Check that we can release the token */
  function isSane() public constant returns (bool) {
    return true;
  }

  /** Called once by crowdsale finalize() if the sale was success. */
  function finalizeCrowdsale() public {
  }

}
