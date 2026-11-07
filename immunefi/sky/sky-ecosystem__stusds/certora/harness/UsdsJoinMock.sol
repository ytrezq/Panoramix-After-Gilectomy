// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.21;

import { UsdsMock } from "certora/harness/UsdsMock.sol";

interface VatLike {
    function move(address, address, uint256) external;
}

contract UsdsJoinMock {
    VatLike public vat;
    UsdsMock public usds;

    function join(address usr, uint256 wad) external {
        vat.move(address(this), usr, wad * 10**27);
        usds.burn(msg.sender, wad);
    }

    function exit(address usr, uint256 wad) external {
        vat.move(msg.sender, address(this), wad * 10**27);
        usds.mint(usr, wad);
    }
}
