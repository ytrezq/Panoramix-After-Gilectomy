// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Call, PriceFeedInfo} from "../../interfaces/Types.sol";

import {Test} from "forge-std/Test.sol";
import {PriceFeedStore} from "../../instance/PriceFeedStore.sol";
import {IBytecodeRepository} from "../../interfaces/IBytecodeRepository.sol";
import {IPriceFeedStore, PriceUpdate} from "../../interfaces/IPriceFeedStore.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {IImmutableOwnableTrait} from "../../interfaces/base/IImmutableOwnableTrait.sol";
import {
    MockPriceFeed,
    MockSingleUnderlyingPriceFeed,
    MockMultipleUnderlyingPriceFeed,
    MockUpdatablePriceFeed
} from "../mocks/MockPriceFeed.sol";
import {
    AP_BYTECODE_REPOSITORY,
    AP_INSTANCE_MANAGER_PROXY,
    AP_ZERO_PRICE_FEED,
    NO_VERSION_CONTROL
} from "../../libraries/ContractLiterals.sol";
import {
    ZeroAddressException,
    StalePriceException,
    IncorrectPriceException,
    IncorrectPriceFeedException
} from "@gearbox-protocol/core-v3/contracts/interfaces/IExceptions.sol";

contract PriceFeedStoreTest is Test {
    PriceFeedStore public store;
    address public owner;
    address public token;
    address public zeroPriceFeed;
    MockPriceFeed public priceFeed;
    IAddressProvider public addressProvider;
    IBytecodeRepository public bytecodeRepository;

    function setUp() public {
        owner = makeAddr("owner");
        token = makeAddr("token");
        zeroPriceFeed = makeAddr("zeroPriceFeed");
        priceFeed = new MockPriceFeed();
        addressProvider = IAddressProvider(makeAddr("addressProvider"));
        bytecodeRepository = IBytecodeRepository(makeAddr("bytecodeRepository"));

        vm.mockCall(
            address(addressProvider),
            abi.encodeWithSignature(
                "getAddressOrRevert(bytes32,uint256)", AP_INSTANCE_MANAGER_PROXY, NO_VERSION_CONTROL
            ),
            abi.encode(owner)
        );

        vm.mockCall(
            address(addressProvider),
            abi.encodeWithSignature("getAddressOrRevert(bytes32,uint256)", AP_BYTECODE_REPOSITORY, NO_VERSION_CONTROL),
            abi.encode(address(bytecodeRepository))
        );

        vm.mockCall(
            address(bytecodeRepository),
            abi.encodeWithSignature("deploy(bytes32,uint256,bytes,bytes32)", AP_ZERO_PRICE_FEED, 3_10, "", bytes32(0)),
            abi.encode(zeroPriceFeed)
        );

        vm.mockCall(
            address(bytecodeRepository), abi.encodeWithSignature("isDeployedFromRepository(address)"), abi.encode(false)
        );

        store = new PriceFeedStore(address(addressProvider));
        _markAsInternalPriceFeed(address(priceFeed));
    }

    function _markAsInternalPriceFeed(address target) internal {
        vm.mockCall(
            address(bytecodeRepository),
            abi.encodeWithSignature("isDeployedFromRepository(address)", target),
            abi.encode(true)
        );

        vm.mockCall(address(target), abi.encodeWithSignature("owner()"), abi.encode(address(store)));
    }

    /// @notice Test basic price feed addition flow
    function test_PFS_01_addPriceFeed_works() public {
        uint32 stalenessPeriod = 3600;
        string memory name = "ETH/USD";

        vm.prank(owner);
        store.addPriceFeed(address(priceFeed), stalenessPeriod, name);

        // Verify price feed was added correctly
        assertEq(store.getStalenessPeriod(address(priceFeed)), stalenessPeriod);

        // Get price feed info
        PriceFeedInfo memory priceFeedInfo = store.priceFeedInfo(address(priceFeed));

        // Verify all parameters were set correctly
        assertEq(priceFeedInfo.priceFeedType, "PRICE_FEED::MOCK");
        assertEq(priceFeedInfo.stalenessPeriod, stalenessPeriod);
        assertEq(priceFeedInfo.version, 1);
        assertEq(priceFeedInfo.name, name);

        // Verify price feed is in known list
        address[] memory knownPriceFeeds = store.getKnownPriceFeeds();
        assertEq(knownPriceFeeds.length, 1);
        assertEq(knownPriceFeeds[0], address(priceFeed));
    }

    /// @notice Test that only owner can add price feeds
    function test_PFS_02_addPriceFeed_reverts_if_not_owner() public {
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSignature("CallerIsNotOwnerException(address)", notOwner));
        store.addPriceFeed(address(priceFeed), 3600, "ETH/USD");
    }

    /// @notice Test that zero address price feed cannot be added
    function test_PFS_03_addPriceFeed_reverts_on_zero_address() public {
        vm.prank(owner);
        vm.expectRevert(ZeroAddressException.selector);
        store.addPriceFeed(address(0), 3600, "ETH/USD");
    }

    /// @notice Test duplicate price feed addition is prevented
    function test_PFS_04_addPriceFeed_reverts_on_duplicate() public {
        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600, "ETH/USD");

        vm.expectRevert(
            abi.encodeWithSelector(IPriceFeedStore.PriceFeedIsAlreadyAddedException.selector, address(priceFeed))
        );
        store.addPriceFeed(address(priceFeed), 3600, "ETH/USD");
        vm.stopPrank();
    }

    /// @notice Test staleness period validation
    function test_PFS_05_addPriceFeed_validates_staleness() public {
        MockPriceFeed stalePriceFeed = new MockPriceFeed();
        stalePriceFeed.setLastUpdateTime(block.timestamp);

        vm.warp(block.timestamp + 7200);

        vm.prank(owner);
        vm.expectRevert(StalePriceException.selector);
        store.addPriceFeed(address(stalePriceFeed), 3600, "ETH/USD");
    }

    /// @notice Test price feed allowance for tokens
    function test_PFS_06_allowPriceFeed_works() public {
        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600, "ETH/USD");
        store.allowPriceFeed(token, address(priceFeed));
        vm.stopPrank();

        assertTrue(store.isAllowedPriceFeed(token, address(priceFeed)));
    }

    /// @notice Test only owner can allow price feeds
    function test_PFS_07_allowPriceFeed_reverts_if_not_owner() public {
        vm.prank(owner);
        store.addPriceFeed(address(priceFeed), 3600, "ETH/USD");

        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSignature("CallerIsNotOwnerException(address)", notOwner));
        store.allowPriceFeed(token, address(priceFeed));
    }

    /// @notice Test unknown price feeds cannot be allowed
    function test_PFS_08_allowPriceFeed_reverts_on_unknown_feed() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IPriceFeedStore.PriceFeedIsNotKnownException.selector, address(priceFeed))
        );
        store.allowPriceFeed(token, address(priceFeed));
    }

    /// @notice Test price feed forbidding
    function test_PFS_09_forbidPriceFeed_works() public {
        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600, "ETH/USD");
        store.allowPriceFeed(token, address(priceFeed));
        store.forbidPriceFeed(token, address(priceFeed));
        vm.stopPrank();

        assertFalse(store.isAllowedPriceFeed(token, address(priceFeed)));
    }

    /// @notice Test only owner can forbid price feeds
    function test_PFS_10_forbidPriceFeed_reverts_if_not_owner() public {
        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600, "ETH/USD");
        store.allowPriceFeed(token, address(priceFeed));
        vm.stopPrank();

        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSignature("CallerIsNotOwnerException(address)", notOwner));
        store.forbidPriceFeed(token, address(priceFeed));
    }

    /// @notice Test staleness period updates
    function test_PFS_11_setStalenessPeriod_works() public {
        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600, "ETH/USD");
        store.setStalenessPeriod(address(priceFeed), 7200);
        vm.stopPrank();

        assertEq(store.getStalenessPeriod(address(priceFeed)), 7200);
    }

    /// @notice Test staleness period validation on update
    function test_PFS_12_setStalenessPeriod_validates_staleness() public {
        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600, "ETH/USD");

        priceFeed.setLastUpdateTime(block.timestamp);
        vm.warp(block.timestamp + 7200);

        vm.expectRevert(StalePriceException.selector);
        store.setStalenessPeriod(address(priceFeed), 3601);
        vm.stopPrank();
    }

    /// @notice Test token list management
    function test_PFS_13_maintains_token_list() public {
        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600, "ETH/USD");
        store.allowPriceFeed(token, address(priceFeed));
        vm.stopPrank();

        address[] memory knownTokens = store.getKnownTokens();
        assertEq(knownTokens.length, 1);
        assertEq(knownTokens[0], token);
    }

    /// @notice Test multiple price feeds per token
    function test_PFS_14_allows_multiple_feeds_per_token() public {
        MockPriceFeed priceFeed2 = new MockPriceFeed();
        _markAsInternalPriceFeed(address(priceFeed2));

        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600, "ETH/USD Primary");
        store.addPriceFeed(address(priceFeed2), 3600, "ETH/USD Secondary");
        store.allowPriceFeed(token, address(priceFeed));
        store.allowPriceFeed(token, address(priceFeed2));
        vm.stopPrank();

        address[] memory feeds = store.getPriceFeeds(token);
        assertEq(feeds.length, 2);
        assertTrue(store.isAllowedPriceFeed(token, address(priceFeed)));
        assertTrue(store.isAllowedPriceFeed(token, address(priceFeed2)));
    }

    /// @notice Test handles updatable price feeds
    function test_PFS_15_handles_updatable_price_feeds() public {
        MockUpdatablePriceFeed updatableFeed = new MockUpdatablePriceFeed();
        _markAsInternalPriceFeed(address(updatableFeed));

        vm.startPrank(owner);

        // Expect AddUpdatablePriceFeed event
        vm.expectEmit(true, false, false, false);
        emit IPriceFeedStore.AddUpdatablePriceFeed(address(updatableFeed));

        store.addPriceFeed(address(updatableFeed), 3600, "ETH/USD Updatable");

        // Check it was added to updatable feeds list
        address[] memory updatableFeeds = store.getUpdatablePriceFeeds();
        assertEq(updatableFeeds.length, 1);
        assertEq(updatableFeeds[0], address(updatableFeed));

        // Test price updates
        bytes memory updateData = abi.encode(1234);
        PriceUpdate[] memory updates = new PriceUpdate[](1);
        updates[0] = PriceUpdate({priceFeed: address(updatableFeed), data: updateData});
        store.updatePrices(updates);

        // Test non-updatable feed
        MockPriceFeed nonUpdatableFeed = new MockPriceFeed();
        _markAsInternalPriceFeed(address(nonUpdatableFeed));
        store.addPriceFeed(address(nonUpdatableFeed), 3600, "ETH/USD Non-updatable");

        // Verify only updatable feed is in the list
        updatableFeeds = store.getUpdatablePriceFeeds();
        assertEq(updatableFeeds.length, 1);
        assertEq(updatableFeeds[0], address(updatableFeed));

        // Try to update non-updatable feed
        updates[0] = PriceUpdate({priceFeed: address(nonUpdatableFeed), data: updateData});
        vm.expectRevert(
            abi.encodeWithSelector(IPriceFeedStore.PriceFeedIsNotUpdatableException.selector, address(nonUpdatableFeed))
        );
        store.updatePrices(updates);

        // Verify update was processed
        assertEq(updatableFeed.lastUpdateData(), updateData);
        vm.stopPrank();
    }

    function test_PFS_16_validates_nested_price_feeds() public {
        // Create a tree of price feeds:
        // root (multiple underlying)
        // ├── child1 (single underlying)
        // │   └── leaf1
        // └── child2 (multiple underlying)
        //     ├── leaf2
        //     └── leaf3 (updatable)

        MockPriceFeed leaf1 = new MockPriceFeed();
        MockPriceFeed leaf2 = new MockPriceFeed();
        MockUpdatablePriceFeed leaf3 = new MockUpdatablePriceFeed();

        // Mock all as internal feeds
        _markAsInternalPriceFeed(address(leaf1));
        _markAsInternalPriceFeed(address(leaf2));
        _markAsInternalPriceFeed(address(leaf3));

        MockSingleUnderlyingPriceFeed child1 = new MockSingleUnderlyingPriceFeed(address(leaf1));
        address[] memory child2Feeds = new address[](2);
        child2Feeds[0] = address(leaf2);
        child2Feeds[1] = address(leaf3);
        MockMultipleUnderlyingPriceFeed child2 = new MockMultipleUnderlyingPriceFeed(child2Feeds);

        _markAsInternalPriceFeed(address(child1));
        _markAsInternalPriceFeed(address(child2));

        address[] memory rootFeeds = new address[](2);
        rootFeeds[0] = address(child1);
        rootFeeds[1] = address(child2);
        MockMultipleUnderlyingPriceFeed root = new MockMultipleUnderlyingPriceFeed(rootFeeds);

        _markAsInternalPriceFeed(address(root));

        vm.startPrank(owner);

        // Expect AddUpdatablePriceFeed event for leaf3
        vm.expectEmit(true, false, false, false);
        emit IPriceFeedStore.AddUpdatablePriceFeed(address(leaf3));

        store.addPriceFeed(address(root), 3600, "Root Feed");

        // Verify updatable feeds were detected
        address[] memory updatableFeeds = store.getUpdatablePriceFeeds();
        assertEq(updatableFeeds.length, 1, "Wrong number of updatable feeds");
        assertEq(updatableFeeds[0], address(leaf3), "Wrong updatable feed");

        vm.stopPrank();
    }

    function test_PFS_17_handles_external_feeds_in_tree() public {
        // Create a tree with mix of internal and external feeds:
        // root (multiple underlying)
        // ├── external1
        // └── child (single underlying)
        //     └── external2

        address external1 = makeAddr("external1");
        address external2 = makeAddr("external2");

        MockSingleUnderlyingPriceFeed child = new MockSingleUnderlyingPriceFeed(external2);
        _markAsInternalPriceFeed(address(child));

        address[] memory rootFeeds = new address[](2);
        rootFeeds[0] = external1;
        rootFeeds[1] = address(child);
        MockMultipleUnderlyingPriceFeed root = new MockMultipleUnderlyingPriceFeed(rootFeeds);
        _markAsInternalPriceFeed(address(root));

        // These calls should never happen
        vm.expectCall(address(external1), abi.encodeWithSignature("owner()"), 0);
        vm.expectCall(address(external2), abi.encodeWithSignature("owner()"), 0);

        vm.startPrank(owner);
        store.addPriceFeed(address(root), 3600, "Root Feed");
        vm.stopPrank();
    }

    function test_PFS_18_handles_complex_nesting() public {
        // Create a complex tree:
        // root (multiple underlying)
        // ├── branch1 (multiple underlying)
        // │   ├── leaf1 (updatable)
        // │   └── branch2 (single underlying)
        // │       └── leaf2
        // └── branch3 (single underlying)
        //     └── leaf3 (updatable)

        // Create leaf nodes
        MockUpdatablePriceFeed leaf1 = new MockUpdatablePriceFeed();
        MockPriceFeed leaf2 = new MockPriceFeed();
        MockUpdatablePriceFeed leaf3 = new MockUpdatablePriceFeed();

        // Mock all as internal feeds
        _markAsInternalPriceFeed(address(leaf1));
        _markAsInternalPriceFeed(address(leaf2));
        _markAsInternalPriceFeed(address(leaf3));

        // Create branch2 (single underlying -> leaf2)
        MockSingleUnderlyingPriceFeed branch2 = new MockSingleUnderlyingPriceFeed(address(leaf2));
        _markAsInternalPriceFeed(address(branch2));

        // Create branch1 (multiple underlying -> [leaf1, branch2])
        address[] memory branch1Feeds = new address[](2);
        branch1Feeds[0] = address(leaf1);
        branch1Feeds[1] = address(branch2);
        MockMultipleUnderlyingPriceFeed branch1 = new MockMultipleUnderlyingPriceFeed(branch1Feeds);
        _markAsInternalPriceFeed(address(branch1));

        // Create branch3 (single underlying -> leaf3)
        MockSingleUnderlyingPriceFeed branch3 = new MockSingleUnderlyingPriceFeed(address(leaf3));
        _markAsInternalPriceFeed(address(branch3));

        // Create root (multiple underlying -> [branch1, branch3])
        address[] memory rootFeeds = new address[](2);
        rootFeeds[0] = address(branch1);
        rootFeeds[1] = address(branch3);
        MockMultipleUnderlyingPriceFeed root = new MockMultipleUnderlyingPriceFeed(rootFeeds);
        _markAsInternalPriceFeed(address(root));

        vm.startPrank(owner);

        // Expect AddUpdatablePriceFeed events
        vm.expectEmit(true, false, false, false);
        emit IPriceFeedStore.AddUpdatablePriceFeed(address(leaf1));
        vm.expectEmit(true, false, false, false);
        emit IPriceFeedStore.AddUpdatablePriceFeed(address(leaf3));

        store.addPriceFeed(address(root), 3600, "Complex Root");

        // Verify updatable feeds were detected
        address[] memory updatableFeeds = store.getUpdatablePriceFeeds();
        assertEq(updatableFeeds.length, 2, "Wrong number of updatable feeds");
        assertTrue(
            (updatableFeeds[0] == address(leaf1) && updatableFeeds[1] == address(leaf3))
                || (updatableFeeds[0] == address(leaf3) && updatableFeeds[1] == address(leaf1)),
            "Wrong updatable feeds"
        );

        // Test updating both feeds
        bytes memory updateData1 = abi.encode(1234);
        bytes memory updateData3 = abi.encode(5678);
        PriceUpdate[] memory updates = new PriceUpdate[](2);
        updates[0] = PriceUpdate({priceFeed: address(leaf1), data: updateData1});
        updates[1] = PriceUpdate({priceFeed: address(leaf3), data: updateData3});
        store.updatePrices(updates);

        // Verify updates were processed
        assertEq(leaf1.lastUpdateData(), updateData1, "Leaf1 not updated");
        assertEq(leaf3.lastUpdateData(), updateData3, "Leaf3 not updated");
        vm.stopPrank();
    }

    function test_PFS_19_handles_external_feed() public {
        MockPriceFeed externalFeed = new MockPriceFeed();

        vm.startPrank(owner);
        store.addPriceFeed(address(externalFeed), 3600, "External Feed");

        // Verify no ownership check was performed
        vm.expectCall(address(externalFeed), abi.encodeWithSignature("owner()"), 0);

        // Verify feed was added with correct metadata
        PriceFeedInfo memory info = store.priceFeedInfo(address(externalFeed));
        assertEq(info.priceFeedType, "PRICE_FEED::EXTERNAL");
        assertEq(info.version, 0);
        assertEq(info.stalenessPeriod, 3600);
        assertEq(info.name, "External Feed");
        vm.stopPrank();
    }

    function test_PFS_20_validates_different_ownership_types() public {
        // Test non-ownable feed (should pass)
        MockPriceFeed nonOwnableFeed = new MockPriceFeed();
        vm.mockCall(
            address(bytecodeRepository),
            abi.encodeWithSignature("isDeployedFromRepository(address)", address(nonOwnableFeed)),
            abi.encode(true)
        );

        // Test Ownable feed owned by store (should pass)
        MockPriceFeed ownableFeed = new MockPriceFeed();
        vm.mockCall(
            address(bytecodeRepository),
            abi.encodeWithSignature("isDeployedFromRepository(address)", address(ownableFeed)),
            abi.encode(true)
        );
        vm.mockCall(address(ownableFeed), abi.encodeWithSignature("acceptOwnership()"), "");
        vm.mockCall(address(ownableFeed), abi.encodeWithSignature("owner()"), abi.encode(address(store)));

        // Test Ownable feed owned by other (should fail)
        MockPriceFeed wrongOwnerFeed = new MockPriceFeed();
        vm.mockCall(
            address(bytecodeRepository),
            abi.encodeWithSignature("isDeployedFromRepository(address)", address(wrongOwnerFeed)),
            abi.encode(true)
        );
        vm.mockCall(address(wrongOwnerFeed), abi.encodeWithSignature("acceptOwnership()"), "");
        vm.mockCall(address(wrongOwnerFeed), abi.encodeWithSignature("owner()"), abi.encode(makeAddr("other")));

        vm.startPrank(owner);

        // Non-ownable should pass
        store.addPriceFeed(address(nonOwnableFeed), 3600, "Non-ownable Feed");

        // Correctly owned should pass
        store.addPriceFeed(address(ownableFeed), 3600, "Ownable Feed");

        // Wrong owner should fail
        vm.expectRevert(
            abi.encodeWithSelector(IPriceFeedStore.PriceFeedIsNotOwnedByStore.selector, address(wrongOwnerFeed))
        );
        store.addPriceFeed(address(wrongOwnerFeed), 3600, "Wrong Owner Feed");

        vm.stopPrank();
    }

    function test_PFS_21_configurePriceFeeds_works() public {
        vm.startPrank(owner);
        store.addPriceFeed(address(priceFeed), 3600, "ETH/USD");

        // Test allowed configuration call
        bytes memory callData = abi.encodeWithSignature("setPrice(int256)", 1234);
        Call[] memory calls = new Call[](1);
        calls[0] = Call(address(priceFeed), callData);
        store.configurePriceFeeds(calls);

        // Verify call was executed
        (, int256 answer,,,) = priceFeed.latestRoundData();
        assertEq(answer, 1234);
        vm.stopPrank();
    }

    function test_PFS_22_configurePriceFeeds_reverts_if_not_owner() public {
        vm.prank(owner);
        store.addPriceFeed(address(priceFeed), 3600, "ETH/USD");

        Call[] memory calls = new Call[](1);
        calls[0] = Call(address(priceFeed), abi.encodeWithSignature("setPrice(int256)", 1234));

        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSignature("CallerIsNotOwnerException(address)", notOwner));
        store.configurePriceFeeds(calls);
    }

    function test_PFS_23_configurePriceFeeds_reverts_on_unknown_feed() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call(address(priceFeed), abi.encodeWithSignature("setPrice(int256)", 1234));

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IPriceFeedStore.PriceFeedIsNotKnownException.selector, address(priceFeed))
        );
        store.configurePriceFeeds(calls);
    }

    function test_PFS_24_configurePriceFeeds_reverts_on_renounceOwnership() public {
        vm.prank(owner);
        store.addPriceFeed(address(priceFeed), 3600, "ETH/USD");

        Call[] memory renounceCall = new Call[](1);
        renounceCall[0] = Call(address(priceFeed), abi.encodeWithSignature("renounceOwnership()"));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPriceFeedStore.ForbiddenConfigurationMethodException.selector, bytes4(renounceCall[0].callData)
            )
        );
        vm.prank(owner);
        store.configurePriceFeeds(renounceCall);
    }

    function test_PFS_25_removePriceFeed_works() public {
        vm.startPrank(owner);

        // Test it reverts on unknown feed
        vm.expectRevert(
            abi.encodeWithSelector(IPriceFeedStore.PriceFeedIsNotKnownException.selector, address(priceFeed))
        );
        store.removePriceFeed(address(priceFeed));

        // Add price feed and allow it for some tokens
        store.addPriceFeed(address(priceFeed), 3600, "ETH/USD");
        store.allowPriceFeed(token, address(priceFeed));
        address token2 = makeAddr("token2");
        store.allowPriceFeed(token2, address(priceFeed));
        vm.stopPrank();

        // Test it reverts if not owner
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(IImmutableOwnableTrait.CallerIsNotOwnerException.selector, notOwner));
        store.removePriceFeed(address(priceFeed));

        // Test it successfully removes feed
        vm.prank(owner);

        // Expect ForbidPriceFeed events for each token
        vm.expectEmit(true, true, false, false);
        emit IPriceFeedStore.ForbidPriceFeed(token, address(priceFeed));
        vm.expectEmit(true, true, false, false);
        emit IPriceFeedStore.ForbidPriceFeed(token2, address(priceFeed));

        // Expect RemovePriceFeed event
        vm.expectEmit(true, false, false, false);
        emit IPriceFeedStore.RemovePriceFeed(address(priceFeed));

        store.removePriceFeed(address(priceFeed));

        // Verify feed was removed
        assertFalse(store.isKnownPriceFeed(address(priceFeed)), "Feed should not be known");
        assertFalse(store.isAllowedPriceFeed(token, address(priceFeed)), "Feed should not be allowed for token1");
        assertFalse(store.isAllowedPriceFeed(token2, address(priceFeed)), "Feed should not be allowed for token2");

        vm.expectRevert(
            abi.encodeWithSelector(IPriceFeedStore.PriceFeedIsNotAllowedException.selector, token, address(priceFeed))
        );
        store.getAllowanceTimestamp(token, address(priceFeed));

        vm.expectRevert(
            abi.encodeWithSelector(IPriceFeedStore.PriceFeedIsNotAllowedException.selector, token2, address(priceFeed))
        );
        store.getAllowanceTimestamp(token2, address(priceFeed));
    }
}
