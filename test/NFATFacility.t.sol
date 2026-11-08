// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.24;

import "dss-test/DssTest.sol";
import { NFATFacility } from "src/NFATFacility.sol";
import { NFATDeploy } from "deploy/NFATDeploy.sol";
import { NFATInit, NFATConfig } from "deploy/NFATInit.sol";
import { IERC721Errors } from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external;
}

contract IdentityNetworkMock {
    mapping(address => bool) public members;
    function setMember(address usr, bool status) external { members[usr] = status; }
    function isMember(address usr) external view returns (bool) { return members[usr]; }
}

contract ERC721ReceiverMock {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract BadReceiverMock {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0xdeadbeef;
    }
}

contract NFATFacilityTest is DssTest {
    DssInstance           dss;
    address               pauseProxy;
    GemLike               susds;
    IdentityNetworkMock   idNet;
    ERC721ReceiverMock    receiver;
    BadReceiverMock       badReceiver;
    NFATFacility          facility;

    address almProxy   = address(0xA1);
    address operator   = address(0xC1);
    address freezer    = address(0xC2);
    address prime1     = address(0xB1);
    address prime2     = address(0xB2);

    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event AddFreezer(address indexed usr);
    event RemoveFreezer(address indexed usr);
    event Stop();
    event Start();
    event Rescue(address indexed token, address indexed to, uint256 amount);
    event RescueDeposit(address indexed depositor, address indexed to, uint256 amount);
    event RescueCollectable(uint256 indexed tokenId, address indexed to, uint256 amount);
    event Subscribe(address indexed depositor, uint256 amount, bytes data);
    event Withdraw(address indexed depositor, uint256 amount);
    event Issue(address indexed to, uint256 indexed tokenId, uint256 amount);
    event Repay(address indexed sender, uint256 indexed tokenId, uint256 amount);
    event Collect(uint256 indexed tokenId, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        dss        = MCD.loadFromChainlog(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
        pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");
        susds      = GemLike(dss.chainlog.getAddress("SUSDS"));

        idNet       = new IdentityNetworkMock();
        receiver    = new ERC721ReceiverMock();
        badReceiver = new BadReceiverMock();

        address facility_ = NFATDeploy.deploy(address(this), pauseProxy, "Non-Fungible Allocation Token - Halo1", "NFAT-HALO1");
        facility = NFATFacility(facility_);

        address[] memory _freezers = new address[](1);
        _freezers[0] = freezer;
        NFATConfig memory cfg = NFATConfig({
            name:            "Non-Fungible Allocation Token - Halo1",
            symbol:          "NFAT-HALO1",
            almProxy:        almProxy,
            identityNetwork: address(0),
            baseURI:         "",
            operator:        operator,
            freezers:        _freezers,
            facilityKey:     "NFAT_FAC_HALO1"
        });
        vm.startPrank(pauseProxy);
        NFATInit.init(dss, facility_, cfg);
        vm.stopPrank();

        deal(address(susds), prime1, 1000 ether);
        deal(address(susds), prime2, 1000 ether);
        vm.prank(prime1); susds.approve(address(facility), type(uint256).max);
        vm.prank(prime2); susds.approve(address(facility), type(uint256).max);
    }

    // --- Helpers ---

    function _subscribe(address who, uint256 amount) internal {
        vm.prank(who); facility.subscribe(amount, "");
    }

    function _issue(address target, uint256 amount) internal returns (uint256 tokenId) {
        tokenId = vm.randomUint();
        vm.prank(operator); facility.issue(target, tokenId, amount);
    }

    function _repayToken(uint256 tokenId, uint256 amount) internal {
        deal(address(susds), address(this), susds.balanceOf(address(this)) + amount);
        susds.approve(address(facility), amount);
        facility.repay(tokenId, amount);
    }

    // --- Constructor ---

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        NFATFacility f = new NFATFacility(address(0x111), "Name", "SYM");

        assertEq(address(f.gem()), address(0x111));
        assertEq(f.name(), "Name");
        assertEq(f.symbol(), "SYM");
        assertEq(f.wards(address(this)), 1);
    }

    // --- Deploy & Init ---

    function testDeployAndInit() public {
        address f_ = NFATDeploy.deploy(address(this), pauseProxy, "SomeName", "SomeSymb");
        address[] memory cops = new address[](2);
        cops[0] = address(0xff1);
        cops[1] = address(0xff2);
        NFATConfig memory cfg = NFATConfig({
            name:            "SomeName",
            symbol:          "SomeSymb",
            almProxy:        address(0xaaa),
            identityNetwork: address(0x111),
            baseURI:         "someURI",
            operator:        address(0xbbb),
            freezers:        cops,
            facilityKey:     "FAC_KEY"
        });
        vm.startPrank(pauseProxy);
        NFATInit.init(dss, f_, cfg);
        vm.stopPrank();

        NFATFacility f = NFATFacility(f_);
        assertEq(address(f.gem()), address(susds));
        assertEq(f.name(), "SomeName");
        assertEq(f.symbol(), "SomeSymb");
        assertEq(f.wards(address(this)), 0);
        assertEq(f.wards(pauseProxy), 1);
        assertEq(f.recipient(), address(0xaaa));
        assertEq(address(f.identityNetwork()), address(0x111));
        assertEq(f.baseURI(), "someURI");
        assertEq(f.buds(address(0xbbb)), 1);
        assertEq(f.cops(cops[0]), 1);
        assertEq(f.cops(cops[1]), 1);
        assertEq(dss.chainlog.getAddress("FAC_KEY"), f_);
    }

    // --- Access Control ---

    function testAuth() public {
        checkAuth(address(facility), "NFATFacility");
    }

    function testModifiers() public {
        vm.startPrank(address(0xBEEF));
        checkModifier(address(facility), "NFATFacility/not-authorized", [
            facility.kiss.selector,
            facility.diss.selector,
            facility.addFreezer.selector,
            facility.removeFreezer.selector,
            facility.start.selector,
            facility.rescue.selector,
            facility.rescueDeposit.selector,
            facility.rescueCollectable.selector
        ]);
        vm.stopPrank();

        checkModifier(address(facility), "NFATFacility/not-operator", [
            facility.issue.selector
        ]);
        checkModifier(address(facility), "NFATFacility/not-freezer", [
            facility.stop.selector
        ]);
    }

    function testKissDiss() public {
        address who = address(0xb0b);
        assertEq(facility.buds(who), 0);

        vm.expectEmit(true, true, true, true);
        emit Kiss(who);
        vm.prank(pauseProxy); facility.kiss(who);
        assertEq(facility.buds(who), 1);

        vm.expectEmit(true, true, true, true);
        emit Diss(who);
        vm.prank(pauseProxy); facility.diss(who);
        assertEq(facility.buds(who), 0);
    }

    function testAddRemoveFreezer() public {
        address who = address(0xb0b);
        assertEq(facility.cops(who), 0);

        vm.expectEmit(true, true, true, true);
        emit AddFreezer(who);
        vm.prank(pauseProxy); facility.addFreezer(who);
        assertEq(facility.cops(who), 1);

        vm.expectEmit(true, true, true, true);
        emit RemoveFreezer(who);
        vm.prank(pauseProxy); facility.removeFreezer(who);
        assertEq(facility.cops(who), 0);
    }

    function testStopStart() public {
        _subscribe(prime1, 100 ether);
        vm.prank(operator); facility.issue(prime1, 1, 25 ether);
        _repayToken(1, 50 ether);

        vm.expectEmit(true, true, true, true);
        emit Stop();
        vm.prank(freezer); facility.stop();
        assertTrue(facility.stopped());

        vm.expectRevert("NFATFacility/stopped");
        vm.prank(prime1); facility.subscribe(25 ether, "");
        vm.expectRevert("NFATFacility/stopped");
        vm.prank(operator); facility.issue(prime1, 2, 25 ether);
        vm.expectRevert("NFATFacility/stopped");
        facility.repay(1, 10 ether);
        vm.expectRevert("NFATFacility/stopped");
        vm.prank(prime1); facility.collect(1, 50 ether);

        vm.expectEmit(true, true, true, true);
        emit Start();
        vm.prank(pauseProxy); facility.start();
        assertTrue(!facility.stopped());

        _subscribe(prime1, 25 ether);
        vm.prank(operator); facility.issue(prime1, 2, 25 ether);
        _repayToken(2, 10 ether);
        vm.prank(prime1); facility.collect(1, 50 ether);
    }

    function testFile() public {
        checkFileAddress(address(facility), "NFATFacility", ["recipient", "identityNetwork"]);
        checkFileString(address(facility), "NFATFacility", ["baseURI"]);
    }

    // --- Rescue ---

    function testRescue() public {
        address rescueTo = address(0xBEEF);

        // Rescue gem surplus
        deal(address(susds), address(facility), 100 ether);

        vm.expectEmit(true, true, true, true);
        emit Rescue(address(susds), rescueTo, 100 ether);
        vm.prank(pauseProxy); facility.rescue(address(susds), rescueTo, 100 ether);

        assertEq(susds.balanceOf(rescueTo), 100 ether);
        assertEq(susds.balanceOf(address(facility)), 0);

        // Rescue non-gem token
        address usds = dss.chainlog.getAddress("USDS");
        deal(usds, address(facility), 50 ether);

        vm.expectEmit(true, true, true, true);
        emit Rescue(usds, rescueTo, 50 ether);
        vm.prank(pauseProxy); facility.rescue(usds, rescueTo, 50 ether);

        assertEq(GemLike(usds).balanceOf(rescueTo), 50 ether);
        assertEq(GemLike(usds).balanceOf(address(facility)), 0);
    }

    function testRescueDeposit() public {
        _subscribe(prime1, 100 ether);

        address rescueTo = address(0xBEEF);

        vm.expectEmit(true, true, true, true);
        emit RescueDeposit(prime1, rescueTo, 60 ether);
        vm.prank(pauseProxy); facility.rescueDeposit(prime1, rescueTo, 60 ether);

        assertEq(facility.deposits(prime1), 40 ether);
        assertEq(susds.balanceOf(rescueTo), 60 ether);
        assertEq(susds.balanceOf(address(facility)), 40 ether);
    }

    function testRevertRescueDepositInsufficientDeposits() public {
        _subscribe(prime1, 100 ether);

        vm.expectRevert("NFATFacility/insufficient-deposits");
        vm.prank(pauseProxy); facility.rescueDeposit(prime1, address(0xBEEF), 101 ether);
    }

    function testRescueCollectable() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);
        _repayToken(tokenId, 80 ether);

        address rescueTo = address(0xBEEF);

        vm.expectEmit(true, true, true, true);
        emit RescueCollectable(tokenId, rescueTo, 50 ether);
        vm.prank(pauseProxy); facility.rescueCollectable(tokenId, rescueTo, 50 ether);

        assertEq(facility.collectable(tokenId), 30 ether);
        assertEq(susds.balanceOf(rescueTo), 50 ether);
        assertEq(susds.balanceOf(address(facility)), 30 ether);
    }

    function testRevertRescueCollectableInsufficientCollectable() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);
        _repayToken(tokenId, 10 ether);

        vm.expectRevert("NFATFacility/insufficient-collectable");
        vm.prank(pauseProxy); facility.rescueCollectable(tokenId, address(0xBEEF), 11 ether);
    }

    // --- Queue ---

    function testSubscribe() public {
        vm.expectEmit(true, true, true, true);
        emit Subscribe(prime1, 100 ether, "");
        _subscribe(prime1, 100 ether);

        assertEq(facility.deposits(prime1), 100 ether);
        assertEq(susds.balanceOf(address(facility)), 100 ether);

        // Second subscribe adds up
        _subscribe(prime1, 50 ether);

        assertEq(facility.deposits(prime1), 150 ether);
        assertEq(susds.balanceOf(address(facility)), 150 ether);
    }

    function testSubscribeZeroAmountWithData() public {
        bytes memory data = bytes("sample terms");
        uint256 depositsBefore = facility.deposits(prime1);

        vm.expectEmit(true, true, true, true);
        emit Subscribe(prime1, 0, data);
        vm.prank(prime1); facility.subscribe(0, data);

        assertEq(facility.deposits(prime1), depositsBefore);
    }

    function testWithdraw() public {
        _subscribe(prime1, 100 ether);

        // Partial withdraw
        vm.expectEmit(true, true, true, true);
        emit Withdraw(prime1, 40 ether);
        vm.prank(prime1); facility.withdraw(40 ether);

        assertEq(facility.deposits(prime1), 60 ether);
        assertEq(susds.balanceOf(prime1), 940 ether);

        // Withdraw remainder
        vm.prank(prime1); facility.withdraw(60 ether);

        assertEq(facility.deposits(prime1), 0);
        assertEq(susds.balanceOf(prime1), 1000 ether);
    }

    function testWithdrawWhenStopped() public {
        _subscribe(prime1, 100 ether);
        vm.prank(freezer); facility.stop();

        vm.prank(prime1); facility.withdraw(100 ether);

        assertEq(facility.deposits(prime1), 0);
        assertEq(susds.balanceOf(prime1), 1000 ether);
    }

    function testRevertWithdrawZeroAmount() public {
        vm.expectRevert("NFATFacility/zero-amount");
        vm.prank(prime1); facility.withdraw(0);
    }

    function testRevertWithdrawInsufficientDeposits() public {
        _subscribe(prime1, 100 ether);

        vm.expectRevert("NFATFacility/insufficient-deposits");
        vm.prank(prime1); facility.withdraw(101 ether);
    }

    // --- Issue ---

    function testIssue() public {
        _subscribe(prime1, 100 ether);

        // First issue
        uint256 tokenId0 = vm.randomUint();
        vm.expectEmit(true, true, true, true);
        emit Issue(prime1, tokenId0, 60 ether);
        vm.prank(operator); facility.issue(prime1, tokenId0, 60 ether);

        assertEq(facility.ownerOf(tokenId0), prime1);
        assertEq(facility.balanceOf(prime1), 1);
        assertEq(facility.deposits(prime1), 40 ether);
        assertEq(susds.balanceOf(almProxy), 60 ether);

        // Second issue
        uint256 tokenId1 = _issue(prime1, 30 ether);

        assertEq(facility.ownerOf(tokenId1), prime1);
        assertEq(facility.balanceOf(prime1), 2);
        assertEq(facility.deposits(prime1), 10 ether);
    }

    function testIssueZeroAmount() public {
        uint256 depositsBefore = facility.deposits(prime1);
        uint256 almBalBefore   = susds.balanceOf(almProxy);

        vm.prank(operator); facility.issue(prime1, 1, 0 ether);

        assertEq(facility.ownerOf(1), prime1);
        assertEq(facility.deposits(prime1), depositsBefore);
        assertEq(susds.balanceOf(almProxy), almBalBefore);
    }

    function testIssueWithIdentityNetwork() public {
        vm.prank(pauseProxy); facility.file("identityNetwork", address(idNet));
        idNet.setMember(prime1, true);

        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 50 ether);

        assertEq(facility.ownerOf(tokenId), prime1);
    }

    function testRevertIssueTokenIdZero() public {
        _subscribe(prime1, 100 ether);

        vm.expectRevert("NFATFacility/token-id-zero");
        vm.prank(operator); facility.issue(prime1, 0, 50 ether);
    }

    function testRevertIssueInsufficientDeposits() public {
        _subscribe(prime1, 100 ether);

        vm.expectRevert("NFATFacility/insufficient-deposits");
        vm.prank(operator); facility.issue(prime1, 1, 101 ether);
    }

    function testRevertIssueDuplicateTokenId() public {
        _subscribe(prime1, 200 ether);
        vm.prank(operator); facility.issue(prime1, 1, 50 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidSender.selector, address(0)));
        vm.prank(operator); facility.issue(prime1, 1, 50 ether);
    }

    function testRevertIssueTargetNotMember() public {
        vm.prank(pauseProxy); facility.file("identityNetwork", address(idNet));

        _subscribe(prime1, 100 ether);

        vm.expectRevert("NFATFacility/not-member");
        vm.prank(operator); facility.issue(prime1, 1, 50 ether);
    }

    // --- Repay ---

    function testRepay() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        // First repay
        deal(address(susds), address(this), 50 ether);
        susds.approve(address(facility), 50 ether);

        vm.expectEmit(true, true, true, true);
        emit Repay(address(this), tokenId, 50 ether);
        facility.repay(tokenId, 50 ether);

        assertEq(facility.collectable(tokenId), 50 ether);

        // Second repay accumulates
        _repayToken(tokenId, 20 ether);

        assertEq(facility.collectable(tokenId), 70 ether);
    }

    function testRevertRepayZeroAmount() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.expectRevert("NFATFacility/zero-amount");
        facility.repay(tokenId, 0);
    }

    function testRevertRepayInvalidToken() public {
        vm.expectRevert("NFATFacility/invalid-token");
        facility.repay(999, 1 ether);
    }

    // --- Collect ---

    function testCollect() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);
        _repayToken(tokenId, 80 ether);

        uint256 balBefore = susds.balanceOf(prime1);

        // Partial collect
        vm.expectEmit(true, true, true, true);
        emit Collect(tokenId, 30 ether);
        vm.prank(prime1); facility.collect(tokenId, 30 ether);

        assertEq(facility.collectable(tokenId), 50 ether);
        assertEq(susds.balanceOf(prime1), balBefore + 30 ether);

        // Collect remainder
        vm.prank(prime1); facility.collect(tokenId, 50 ether);

        assertEq(facility.collectable(tokenId), 0);
        assertEq(susds.balanceOf(prime1), balBefore + 80 ether);
    }

    function testCollectAfterTransfer() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);
        _repayToken(tokenId, 50 ether);

        vm.prank(prime1); facility.transferFrom(prime1, prime2, tokenId);

        assertEq(facility.collectable(tokenId), 50 ether);

        uint256 balBefore = susds.balanceOf(prime2);
        vm.prank(prime2); facility.collect(tokenId, 50 ether);

        assertEq(facility.collectable(tokenId), 0);
        assertEq(susds.balanceOf(prime2), balBefore + 50 ether);
    }

    function testCollectWithIdentityNetwork() public {
        vm.prank(pauseProxy); facility.file("identityNetwork", address(idNet));
        idNet.setMember(prime1, true);

        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);
        _repayToken(tokenId, 50 ether);

        uint256 balBefore = susds.balanceOf(prime1);
        vm.prank(prime1); facility.collect(tokenId, 50 ether);

        assertEq(facility.collectable(tokenId), 0);
        assertEq(susds.balanceOf(prime1), balBefore + 50 ether);
    }

    function testRevertCollectZeroAmount() public {
        vm.expectRevert("NFATFacility/zero-amount");
        vm.prank(prime1); facility.collect(0, 0);
    }

    function testRevertCollectInsufficientCollectable() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);
        _repayToken(tokenId, 10 ether);

        vm.expectRevert("NFATFacility/insufficient-collectable");
        vm.prank(prime1); facility.collect(tokenId, 11 ether);
    }

    function testRevertCollectNotOwner() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);
        _repayToken(tokenId, 50 ether);

        vm.expectRevert("NFATFacility/not-owner");
        vm.prank(prime2); facility.collect(tokenId, 50 ether);
    }

    function testRevertCollectNotMember() public {
        vm.prank(pauseProxy); facility.file("identityNetwork", address(idNet));
        idNet.setMember(prime1, true);

        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);
        _repayToken(tokenId, 50 ether);

        idNet.setMember(prime1, false);

        vm.expectRevert("NFATFacility/not-member");
        vm.prank(prime1); facility.collect(tokenId, 50 ether);
    }

    // --- ERC-721 ---

    function testTransferFrom() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.expectEmit(true, true, true, true);
        emit Transfer(prime1, prime2, tokenId);
        vm.prank(prime1); facility.transferFrom(prime1, prime2, tokenId);

        assertEq(facility.ownerOf(tokenId), prime2);
        assertEq(facility.balanceOf(prime1), 0);
        assertEq(facility.balanceOf(prime2), 1);
    }

    function testTransferFromWithApproval() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.prank(prime1); facility.approve(prime2, tokenId);
        assertEq(facility.getApproved(tokenId), prime2);

        vm.prank(prime2); facility.transferFrom(prime1, prime2, tokenId);

        assertEq(facility.ownerOf(tokenId), prime2);
        assertEq(facility.getApproved(tokenId), address(0)); // approval cleared
    }

    function testTransferFromWithOperatorApproval() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.prank(prime1); facility.setApprovalForAll(prime2, true);
        vm.prank(prime2); facility.transferFrom(prime1, prime2, tokenId);

        assertEq(facility.ownerOf(tokenId), prime2);
    }

    function testRevertTransferFromNotAuthorized() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, prime2, tokenId));
        vm.prank(prime2); facility.transferFrom(prime1, prime2, tokenId);
    }

    function testRevertTransferFromWrongFrom() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721IncorrectOwner.selector, prime2, tokenId, prime1));
        vm.prank(prime1); facility.transferFrom(prime2, prime2, tokenId);
    }

    function testRevertTransferFromZeroAddress() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(0)));
        vm.prank(prime1); facility.transferFrom(prime1, address(0), tokenId);
    }

    function testTransferFromWithIdentityNetwork() public {
        vm.prank(pauseProxy); facility.file("identityNetwork", address(idNet));
        idNet.setMember(prime1, true);
        idNet.setMember(prime2, true);

        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        idNet.setMember(prime2, false);
        vm.expectRevert("NFATFacility/not-member");
        vm.prank(prime1); facility.transferFrom(prime1, prime2, tokenId);

        idNet.setMember(prime2, true);
        vm.prank(prime1); facility.transferFrom(prime1, prime2, tokenId);
        assertEq(facility.ownerOf(tokenId), prime2);

        // Sender membership is not checked
        idNet.setMember(prime2, false);
        vm.prank(prime2); facility.transferFrom(prime2, prime1, tokenId);
        assertEq(facility.ownerOf(tokenId), prime1);
    }

    function testSafeTransferFrom() public {
        _subscribe(prime1, 100 ether);

        // To EOA
        uint256 tokenId0 = _issue(prime1, 50 ether);
        vm.prank(prime1); facility.safeTransferFrom(prime1, prime2, tokenId0);
        assertEq(facility.ownerOf(tokenId0), prime2);

        // To contract implementing onERC721Received
        uint256 tokenId1 = _issue(prime1, 50 ether);
        vm.prank(prime1); facility.safeTransferFrom(prime1, address(receiver), tokenId1, "test data");
        assertEq(facility.ownerOf(tokenId1), address(receiver));
    }

    function testRevertSafeTransferFromUnsafeRecipient() public {
        _subscribe(prime1, 100 ether);

        // Bad return value
        uint256 tokenId0 = _issue(prime1, 50 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(badReceiver)));
        vm.prank(prime1); facility.safeTransferFrom(prime1, address(badReceiver), tokenId0);

        // No onERC721Received at all
        uint256 tokenId1 = _issue(prime1, 50 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(facility)));
        vm.prank(prime1); facility.safeTransferFrom(prime1, address(facility), tokenId1);
    }

    function testApprove() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        // Owner approves
        vm.expectEmit(true, true, true, true);
        emit Approval(prime1, prime2, tokenId);
        vm.prank(prime1); facility.approve(prime2, tokenId);
        assertEq(facility.getApproved(tokenId), prime2);

        // Operator approves
        vm.prank(prime1); facility.setApprovalForAll(prime2, true);
        vm.prank(prime2); facility.approve(operator, tokenId);
        assertEq(facility.getApproved(tokenId), operator);
    }

    function testRevertApproveNotAuthorized() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidApprover.selector, prime2));
        vm.prank(prime2); facility.approve(prime2, tokenId);
    }

    function testSetApprovalForAll() public {
        vm.expectEmit(true, true, true, true);
        emit ApprovalForAll(prime1, prime2, true);
        vm.prank(prime1); facility.setApprovalForAll(prime2, true);

        assertTrue(facility.isApprovedForAll(prime1, prime2));
    }

    function testRevertSetApprovalForAllZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidOperator.selector, address(0)));
        vm.prank(prime1); facility.setApprovalForAll(address(0), true);
    }

    function testRevertOwnerOfInvalidToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999)));
        facility.ownerOf(999);
    }

    function testRevertBalanceOfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidOwner.selector, address(0)));
        facility.balanceOf(address(0));
    }

    function testRevertGetApprovedInvalidToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999)));
        facility.getApproved(999);
    }

    // --- Metadata & ERC-165 ---

    function testTokenURI() public {
        _subscribe(prime1, 100 ether);
        uint256 tokenId = _issue(prime1, 100 ether);
        assertEq(facility.baseURI(), "");
        assertEq(facility.tokenURI(tokenId), "");

        vm.prank(pauseProxy); facility.file("baseURI", "https://example.com/nfat/");

        assertEq(facility.baseURI(), "https://example.com/nfat/");
        assertEq(facility.tokenURI(tokenId), string.concat("https://example.com/nfat/", vm.toString(tokenId)));
    }

    function testMetadataAndERC165() public view {
        assertEq(facility.name(), "Non-Fungible Allocation Token - Halo1");
        assertEq(facility.symbol(), "NFAT-HALO1");
        assertTrue(facility.supportsInterface(0x01ffc9a7));  // ERC-165
        assertTrue(facility.supportsInterface(0x80ac58cd));  // ERC-721
        assertTrue(facility.supportsInterface(0x5b5e139f));  // ERC-721 Metadata
        assertTrue(!facility.supportsInterface(0xdeadbeef)); // random
    }
}
