// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { StrataProtocolDeploymentBase } from "./StrataProtocolDeploymentBase.sol";
import { IStrataCDO } from "../../../contracts/tranches/interfaces/IStrataCDO.sol";

contract TrancheMaxMintTest is StrataProtocolDeploymentBase {
    function testJrtMaxMintRevertsWhenSharePriceBelowOne() public {
        _deployStrataStack();

        address receiver = makeAddr("receiver");
        uint256 shareSupply = 100e18;
        deal(address(jrtVault), receiver, shareSupply, true);

        uint256 mockedAssets = 50e18;
        vm.mockCall(
            address(cdo),
            abi.encodeWithSelector(IStrataCDO.totalAssets.selector, address(jrtVault)),
            abi.encode(mockedAssets)
        );

        jrtVault.maxMint(receiver);
    }
}
