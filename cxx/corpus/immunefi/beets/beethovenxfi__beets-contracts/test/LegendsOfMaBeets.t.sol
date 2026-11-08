// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {LegendsOfMaBeets} from "src/legends-of-mabeets/LegendsOfMaBeets.sol";
import {NftDescriptor} from "src/legends-of-mabeets/NftDescriptor.sol";
import {LevelNftDescriptor} from "src/legends-of-mabeets/LevelNftDescriptor.sol";

contract LegendsOfMaBeetsTest is Test {
    string SONIC_FORK_URL = "https://rpc.soniclabs.com";
    uint256 INITIAL_FORK_BLOCK_NUMBER = 10505083;
    uint256 sonicFork;

    LegendsOfMaBeets lomNftContract;

    error OwnableUnauthorizedAccount(address account);

    function setUp() public {
        sonicFork = vm.createSelectFork(SONIC_FORK_URL, INITIAL_FORK_BLOCK_NUMBER);

        NftDescriptor lomNftDescriptor = new NftDescriptor();
        lomNftContract = new LegendsOfMaBeets(lomNftDescriptor);
        // lomNftContract.setNFTDescriptor(lomNftDescriptor);
    }

    function testConstructor() public view {
        assertEq(lomNftContract.name(), "Legends of maBeets");
        assertEq(lomNftContract.symbol(), "LOM");
    }

    function testMint() public {
        uint256 amount = 100 ether;
        uint256 level = 10;

        address owner = vm.addr(1);

        uint256 id = lomNftContract.mint(owner, level, amount);
        LegendsOfMaBeets.PositionInfo memory position = lomNftContract.getPositionForId(id);

        assertEq(position.amount, amount);
        assertEq(position.level, level);
        assertEq(lomNftContract.ownerOf(id), owner);
        assertEq(lomNftContract.totalSupply(), 1);
    }

    function testMultiMint() public {
        uint256 amount1 = 100 ether;
        uint256 level1 = 10;
        uint256 amount2 = 200 ether;
        uint256 level2 = 5;
        uint256 amount3 = 120 ether;
        uint256 level3 = 3;

        address owner1 = vm.addr(1);
        address owner2 = vm.addr(2);

        uint256 id1 = lomNftContract.mint(owner1, level1, amount1);
        LegendsOfMaBeets.PositionInfo memory position1 = lomNftContract.getPositionForId(id1);

        assertEq(position1.amount, amount1);
        assertEq(position1.level, level1);
        assertEq(lomNftContract.ownerOf(id1), owner1);
        assertEq(lomNftContract.totalSupply(), 1);

        uint256 id2 = lomNftContract.mint(owner1, level2, amount2);
        LegendsOfMaBeets.PositionInfo memory position2 = lomNftContract.getPositionForId(id2);

        assertEq(position2.amount, amount2);
        assertEq(position2.level, level2);
        assertEq(lomNftContract.ownerOf(id2), owner1);
        assertEq(lomNftContract.totalSupply(), 2);

        uint256 id3 = lomNftContract.mint(owner2, level3, amount3);
        LegendsOfMaBeets.PositionInfo memory position3 = lomNftContract.getPositionForId(id3);

        assertEq(position3.amount, amount3);
        assertEq(position3.level, level3);
        assertEq(lomNftContract.ownerOf(id3), owner2);
        assertEq(lomNftContract.totalSupply(), 3);
    }

    function testMintMany() public {
        uint256 amount1 = 100 ether;
        uint256 level1 = 10;
        uint256 amount2 = 200 ether;
        uint256 level2 = 5;
        uint256 amount3 = 120 ether;
        uint256 level3 = 3;

        address owner1 = vm.addr(1);
        address owner2 = vm.addr(2);

        address[] memory owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner1;
        owners[2] = owner2;

        uint256[] memory levels = new uint256[](3);
        levels[0] = level1;
        levels[1] = level2;
        levels[2] = level3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amount1;
        amounts[1] = amount2;
        amounts[2] = amount3;

        lomNftContract.mintMany(owners, levels, amounts);
        LegendsOfMaBeets.PositionInfo memory position1 = lomNftContract.getPositionForId(1);

        assertEq(position1.amount, amount1);
        assertEq(position1.level, level1);
        assertEq(lomNftContract.ownerOf(1), owner1);
        assertEq(lomNftContract.totalSupply(), 3);

        LegendsOfMaBeets.PositionInfo memory position2 = lomNftContract.getPositionForId(2);

        assertEq(position2.amount, amount2);
        assertEq(position2.level, level2);
        assertEq(lomNftContract.ownerOf(2), owner1);

        LegendsOfMaBeets.PositionInfo memory position3 = lomNftContract.getPositionForId(3);

        assertEq(position3.amount, amount3);
        assertEq(position3.level, level3);
        assertEq(lomNftContract.ownerOf(3), owner2);
    }

    function testTransfer() public {
        uint256 amount1 = 100 ether;
        uint256 level1 = 10;

        address owner1 = vm.addr(1);
        address owner2 = vm.addr(2);

        uint256 id1 = lomNftContract.mint(owner1, level1, amount1);
        LegendsOfMaBeets.PositionInfo memory position1 = lomNftContract.getPositionForId(id1);

        assertEq(position1.amount, amount1);
        assertEq(position1.level, level1);
        assertEq(lomNftContract.ownerOf(id1), owner1);
        assertEq(lomNftContract.totalSupply(), 1);

        vm.prank(owner1);
        lomNftContract.safeTransferFrom(owner1, owner2, id1);
        assertEq(lomNftContract.ownerOf(id1), owner2);
    }

    function testOnlyOwnerCanMint() public {
        address user = vm.addr(1);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(user)));
        lomNftContract.mint(user, 10, 1000 ether);
    }

    function testNftTokenURI() public {
        uint256 amount = 100 ether;
        uint256 level = 10;

        address owner = vm.addr(1);

        uint256 id = lomNftContract.mint(owner, level, amount);
        string memory tokenURI = lomNftContract.tokenURI(id);

        assertEq(tokenURI, "https://beethoven-assets.s3.eu-central-1.amazonaws.com/mabeets-legends.png");
    }

    function testNonExistentTokenUri() public {
        uint256 id = 1;
        vm.expectRevert(abi.encodeWithSelector(LegendsOfMaBeets.NonExistentToken.selector));
        lomNftContract.tokenURI(id);
    }

    function testSetNFTDescriptor() public {
        uint256 amount = 100 ether;
        uint256 level = 10;

        address owner = vm.addr(1);

        uint256 id = lomNftContract.mint(owner, level, amount);
        string memory tokenURI = lomNftContract.tokenURI(id);
        assertEq(tokenURI, "https://beethoven-assets.s3.eu-central-1.amazonaws.com/mabeets-legends.png");

        LevelNftDescriptor newDescriptor = new LevelNftDescriptor();
        lomNftContract.setNFTDescriptor(newDescriptor);

        assertEq(address(lomNftContract.nftDescriptor()), address(newDescriptor));
        assertEq(
            lomNftContract.tokenURI(id), "https://beethoven-assets.s3.eu-central-1.amazonaws.com/mabeets-legends/10.png"
        );
    }

    function testSetNFTDescriptorOnlyOwner() public {
        LevelNftDescriptor newDescriptor = new LevelNftDescriptor();
        address user = vm.addr(1);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(user)));
        lomNftContract.setNFTDescriptor(newDescriptor);
    }

    function testGetPositionForId() public {
        uint256 amount = 100 ether;
        uint256 level = 10;

        address owner = vm.addr(1);

        uint256 id = lomNftContract.mint(owner, level, amount);
        LegendsOfMaBeets.PositionInfo memory position = lomNftContract.getPositionForId(id);

        assertEq(position.amount, amount);
        assertEq(position.level, level);
    }

    function testGetPositionForIdNonExistent() public {
        uint256 id = 1;
        LegendsOfMaBeets.PositionInfo memory position = lomNftContract.getPositionForId(id);

        assertEq(position.amount, 0);
        assertEq(position.level, 0);
    }
}
