// SPDX-License-Identifier: BUSL-1.1
/*
      ▄▄█████████▄
   ╓██▀└ ,╓▄▄▄, '▀██▄
  ██▀ ▄██▀▀╙╙▀▀██▄ └██µ           ,,       ,,      ,     ,,,            ,,,
 ██ ,██¬ ▄████▄  ▀█▄ ╙█▄      ▄███▀▀███▄   ███▄    ██  ███▀▀▀███▄    ▄███▀▀███,
██  ██ ╒█▀'   ╙█▌ ╙█▌ ██     ▐██      ███  █████,  ██  ██▌    └██▌  ██▌     └██▌
██ ▐█▌ ██      ╟█  █▌ ╟█     ██▌      ▐██  ██ └███ ██  ██▌     ╟██ j██       ╟██
╟█  ██ ╙██    ▄█▀ ▐█▌ ██     ╙██      ██▌  ██   ╙████  ██▌    ▄██▀  ██▌     ,██▀
 ██ "██, ╙▀▀███████████⌐      ╙████████▀   ██     ╙██  ███████▀▀     ╙███████▀`
  ██▄ ╙▀██▄▄▄▄▄,,,                ¬─                                    '─¬
   ╙▀██▄ '╙╙╙▀▀▀▀▀▀▀▀
      ╙▀▀██████R⌐
 */
pragma solidity ^0.8.4;

interface IOUSG_InstantManager {
  function subscribe(address depositToken, uint256 depositAmount, uint256 minimumRwaReceived)
    external
    returns (uint256 rwaAmountOut);

  function subscribeRebasingOUSG(
    address depositToken,
    uint256 depositAmount,
    uint256 minimumRwaReceived
  ) external returns (uint256 rousgAmountOut);

  function adminSubscribe(address recipient, uint256 rwaAmount, bytes32 metadata) external;

  function adminSubscribeRebasingOUSG(address recipient, uint256 rousgAmount, bytes32 metadata)
    external;

  function redeem(uint256 rwaAmount, address receivingToken, uint256 minimumTokenReceived)
    external
    returns (uint256 receiveTokenAmount);

  function redeemRebasingOUSG(
    uint256 rwaAmount,
    address receivingToken,
    uint256 minimumTokenReceived
  ) external returns (uint256 receiveTokenAmount);
}
