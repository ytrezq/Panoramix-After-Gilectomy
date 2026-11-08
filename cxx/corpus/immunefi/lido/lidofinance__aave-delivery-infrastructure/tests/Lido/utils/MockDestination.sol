// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;


contract MockDestination {
  string public message;
  address public immutable EXECUTOR;

  event TestWorked(string message);

  constructor(address _executor) {
    require(_executor != address(0), 'WRONG_EXECUTOR');
    EXECUTOR = _executor;
  }

  function test(
    string memory _message
  ) external {
    require(msg.sender == EXECUTOR, 'CALLER_IS_NOT_EXECUTOR');

    message = _message;

    emit TestWorked(_message);
  }
}
