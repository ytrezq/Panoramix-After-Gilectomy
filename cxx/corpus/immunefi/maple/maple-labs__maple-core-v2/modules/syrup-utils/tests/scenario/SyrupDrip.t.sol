// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { console2 as console, Test, Vm } from "../../modules/forge-std/src/Test.sol";

import { SyrupDrip } from "../../contracts/SyrupDrip.sol";

import { TestBase } from "../integration/TestBase.t.sol";

contract ScenarioTestBase is TestBase {

    SyrupDrip drip;

    bytes32[] proof;

    function setUp() public virtual override {
        super.setUp();

        drip = new SyrupDrip(address(syrup), address(globals), address(stsyrup));
    }

    function test_scenario_drip() external {
        // Fill up contract with Syrup.
        mintSyrup(address(drip), 1_000e18);

        // Allocate `month-1.json`
        vm.prank(governor.addr);
        drip.allocate(0xbda372a36362be11b0ff01e3315d3ad00b11a562ee5047aaf6d8a6678c3d78c5, 1624992000, 4);

        // Claim all except allocation `3`.
        claim({
            id:     0,
            owner:  0x343553366dA8546fc252aa25Fe3D25E1c782303B,
            amount: 3.2e18,
            proofs: [
                bytes32(0x44662f79fc38cb81708f0117770f8909d2fbab561fbe79a1bada69532af7ca35),
                bytes32(0xea9c918a8885f0bfd64f98fbb47cb6fe4fd3cd2c27dc574ce5b55c942e5fdbe8),
                bytes32(0x881d714b0c795ea64b0f1824b7af092e2ce7830ece5dbfa06d79d3e3ecf532e1)
            ]
        });

        claim({
            id:     2,
            owner:  0xe1cC612EcB2E854Efff82B0F9Cf5357c2D892adb,
            amount: 3.3e18,
            proofs: [
                bytes32(0x88a3dc0111ed0e005aafd907a5c20e0df45ea914adcaec8fc40234baa3ccb562),
                bytes32(0xad7048a7b9237dd3668a2650fca9fcfd06f0ead4e6cc944eb223c69816525021),
                bytes32(0)
            ]
        });

        claim({
            id:     4,
            owner:  0x1642812ECb2E853d3A882b0F9cf5357c2D892ADC,
            amount: 2.1e18,
            proofs: [
                bytes32(0x684b3a36f19fbebbf04009b34bfa0fe82a053e7b751b1e4844a5098e4e755426),
                bytes32(0xea9c918a8885f0bfd64f98fbb47cb6fe4fd3cd2c27dc574ce5b55c942e5fdbe8),
                bytes32(0x881d714b0c795ea64b0f1824b7af092e2ce7830ece5dbfa06d79d3e3ecf532e1)
            ]
        });

        claim({
            id:     1,
            owner:  0xccccCCccCb2DdddD3a882b2e9dF5357c2D892AdA,
            amount: 150e18,
            proofs: [
                bytes32(0x7470ac23e480005ebe99167bb4c6f114715b8b67ec2d19a94947cb571ae2f9a6),
                bytes32(0xad7048a7b9237dd3668a2650fca9fcfd06f0ead4e6cc944eb223c69816525021),
                bytes32(0)
            ]
        });

        // Allocate `month-2.json`
        vm.prank(governor.addr);
        drip.allocate(0xab0e7cda95e3c25b6cf234da44164f65a56144a0b66efeb8c9215e5bdd4855ee, 1627584000, 9);

        // Prove old allocation `3` can no longer be claimed.
        claim({
            id:     3,
            owner:  0x78C750a323169BD762a06567CaAD02A8E680e7b3,
            amount: 11.7e18,
            proofs: [
                bytes32(0xb31398d9df107913c267109e5e8ef660a8759a358130ad2b9fe54d1930b41f88),
                bytes32(0x881d714b0c795ea64b0f1824b7af092e2ce7830ece5dbfa06d79d3e3ecf532e1),
                bytes32(0)
            ],
            reverts: "SD:C:INVALID_PROOF"
        });

        // Prove new allocation `8` can be claimed.
        claim({
            id:     8,
            owner:  0x3ac750a323169BD762A06567cAad02A8E680E7b3,
            amount: 4.2e18,
            proofs: [
                bytes32(0x649266ba475f858a9bc241c94343d7194b47380bde5ea028ed6357ae53422747),
                bytes32(0xf7606e61faeb517633a260e5bb389f3252a0487d39702f158c42ba264fa77a43),
                bytes32(0x1faf411049de1eb9552d478d5dd69e898140dce0ca1b48e179cce562dc56a8e3)
            ]
        });

        // Prove allocation `7` can not be claimed past the deadline.
        vm.warp(1627584000 + 1 seconds);
        claim({
            id:     7,
            owner:  0xF7Cc612ECb2e854EfFf82b0F9cf5357c2d892aDb,
            amount: 2000000000000000001,
            proofs: [
                bytes32(0x11a6883e99343bc419026a697d74a1be043c679d48b9b290029f7b3b24d05503),
                bytes32(0xf7606e61faeb517633a260e5bb389f3252a0487d39702f158c42ba264fa77a43),
                bytes32(0x1faf411049de1eb9552d478d5dd69e898140dce0ca1b48e179cce562dc56a8e3)
            ],
            reverts: "SD:C:EXPIRED_DEADLINE"
        });
    }

    /**************************************************************************************************************************************/
    /*** Helper Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function claim(uint256 id, address owner, uint256 amount, bytes32[3] memory proofs, bytes memory reverts) internal {
        proof.push(proofs[0]);
        proof.push(proofs[1]);

        if (proofs[2] != bytes32(0)) {
            proof.push(proofs[2]);
        }

        uint256 balance = syrup.balanceOf(owner);

        if (reverts.length != 0) {
            vm.expectRevert(reverts);
        }

        vm.prank(owner);
        drip.claim(id, owner, amount, proof);

        if (reverts.length == 0) {
            assertEq(syrup.balanceOf(owner), balance + amount);
        }

        delete proof;
    }

    function claim(uint256 id, address owner, uint256 amount, bytes32[3] memory proofs) internal {
        claim(id, owner, amount, proofs, "");
    }

}
