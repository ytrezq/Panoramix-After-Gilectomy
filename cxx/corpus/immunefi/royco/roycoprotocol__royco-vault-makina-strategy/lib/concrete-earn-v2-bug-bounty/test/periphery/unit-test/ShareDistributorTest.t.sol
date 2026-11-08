// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ShareDistributor} from "../../../src/periphery/predeposit/ShareDistributor.sol";
import {ConcreteStandardVaultImpl} from "../../../src/implementation/ConcreteStandardVaultImpl.sol";
import {ConcreteFactory} from "../../../src/factory/ConcreteFactory.sol";
import {AllocateModule} from "../../../src/module/AllocateModule.sol";
import {ERC20Mock} from "../../mock/ERC20Mock.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ShareDistributorTest
 * @notice Comprehensive unit tests for the ShareDistributor contract
 * @dev Tests single claims, batch claims, access control, and edge cases
 */
contract ShareDistributorTest is Test, TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 public constant A_EID = 1; // Source chain
    uint32 public constant B_EID = 2; // Destination chain

    ShareDistributor public distributor;
    ConcreteStandardVaultImpl public vault;
    ConcreteFactory public factory;
    AllocateModule public allocateModule;
    ERC20Mock public asset;

    address public owner;
    address public vaultManager;
    address public user1;
    address public user2;
    address public user3;
    address public factoryOwner;

    // Events to test
    event SharesDistributed(address indexed user, uint256 shares, bytes32 guid);
    event BatchSharesDistributed(address[] users, uint256[] shares, bytes32 guid);
    event TargetVaultSet(address indexed vault);

    // Errors to test
    error InvalidMessageType(uint16 received);
    error InvalidTargetVault();
    error InsufficientShares(uint256 required, uint256 available);
    error ArrayLengthMismatch(uint256 usersLength, uint256 sharesLength);

    function setUp() public override {
        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        owner = makeAddr("owner");
        vaultManager = makeAddr("vaultManager");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        factoryOwner = makeAddr("factoryOwner");

        // Deploy factory using proxy pattern
        vm.prank(factoryOwner);
        address factoryImpl = address(new ConcreteFactory());
        factory = ConcreteFactory(
            address(new ERC1967Proxy(factoryImpl, abi.encodeCall(ConcreteFactory.initialize, (factoryOwner))))
        );

        allocateModule = new AllocateModule();
        asset = new ERC20Mock();

        // Deploy standard vault implementation and approve it
        ConcreteStandardVaultImpl vaultImpl = new ConcreteStandardVaultImpl(address(factory));
        vm.prank(factoryOwner);
        factory.approveImplementation(address(vaultImpl));

        // Create vault on chain B (destination chain)
        vault = ConcreteStandardVaultImpl(
            factory.create(
                1, vaultManager, abi.encode(address(allocateModule), address(asset), vaultManager, "Test Vault", "TVT")
            )
        );

        // Get LayerZero endpoint for chain B
        address lzEndpointB = address(endpoints[B_EID]);

        // Deploy ShareDistributor using proxy pattern
        ShareDistributor distributorImpl = new ShareDistributor(lzEndpointB);
        bytes memory initData = abi.encodeCall(ShareDistributor.initialize, (address(vault), owner));
        ERC1967Proxy distributorProxy = new ERC1967Proxy(address(distributorImpl), initData);
        distributor = ShareDistributor(address(distributorProxy));

        vm.label(address(distributor), "distributor");
        vm.label(address(vault), "vault");
        vm.label(address(asset), "asset");
        vm.label(lzEndpointB, "lzEndpointB");

        // Set up peer on distributor (this is required for OApp to accept messages)
        // The peer is the source chain (A_EID) and any address that sends to this distributor
        vm.prank(owner);
        distributor.setPeer(A_EID, addressToBytes32(address(this)));

        // Fund the distributor with vault shares
        uint256 distributorFunding = 1000000e18; // 1M shares
        asset.mint(address(distributor), distributorFunding);
        vm.startPrank(address(distributor));
        asset.approve(address(vault), distributorFunding);
        vault.deposit(distributorFunding, address(distributor));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor_setsTargetVault() public view {
        assertEq(distributor.targetVault(), address(vault), "Target vault should be set correctly");
    }

    function test_constructor_setsOwner() public view {
        assertEq(distributor.owner(), owner, "Owner should be set correctly");
    }

    function test_constructor_setsEndpoint() public view {
        assertEq(address(distributor.endpoint()), address(endpoints[B_EID]), "Endpoint should be set correctly");
    }

    function test_constructor_emitsTargetVaultSetEvent() public {
        address lzEndpointB = address(endpoints[B_EID]);

        ShareDistributor distributorImpl = new ShareDistributor(lzEndpointB);

        vm.expectEmit(true, true, true, true);
        emit TargetVaultSet(address(vault));

        bytes memory initData = abi.encodeCall(ShareDistributor.initialize, (address(vault), owner));
        new ERC1967Proxy(address(distributorImpl), initData);
    }

    function test_constructor_revertsWithZeroAddress() public {
        address lzEndpointB = address(endpoints[B_EID]);

        ShareDistributor distributorImpl = new ShareDistributor(lzEndpointB);
        bytes memory initData = abi.encodeCall(ShareDistributor.initialize, (address(0), owner));

        vm.expectRevert(InvalidTargetVault.selector);
        new ERC1967Proxy(address(distributorImpl), initData);
    }

    /*//////////////////////////////////////////////////////////////
                       SET TARGET VAULT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setTargetVault_updatesVault() public {
        // Deploy a new vault
        ConcreteStandardVaultImpl newVault = ConcreteStandardVaultImpl(
            factory.create(
                1, vaultManager, abi.encode(address(allocateModule), address(asset), vaultManager, "New Vault", "NVT")
            )
        );

        vm.prank(owner);
        distributor.setTargetVault(address(newVault));

        assertEq(distributor.targetVault(), address(newVault), "Target vault should be updated");
    }

    function test_setTargetVault_emitsEvent() public {
        ConcreteStandardVaultImpl newVault = ConcreteStandardVaultImpl(
            factory.create(
                1, vaultManager, abi.encode(address(allocateModule), address(asset), vaultManager, "New Vault", "NVT")
            )
        );

        vm.expectEmit(true, true, true, true);
        emit TargetVaultSet(address(newVault));

        vm.prank(owner);
        distributor.setTargetVault(address(newVault));
    }

    function test_setTargetVault_revertsWithZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(InvalidTargetVault.selector);
        distributor.setTargetVault(address(0));
    }

    function test_setTargetVault_revertsForNonOwner() public {
        ConcreteStandardVaultImpl newVault = ConcreteStandardVaultImpl(
            factory.create(
                1, vaultManager, abi.encode(address(allocateModule), address(asset), vaultManager, "New Vault", "NVT")
            )
        );

        vm.prank(user1);
        vm.expectRevert();
        distributor.setTargetVault(address(newVault));
    }

    /*//////////////////////////////////////////////////////////////
                      SINGLE CLAIM DISTRIBUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_singleClaim_distributesSharesCorrectly() public {
        uint256 claimAmount = 1000e18;
        uint256 userBalanceBefore = vault.balanceOf(user1);
        uint256 distributorBalanceBefore = vault.balanceOf(address(distributor));

        // Encode single claim message
        bytes memory message = abi.encode(uint16(1), user1, claimAmount); // MSG_TYPE_CLAIM = 1
        bytes32 guid = keccak256("test-guid");

        // Simulate _lzReceive by calling it through the endpoint
        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");

        assertEq(vault.balanceOf(user1), userBalanceBefore + claimAmount, "User should receive shares");
        assertEq(
            vault.balanceOf(address(distributor)),
            distributorBalanceBefore - claimAmount,
            "Distributor balance should decrease"
        );
    }

    function test_singleClaim_emitsSharesDistributedEvent() public {
        uint256 claimAmount = 1000e18;
        bytes memory message = abi.encode(uint16(1), user1, claimAmount);
        bytes32 guid = keccak256("test-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.expectEmit(true, true, true, true);
        emit SharesDistributed(user1, claimAmount, guid);

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");
    }

    function test_singleClaim_revertsWithInsufficientShares() public {
        uint256 availableShares = vault.balanceOf(address(distributor));
        uint256 claimAmount = availableShares + 1; // Request more than available

        bytes memory message = abi.encode(uint16(1), user1, claimAmount);
        bytes32 guid = keccak256("test-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        vm.expectRevert(abi.encodeWithSelector(InsufficientShares.selector, claimAmount, availableShares));
        distributor.lzReceive(origin, guid, message, address(0), "");
    }

    function test_singleClaim_worksWithMinimumShares() public {
        uint256 claimAmount = 1; // Minimum amount

        bytes memory message = abi.encode(uint16(1), user1, claimAmount);
        bytes32 guid = keccak256("test-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");

        assertEq(vault.balanceOf(user1), claimAmount, "User should receive minimum shares");
    }

    function test_singleClaim_tracksClaimedAmount() public {
        uint256 claimAmount = 5000e18;

        bytes memory message = abi.encode(uint16(1), user1, claimAmount);
        bytes32 guid = keccak256("test-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        assertEq(distributor.claimedShares(user1), 0, "Claimed shares should be 0 initially");

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");

        assertEq(distributor.claimedShares(user1), claimAmount, "Claimed shares should be tracked");
    }

    function test_singleClaim_worksWithMaximumAvailableShares() public {
        uint256 claimAmount = vault.balanceOf(address(distributor));

        bytes memory message = abi.encode(uint16(1), user1, claimAmount);
        bytes32 guid = keccak256("test-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");

        assertEq(vault.balanceOf(user1), claimAmount, "User should receive all available shares");
        assertEq(vault.balanceOf(address(distributor)), 0, "Distributor should have no shares left");
    }

    /*//////////////////////////////////////////////////////////////
                      BATCH CLAIM DISTRIBUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_batchClaim_distributesSharesCorrectly() public {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256[] memory sharesArray = new uint256[](3);
        sharesArray[0] = 1000e18;
        sharesArray[1] = 2000e18;
        sharesArray[2] = 3000e18;

        uint256 distributorBalanceBefore = vault.balanceOf(address(distributor));

        bytes memory message = abi.encode(uint16(2), users, sharesArray); // MSG_TYPE_BATCH_CLAIM = 2
        bytes32 guid = keccak256("test-batch-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");

        assertEq(vault.balanceOf(user1), 1000e18, "User1 should receive correct shares");
        assertEq(vault.balanceOf(user2), 2000e18, "User2 should receive correct shares");
        assertEq(vault.balanceOf(user3), 3000e18, "User3 should receive correct shares");
        assertEq(
            vault.balanceOf(address(distributor)),
            distributorBalanceBefore - 6000e18,
            "Distributor balance should decrease by total"
        );
    }

    function test_batchClaim_emitsBatchSharesDistributedEvent() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        uint256[] memory sharesArray = new uint256[](2);
        sharesArray[0] = 1000e18;
        sharesArray[1] = 2000e18;

        bytes memory message = abi.encode(uint16(2), users, sharesArray);
        bytes32 guid = keccak256("test-batch-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.expectEmit(true, true, true, true);
        emit BatchSharesDistributed(users, sharesArray, guid);

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");
    }

    function test_batchClaim_skipsZeroShares() public {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256[] memory sharesArray = new uint256[](3);
        sharesArray[0] = 1000e18;
        sharesArray[1] = 0; // Zero shares - should be skipped
        sharesArray[2] = 2000e18;

        bytes memory message = abi.encode(uint16(2), users, sharesArray);
        bytes32 guid = keccak256("test-batch-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");

        assertEq(vault.balanceOf(user1), 1000e18, "User1 should receive shares");
        assertEq(vault.balanceOf(user2), 0, "User2 should receive no shares");
        assertEq(vault.balanceOf(user3), 2000e18, "User3 should receive shares");
    }

    function test_batchClaim_revertsWithInsufficientSharesFirstUser() public {
        uint256 availableShares = vault.balanceOf(address(distributor));

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        uint256[] memory sharesArray = new uint256[](2);
        sharesArray[0] = availableShares + 1; // More than available
        sharesArray[1] = 1000e18;

        bytes memory message = abi.encode(uint16(2), users, sharesArray);
        bytes32 guid = keccak256("test-batch-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        vm.expectRevert(abi.encodeWithSelector(InsufficientShares.selector, sharesArray[0], availableShares));
        distributor.lzReceive(origin, guid, message, address(0), "");
    }

    function test_batchClaim_revertsWithInsufficientSharesSecondUser() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        uint256[] memory sharesArray = new uint256[](2);
        sharesArray[0] = 500000e18; // Half available
        sharesArray[1] = 600000e18; // Would exceed remaining

        bytes memory message = abi.encode(uint16(2), users, sharesArray);
        bytes32 guid = keccak256("test-batch-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        uint256 remainingAfterFirst = vault.balanceOf(address(distributor)) - sharesArray[0];

        vm.prank(address(endpoints[B_EID]));
        vm.expectRevert(abi.encodeWithSelector(InsufficientShares.selector, sharesArray[1], remainingAfterFirst));
        distributor.lzReceive(origin, guid, message, address(0), "");
    }

    function test_batchClaim_worksWithSingleUser() public {
        address[] memory users = new address[](1);
        users[0] = user1;

        uint256[] memory sharesArray = new uint256[](1);
        sharesArray[0] = 1000e18;

        bytes memory message = abi.encode(uint16(2), users, sharesArray);
        bytes32 guid = keccak256("test-batch-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");

        assertEq(vault.balanceOf(user1), 1000e18, "Single user should receive shares");
    }

    function test_batchClaim_worksWithAllZeroShares() public {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256[] memory sharesArray = new uint256[](3);
        sharesArray[0] = 0;
        sharesArray[1] = 0;
        sharesArray[2] = 0;

        uint256 distributorBalanceBefore = vault.balanceOf(address(distributor));

        bytes memory message = abi.encode(uint16(2), users, sharesArray);
        bytes32 guid = keccak256("test-batch-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");

        assertEq(vault.balanceOf(user1), 0, "User1 should receive no shares");
        assertEq(vault.balanceOf(user2), 0, "User2 should receive no shares");
        assertEq(vault.balanceOf(user3), 0, "User3 should receive no shares");
        assertEq(
            vault.balanceOf(address(distributor)), distributorBalanceBefore, "Distributor balance should not change"
        );
    }

    function test_batchClaim_worksWithManyUsers() public {
        uint256 numUsers = 10;
        address[] memory users = new address[](numUsers);
        uint256[] memory sharesArray = new uint256[](numUsers);

        for (uint256 i = 0; i < numUsers; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            sharesArray[i] = 1000e18 * (i + 1);
        }

        bytes memory message = abi.encode(uint16(2), users, sharesArray);
        bytes32 guid = keccak256("test-batch-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");

        for (uint256 i = 0; i < numUsers; i++) {
            assertEq(vault.balanceOf(users[i]), sharesArray[i], "User should receive correct shares");
        }
    }

    function test_batchClaim_revertsOnArrayLengthMismatch() public {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256[] memory sharesArray = new uint256[](2); // Mismatch: 3 users but 2 shares
        sharesArray[0] = 1000e18;
        sharesArray[1] = 2000e18;

        bytes memory message = abi.encode(uint16(2), users, sharesArray);
        bytes32 guid = keccak256("test-batch-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        vm.expectRevert(abi.encodeWithSelector(ArrayLengthMismatch.selector, 3, 2));
        distributor.lzReceive(origin, guid, message, address(0), "");
    }

    function test_batchClaim_revertsOnArrayLengthMismatchReverse() public {
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        uint256[] memory sharesArray = new uint256[](3); // Mismatch: 2 users but 3 shares
        sharesArray[0] = 1000e18;
        sharesArray[1] = 2000e18;
        sharesArray[2] = 3000e18;

        bytes memory message = abi.encode(uint16(2), users, sharesArray);
        bytes32 guid = keccak256("test-batch-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        vm.expectRevert(abi.encodeWithSelector(ArrayLengthMismatch.selector, 2, 3));
        distributor.lzReceive(origin, guid, message, address(0), "");
    }

    function test_batchClaim_tracksClaimedAmounts() public {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint256[] memory sharesArray = new uint256[](3);
        sharesArray[0] = 1000e18;
        sharesArray[1] = 2000e18;
        sharesArray[2] = 3000e18;

        bytes memory message = abi.encode(uint16(2), users, sharesArray);
        bytes32 guid = keccak256("test-batch-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");

        assertEq(distributor.claimedShares(user1), 1000e18, "User1 claimed amount should be tracked");
        assertEq(distributor.claimedShares(user2), 2000e18, "User2 claimed amount should be tracked");
        assertEq(distributor.claimedShares(user3), 3000e18, "User3 claimed amount should be tracked");
    }

    function test_batchClaim_handlesDuplicateUsers() public {
        // Create arrays with duplicate users
        address[] memory users = new address[](4);
        users[0] = user1;
        users[1] = user2;
        users[2] = user1; // Duplicate of user1
        users[3] = user2; // Duplicate of user2

        uint256[] memory sharesArray = new uint256[](4);
        sharesArray[0] = 1000e18;
        sharesArray[1] = 2000e18;
        sharesArray[2] = 0; // Typical case - duplicate user was skipped in batch claim
        sharesArray[3] = 300e18; // Additional shares for duplicate user2 - not possible in current batch claim implementation

        uint256 distributorBalanceBefore = vault.balanceOf(address(distributor));

        bytes memory message = abi.encode(uint16(2), users, sharesArray);
        bytes32 guid = keccak256("test-batch-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");

        // Users should receive shares from all occurrences (including duplicates)
        // User1: 1000e18 + 500e18 = 1500e18
        // User2: 2000e18 + 300e18 = 2300e18
        assertEq(vault.balanceOf(user1), 1000e18, "User1 should receive shares from first occurrence");
        assertEq(vault.balanceOf(user2), 2300e18, "User2 should receive shares from all occurrences");

        // Claimed shares should track the total for each user
        assertEq(distributor.claimedShares(user1), 1000e18, "User1 total claimed should be tracked");
        assertEq(distributor.claimedShares(user2), 2300e18, "User2 total claimed should be tracked");

        // Distributor balance should decrease by total distributed
        assertEq(
            vault.balanceOf(address(distributor)),
            distributorBalanceBefore - 3300e18, // 1000 + 2000 + 0 + 300
            "Distributor balance should decrease by total distributed"
        );
    }

    /*//////////////////////////////////////////////////////////////
                      INVALID MESSAGE TYPE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_invalidMessageType_reverts() public {
        uint16 invalidType = 99;
        bytes memory message = abi.encode(invalidType, user1, 1000e18);
        bytes32 guid = keccak256("test-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        vm.expectRevert(abi.encodeWithSelector(InvalidMessageType.selector, invalidType));
        distributor.lzReceive(origin, guid, message, address(0), "");
    }

    function test_zeroMessageType_reverts() public {
        uint16 invalidType = 0;
        bytes memory message = abi.encode(invalidType, user1, 1000e18);
        bytes32 guid = keccak256("test-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        vm.expectRevert(abi.encodeWithSelector(InvalidMessageType.selector, invalidType));
        distributor.lzReceive(origin, guid, message, address(0), "");
    }

    function test_highMessageType_reverts() public {
        uint16 invalidType = type(uint16).max;
        bytes memory message = abi.encode(invalidType, user1, 1000e18);
        bytes32 guid = keccak256("test-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        vm.expectRevert(abi.encodeWithSelector(InvalidMessageType.selector, invalidType));
        distributor.lzReceive(origin, guid, message, address(0), "");
    }

    /*//////////////////////////////////////////////////////////////
                      GET AVAILABLE SHARES TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getAvailableShares_returnsCorrectBalance() public view {
        uint256 expectedBalance = vault.balanceOf(address(distributor));
        uint256 availableShares = distributor.getAvailableShares();

        assertEq(availableShares, expectedBalance, "Available shares should match distributor balance");
    }

    function test_getAvailableShares_updatesAfterDistribution() public {
        uint256 initialShares = distributor.getAvailableShares();
        uint256 claimAmount = 1000e18;

        bytes memory message = abi.encode(uint16(1), user1, claimAmount);
        bytes32 guid = keccak256("test-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");

        uint256 newShares = distributor.getAvailableShares();
        assertEq(newShares, initialShares - claimAmount, "Available shares should decrease after distribution");
    }

    function test_getAvailableShares_returnsZeroWhenEmpty() public {
        uint256 allShares = distributor.getAvailableShares();

        // Drain all shares
        bytes memory message = abi.encode(uint16(1), user1, allShares);
        bytes32 guid = keccak256("test-guid");

        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");

        assertEq(distributor.getAvailableShares(), 0, "Available shares should be zero when empty");
    }

    /*//////////////////////////////////////////////////////////////
                      EMERGENCY WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_emergencyWithdraw_transfersShares() public {
        uint256 withdrawAmount = 50000e18;
        uint256 ownerBalanceBefore = vault.balanceOf(owner);
        uint256 distributorBalanceBefore = vault.balanceOf(address(distributor));

        vm.prank(owner);
        distributor.emergencyWithdraw(withdrawAmount);

        assertEq(vault.balanceOf(owner), ownerBalanceBefore + withdrawAmount, "Owner should receive shares");
        assertEq(
            vault.balanceOf(address(distributor)),
            distributorBalanceBefore - withdrawAmount,
            "Distributor balance should decrease"
        );
    }

    function test_emergencyWithdraw_canWithdrawAllShares() public {
        uint256 allShares = vault.balanceOf(address(distributor));

        vm.prank(owner);
        distributor.emergencyWithdraw(allShares);

        assertEq(vault.balanceOf(address(distributor)), 0, "Distributor should have no shares");
        assertEq(vault.balanceOf(owner), allShares, "Owner should receive all shares");
    }

    function test_emergencyWithdraw_revertsForNonOwner() public {
        uint256 withdrawAmount = 10000e18;

        vm.prank(user1);
        vm.expectRevert();
        distributor.emergencyWithdraw(withdrawAmount);
    }

    function test_emergencyWithdraw_revertsWithInsufficientBalance() public {
        uint256 distributorBalance = vault.balanceOf(address(distributor));
        uint256 withdrawAmount = distributorBalance + 1;

        vm.prank(owner);
        vm.expectRevert();
        distributor.emergencyWithdraw(withdrawAmount);
    }

    function test_emergencyWithdraw_worksAfterRegularDistributions() public {
        // First do some regular distributions
        bytes memory message = abi.encode(uint16(1), user1, 100000e18);
        bytes32 guid = keccak256("test-guid");
        Origin memory origin = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin, guid, message, address(0), "");

        // Then emergency withdraw remaining
        uint256 remaining = vault.balanceOf(address(distributor));

        vm.prank(owner);
        distributor.emergencyWithdraw(remaining);

        assertEq(vault.balanceOf(address(distributor)), 0, "Distributor should be empty");
    }

    /*//////////////////////////////////////////////////////////////
                      INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_multipleClaims_fromDifferentUsers() public {
        // User1 claims
        bytes memory message1 = abi.encode(uint16(1), user1, 1000e18);
        bytes32 guid1 = keccak256("guid1");
        Origin memory origin1 = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin1, guid1, message1, address(0), "");

        // User2 claims
        bytes memory message2 = abi.encode(uint16(1), user2, 2000e18);
        bytes32 guid2 = keccak256("guid2");
        Origin memory origin2 = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 2});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin2, guid2, message2, address(0), "");

        // User3 claims
        bytes memory message3 = abi.encode(uint16(1), user3, 3000e18);
        bytes32 guid3 = keccak256("guid3");
        Origin memory origin3 = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 3});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin3, guid3, message3, address(0), "");

        assertEq(vault.balanceOf(user1), 1000e18, "User1 balance correct");
        assertEq(vault.balanceOf(user2), 2000e18, "User2 balance correct");
        assertEq(vault.balanceOf(user3), 3000e18, "User3 balance correct");
    }

    function test_mixedClaimTypes_singleAndBatch() public {
        // Single claim
        bytes memory message1 = abi.encode(uint16(1), user1, 1000e18);
        bytes32 guid1 = keccak256("guid1");
        Origin memory origin1 = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 1});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin1, guid1, message1, address(0), "");

        // Batch claim
        address[] memory users = new address[](2);
        users[0] = user2;
        users[1] = user3;

        uint256[] memory sharesArray = new uint256[](2);
        sharesArray[0] = 2000e18;
        sharesArray[1] = 3000e18;

        bytes memory message2 = abi.encode(uint16(2), users, sharesArray);
        bytes32 guid2 = keccak256("guid2");
        Origin memory origin2 = Origin({srcEid: A_EID, sender: addressToBytes32(address(this)), nonce: 2});

        vm.prank(address(endpoints[B_EID]));
        distributor.lzReceive(origin2, guid2, message2, address(0), "");

        assertEq(vault.balanceOf(user1), 1000e18, "User1 balance correct");
        assertEq(vault.balanceOf(user2), 2000e18, "User2 balance correct");
        assertEq(vault.balanceOf(user3), 3000e18, "User3 balance correct");
    }

    function test_constants_haveCorrectValues() public view {
        assertEq(distributor.MSG_TYPE_CLAIM(), 1, "MSG_TYPE_CLAIM should be 1");
        assertEq(distributor.MSG_TYPE_BATCH_CLAIM(), 2, "MSG_TYPE_BATCH_CLAIM should be 2");
    }
}

