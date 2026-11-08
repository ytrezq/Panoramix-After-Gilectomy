/**
 * SPDX-License-Identifier: BUSL-1.1
 *
 *       ▄▄█████████▄
 *    ╓██▀└ ,╓▄▄▄, '▀██▄
 *   ██▀ ▄██▀▀╙╙▀▀██▄ └██µ           ,,       ,,      ,     ,,,            ,,,
 *  ██ ,██¬ ▄████▄  ▀█▄ ╙█▄      ▄███▀▀███▄   ███▄    ██  ███▀▀▀███▄    ▄███▀▀███,
 * ██  ██ ╒█▀'   ╙█▌ ╙█▌ ██     ▐██      ███  █████,  ██  ██▌    └██▌  ██▌     └██▌
 * ██ ▐█▌ ██      ╟█  █▌ ╟█     ██▌      ▐██  ██ └███ ██  ██▌     ╟██ j██       ╟██
 * ╟█  ██ ╙██    ▄█▀ ▐█▌ ██     ╙██      ██▌  ██   ╙████  ██▌    ▄██▀  ██▌     ,██▀
 *  ██ "██, ╙▀▀███████████⌐      ╙████████▀   ██     ╙██  ███████▀▀     ╙███████▀`
 *   ██▄ ╙▀██▄▄▄▄▄,,,                ¬─                                    '─¬
 *    ╙▀██▄ '╙╙╙▀▀▀▀▀▀▀▀
 *       ╙▀▀██████R⌐
 *
 */
pragma solidity 0.8.33;
import {
  IIssuanceHours
} from "contracts/globalMarkets/tokenManager/issuanceHours/IIssuanceHours.sol";
import {Ownable2Step} from "contracts/external/openzeppelin/contracts/access/Ownable2Step.sol";
import {
  BokkyPooBahsDateTimeLibrary
} from "contracts/external/BokkyPooBahsDateTimeLibrary/BokkyPooBahsDateTimeLibrary.sol";

/**
 * @title  IssuanceHours
 * @author Ondo Finance
 * @notice This contract is used to check if the current time is within the
 *         issuance hours for a given market. The issuance hours are defined
 *         as Monday to Friday 24/5.
 *
 * @dev    This is a naive layer of protection for defense-in-depth, and should not be
 *         relied upon for any critical functionality. It is intended to be used as
 *         a fail safe for the quoting engine signing invalid attestations.
 */
contract IssuanceHours is IIssuanceHours, Ownable2Step {
  /// The timezone offset in seconds from UTC. Can be negative (west of UTC) or positive (east of UTC)
  int256 public timezoneOffset;

  /// Constant for the number of seconds in an hour
  int256 constant HOUR_IN_SECONDS = 3_600;

  /**
   * @notice Event emitted when the timezone offset is set
   * @param  prevTimezoneOffset The previous timezone offset in seconds from UTC
   * @param  newTimezoneOffset  The new timezone offset in seconds from UTC
   */
  event SetTimezoneOffset(int256 prevTimezoneOffset, int256 newTimezoneOffset);

  /// Error emitted when the current time is not within the issuance hours
  error OutsideMarketHours();

  /// Error emitted when the timezone offset exceeds the maximum allowed value
  error MaximumOffsetExceeded();

  /**
   * @notice Constructor for the MarketIssuanceHours contract
   * @param  admin           The address of the admin for the contract
   * @param  _timezoneOffset The timezone offset in seconds from UTC
   * @dev    The timezone offset is used to determine the issuance hours for
   *         the market.
   */
  constructor(address admin, int256 _timezoneOffset) {
    _validateTimezoneOffset(_timezoneOffset);

    timezoneOffset = _timezoneOffset;

    _transferOwnership(admin);
  }

  /**
   * @notice Check if the current time is within the market hours
   * @dev    The function computes the day of the week based on the current block timestamp
   *         and checks if it is within the issuance hours. This does ignore holidays as it
   *         is only intended to be a fail safe for the quoting engine signing invalid attestations.
   */
  function checkIsValidHours() external view {
    uint256 adjustedTimestamp;
    if (timezoneOffset < 0) {
      // forge-lint: disable-next-line(unsafe-typecast)
      adjustedTimestamp = block.timestamp - uint256(-timezoneOffset);
    } else {
      // forge-lint: disable-next-line(unsafe-typecast)
      adjustedTimestamp = block.timestamp + uint256(timezoneOffset);
    }

    if (BokkyPooBahsDateTimeLibrary.getDayOfWeek(adjustedTimestamp) >= 6) {
      revert OutsideMarketHours();
    }
  }

  /**
   * @notice Set the timezone offset in seconds from UTC
   * @param  _timezoneOffset The new timezone offset in seconds from UTC
   * @dev    This function can only be called by the owner of the contract
   */
  function setTimezoneOffset(int256 _timezoneOffset) public onlyOwner {
    _validateTimezoneOffset(_timezoneOffset);

    emit SetTimezoneOffset(timezoneOffset, _timezoneOffset);

    timezoneOffset = _timezoneOffset;
  }

  /**
   * @notice Validate the timezone offset
   * @param  _timezoneOffset The timezone offset in seconds from UTC
   * @dev    This function checks if the timezone offset is within the allowed range
   *         of -12 to +14 hours. If it is not, it reverts with MaximumOffsetExceeded error.
   */
  function _validateTimezoneOffset(int256 _timezoneOffset) private pure {
    if (_timezoneOffset < -12 * HOUR_IN_SECONDS || _timezoneOffset > 14 * HOUR_IN_SECONDS) {
      revert MaximumOffsetExceeded();
    }
  }
}
