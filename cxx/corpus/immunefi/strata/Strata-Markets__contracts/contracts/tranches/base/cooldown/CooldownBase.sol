// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICooldown } from "../../interfaces/cooldown/ICooldown.sol";
import { AccessControlled } from "../../../governance/AccessControlled.sol";


abstract contract CooldownBase is ICooldown, AccessControlled {
    /// @dev Users can create multiple requests with separate finalization dates.
    /// @dev To prevent spamming, new requests are merged with the last one if the limit is reached.
    uint256 constant internal MAX_ACTIVE_REQUEST_SLOTS  = 70;
    /// @dev Maximum amount of active cooldown transfers where from != to
    uint256 constant internal PUBLIC_REQUEST_SLOTS_CAP  = 40;

    function initialize(
        address owner_,
        address acm_
    ) public virtual initializer {
        AccessControlled_init(owner_, acm_);
    }
}
