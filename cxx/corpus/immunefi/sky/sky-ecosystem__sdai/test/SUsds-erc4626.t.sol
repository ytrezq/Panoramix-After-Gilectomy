// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.21;

import "erc4626-tests/ERC4626.test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { VatMock } from "test/mocks/VatMock.sol";
import { UsdsMock } from "test/mocks/UsdsMock.sol";
import { UsdsJoinMock } from "test/mocks/UsdsJoinMock.sol";

import { SUsds } from "src/SUsds.sol";

contract SUsdsERC4626Test is ERC4626Test {

    using stdStorage for StdStorage;

    VatMock vat;
    UsdsMock usds;
    UsdsJoinMock usdsJoin;

    SUsds sUsds;

    uint256 constant private RAY = 10**27;

    function setUp() public override {
        vat = new VatMock();
        usds = new UsdsMock();
        usdsJoin = new UsdsJoinMock(address(vat), address(usds));

        usds.rely(address(usdsJoin));
        vat.suck(address(123), address(usdsJoin), 100_000_000_000 * 10 ** 45);

        sUsds = SUsds(address(new ERC1967Proxy(address(new SUsds(address(usdsJoin), address(0))), abi.encodeCall(SUsds.initialize, ()))));
        vat.rely(address(sUsds));

        sUsds.file("ssr", 1000000001547125957863212448);

        vat.hope(address(usdsJoin));

        vm.warp(100 days);
        sUsds.drip();

        assertGt(sUsds.chi(), RAY);

        _underlying_ = address(usds);
        _vault_ = address(sUsds);
        _delta_ = 0;
        _vaultMayBeEmpty = true;
        _unlimitedAmount = false;
    }

    // setup initial vault state
    function setUpVault(Init memory init) public override {
        for (uint256 i = 0; i < N; i++) {
            init.share[i] %= 1_000_000_000 ether;
            init.asset[i] %= 1_000_000_000 ether;
            vm.assume(init.user[i] != address(0) && init.user[i] != address(sUsds));
        }
        super.setUpVault(init);
    }

    // setup initial yield
    function setUpYield(Init memory init) public override {
        vm.assume(init.yield >= 0);
        init.yield %= 1_000_000_000 ether;
        uint256 gain = uint256(init.yield);

        uint256 supply = sUsds.totalSupply();
        if (supply > 0) {
            uint256 nChi = gain * RAY / supply + sUsds.chi();
            uint256 chiRho = (block.timestamp << 192) + nChi;
            vm.store(
                address(sUsds),
                bytes32(uint256(5)),
                bytes32(chiRho)
            );
            assertEq(uint256(sUsds.chi()), nChi);
            assertEq(uint256(sUsds.rho()), block.timestamp);
            vat.suck(address(sUsds.vow()), address(this), gain * RAY);
            usdsJoin.exit(address(sUsds), gain);
        }
    }

}
