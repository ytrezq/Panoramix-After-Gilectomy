// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ConfigurationTestHelper} from "../configuration/ConfigurationTestHelper.sol";
import {DefaultDegenNFT} from "../../helpers/DefaultDegenNFT.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {GeneralMock} from "@gearbox-protocol/core-v3/contracts/test/mocks/GeneralMock.sol";

contract InvalidCreditFacade {
    address public creditManager;

    constructor(address _creditManager) {
        creditManager = _creditManager;
    }
}

contract DefaultDegenNFTTest is ConfigurationTestHelper {
    DefaultDegenNFT public degenNFT;
    address public user1;
    address public user2;
    address public invalidCreditFacade;

    function setUp() public override {
        super.setUp();
        degenNFT = new DefaultDegenNFT(address(marketConfigurator), "Test Degen NFT", "DEGEN");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        invalidCreditFacade = address(new InvalidCreditFacade(address(creditManager)));
    }

    function test_DD_01_mint() public {
        vm.prank(admin);
        degenNFT.setMinter(address(this));

        degenNFT.mint(user1, 3);

        assertEq(degenNFT.balanceOf(user1), 3, "Incorrect balance after mint");
        assertEq(degenNFT.totalSupply(), 3, "Incorrect total supply after mint");

        uint256 expectedTokenId;
        for (uint256 i = 0; i < 3; ++i) {
            expectedTokenId = (uint256(uint160(user1)) << 40) + i;
            assertTrue(degenNFT.ownerOf(expectedTokenId) == user1, "Incorrect token owner");
        }
    }

    function test_DD_02_mintMultipleUsers() public {
        vm.prank(admin);
        degenNFT.setMinter(address(this));

        degenNFT.mint(user1, 2);
        degenNFT.mint(user2, 3);

        assertEq(degenNFT.balanceOf(user1), 2, "Incorrect user1 balance");
        assertEq(degenNFT.balanceOf(user2), 3, "Incorrect user2 balance");
        assertEq(degenNFT.totalSupply(), 5, "Incorrect total supply");
    }

    function test_DD_03_burnByCreditFacade() public {
        vm.prank(admin);
        degenNFT.setMinter(address(this));
        degenNFT.mint(user1, 5);

        vm.prank(address(creditFacade));
        degenNFT.burn(user1, 3);

        assertEq(degenNFT.balanceOf(user1), 2, "Incorrect balance after burn");
        assertEq(degenNFT.totalSupply(), 2, "Incorrect total supply after burn");
    }

    function test_DD_04_burnByEmergencyAdmin() public {
        vm.prank(admin);
        degenNFT.setMinter(address(this));
        degenNFT.mint(user1, 5);

        vm.prank(emergencyAdmin);
        degenNFT.burn(user1, 3);

        assertEq(degenNFT.balanceOf(user1), 2, "Incorrect balance after burn");
        assertEq(degenNFT.totalSupply(), 2, "Incorrect total supply after burn");
    }

    function test_DD_05_burnRevertIfInsufficientBalance() public {
        vm.prank(admin);
        degenNFT.setMinter(address(this));
        degenNFT.mint(user1, 2);

        vm.prank(address(creditFacade));
        vm.expectRevert("ERC721: invalid token ID");
        degenNFT.burn(user1, 3);
    }

    function test_DD_06_onlyMinterCanMint() public {
        vm.prank(admin);
        degenNFT.setMinter(user1);

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(DefaultDegenNFT.CallerIsNotMinterException.selector, user2));
        degenNFT.mint(user2, 1);
    }

    function test_DD_07_onlyCreditFacadeOrEmergencyAdminCanBurn() public {
        vm.prank(admin);
        degenNFT.setMinter(address(this));
        degenNFT.mint(user1, 1);

        vm.prank(invalidCreditFacade);
        vm.expectRevert(
            abi.encodeWithSelector(
                DefaultDegenNFT.CallerIsNotCreditFacadeOrEmergencyAdminException.selector, invalidCreditFacade
            )
        );
        degenNFT.burn(user1, 1);
    }

    function test_DD_08_onlyAdminCanSetMinter() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(DefaultDegenNFT.CallerIsNotAdminException.selector, user1));
        degenNFT.setMinter(user2);

        vm.prank(admin);
        degenNFT.setMinter(user2);
        assertEq(degenNFT.minter(), user2, "Minter not set correctly");
    }

    function test_DD_09_setMinter() public {
        vm.prank(admin);
        degenNFT.setMinter(user1);
        assertEq(degenNFT.minter(), user1, "Minter not set correctly");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit DefaultDegenNFT.SetMinter(user2);
        degenNFT.setMinter(user2);
    }

    function test_DD_10_setBaseUri() public {
        string memory newUri = "https://api.example.com/token/";

        vm.prank(admin);
        degenNFT.setBaseUri(newUri);

        vm.prank(admin);
        degenNFT.setMinter(address(this));
        degenNFT.mint(user1, 1);

        uint256 tokenId = uint256(uint160(user1)) << 40;
        assertEq(degenNFT.tokenURI(tokenId), newUri, "Base URI not set correctly");
    }

    function test_DD_11_transferRestrictions() public {
        vm.prank(admin);
        degenNFT.setMinter(address(this));
        degenNFT.mint(user1, 1);

        uint256 tokenId = uint256(uint160(user1)) << 40;

        vm.prank(user1);
        vm.expectRevert(DefaultDegenNFT.NotImplementedException.selector);
        degenNFT.transferFrom(user1, user2, tokenId);

        vm.prank(user1);
        vm.expectRevert(DefaultDegenNFT.NotImplementedException.selector);
        degenNFT.safeTransferFrom(user1, user2, tokenId);

        vm.prank(user1);
        vm.expectRevert(DefaultDegenNFT.NotImplementedException.selector);
        degenNFT.approve(user2, tokenId);

        vm.prank(user1);
        vm.expectRevert(DefaultDegenNFT.NotImplementedException.selector);
        degenNFT.setApprovalForAll(user2, true);
    }
}
