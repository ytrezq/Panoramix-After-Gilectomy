// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import {CapyfiAggregatorV3} from "src/contracts/PriceOracle/CapyfiAggregatorV3.sol";

contract CapyfiAggregatorV3Test is Test {
    CapyfiAggregatorV3 public aggregator;
    
    address public owner;
    address public authorizedUser;
    address public unauthorizedUser;
    
    uint8 constant DECIMALS = 8;
    string constant DESCRIPTION = "BTC/USD Price Feed";
    uint256 constant VERSION = 1;
    int256 constant INITIAL_PRICE = 50000e8; // $50,000 with 8 decimals
    
    // Chainlink-compatible round ID: (phaseId << 64) + originalId
    // First round: (1 << 64) + 1 = 18446744073709551617
    uint80 constant FIRST_ROUND_ID = 18446744073709551617;
    
    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);
    event NewRound(uint256 indexed roundId, address indexed startedBy, uint256 startedAt);
    event AuthorizedAddressAdded(address indexed addr);
    event AuthorizedAddressRemoved(address indexed addr);
    event BoundsConfigured(int256 minAnswer, int256 maxAnswer, bool enabled);
    event BoundChecksToggled(bool enabled);

    function setUp() public {
        owner = makeAddr("owner");
        authorizedUser = makeAddr("authorizedUser");
        unauthorizedUser = makeAddr("unauthorizedUser");
        
        vm.prank(owner);
        aggregator = new CapyfiAggregatorV3(
            DECIMALS,
            DESCRIPTION,
            VERSION,
            INITIAL_PRICE
        );
    }

    // ============ Constructor Tests ============
    
    function testConstructorValidPrice() public {
        int256 price = 3000e8;
        vm.prank(owner);
        CapyfiAggregatorV3 newAggregator = new CapyfiAggregatorV3(18, "ETH/USD", 2, price);
        
        assertEq(newAggregator.decimals(), 18);
        assertEq(newAggregator.description(), "ETH/USD");
        assertEq(newAggregator.version(), 2);
        assertEq(newAggregator.latestAnswer(), price);
        assertEq(newAggregator.latestRound(), FIRST_ROUND_ID);
    }
    
    function testConstructorInvalidPriceZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.InvalidPrice.selector, int256(0)));
        new CapyfiAggregatorV3(DECIMALS, DESCRIPTION, VERSION, 0);
    }
    
    function testConstructorInvalidPriceNegative() public {
        int256 negativePrice = -1000;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.InvalidPrice.selector, negativePrice));
        new CapyfiAggregatorV3(DECIMALS, DESCRIPTION, VERSION, negativePrice);
    }

    // ============ Access Control Tests ============
    
    function testAddAuthorizedAddress() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit AuthorizedAddressAdded(authorizedUser);
        aggregator.addAuthorizedAddress(authorizedUser);
        
        assertTrue(aggregator.authorizedAddresses(authorizedUser));
    }
    
    function testAddAuthorizedAddressZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.InvalidAddress.selector, address(0)));
        aggregator.addAuthorizedAddress(address(0));
    }
    
    function testAddAuthorizedAddressUnauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert("Ownable: caller is not the owner");
        aggregator.addAuthorizedAddress(authorizedUser);
    }
    
    function testRemoveAuthorizedAddress() public {
        // First add the address
        vm.prank(owner);
        aggregator.addAuthorizedAddress(authorizedUser);
        assertTrue(aggregator.authorizedAddresses(authorizedUser));
        
        // Then remove it
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit AuthorizedAddressRemoved(authorizedUser);
        aggregator.removeAuthorizedAddress(authorizedUser);
        
        assertFalse(aggregator.authorizedAddresses(authorizedUser));
    }

    function testRemoveNonAuthorizedAddress() public {
        // Try to remove an address that was never authorized
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.AddressNotAuthorized.selector, unauthorizedUser));
        aggregator.removeAuthorizedAddress(unauthorizedUser);
    }

    // ============ Price Bounds Tests ============
    
    function testSetBounds() public {
        int256 minPrice = 30000e8;
        int256 maxPrice = 80000e8;
        bool enabled = true;
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit BoundsConfigured(minPrice, maxPrice, enabled);
        aggregator.setBounds(minPrice, maxPrice, enabled);
        
        assertEq(aggregator.minAnswer(), minPrice);
        assertEq(aggregator.maxAnswer(), maxPrice);
        assertTrue(aggregator.boundChecksEnabled());
    }
    
    function testSetBoundsInvalidRange() public {
        int256 minPrice = 80000e8;
        int256 maxPrice = 30000e8; // max < min
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.InvalidBounds.selector, minPrice, maxPrice));
        aggregator.setBounds(minPrice, maxPrice, true);
    }
    
    function testToggleBoundsChecking() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit BoundChecksToggled(true);
        aggregator.toggleBoundsChecking(true);
        
        assertTrue(aggregator.boundChecksEnabled());
        
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit BoundChecksToggled(false);
        aggregator.toggleBoundsChecking(false);
        
        assertFalse(aggregator.boundChecksEnabled());
    }
    
    function testUpdateAnswerWithBoundsEnabled() public {
        // Set bounds
        vm.prank(owner);
        aggregator.setBounds(40000e8, 60000e8, true);
        
        // Valid price within bounds
        int256 validPrice = 55000e8;
        vm.prank(owner);
        aggregator.updateAnswer(validPrice);
        assertEq(aggregator.latestAnswer(), validPrice);
        
        // Price below minimum
        int256 lowPrice = 35000e8;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.PriceOutOfBounds.selector, lowPrice, 40000e8, 60000e8));
        aggregator.updateAnswer(lowPrice);
        
        // Price above maximum
        int256 highPrice = 65000e8;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.PriceOutOfBounds.selector, highPrice, 40000e8, 60000e8));
        aggregator.updateAnswer(highPrice);
    }
    
    function testUpdateAnswerWithBoundsDisabled() public {
        // Set bounds but disable them
        vm.prank(owner);
        aggregator.setBounds(40000e8, 60000e8, false);
        
        // Price outside bounds should still work
        int256 lowPrice = 35000e8;
        vm.prank(owner);
        aggregator.updateAnswer(lowPrice);
        assertEq(aggregator.latestAnswer(), lowPrice);
    }

    // ============ Price Update Tests ============
    
    function testUpdateAnswerAsOwner() public {
        int256 newPrice = 51000e8;
        uint80 expectedRoundId = FIRST_ROUND_ID + 1;
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit AnswerUpdated(newPrice, expectedRoundId, block.timestamp);
        aggregator.updateAnswer(newPrice);
        
        assertEq(aggregator.latestAnswer(), newPrice);
        assertEq(aggregator.latestRound(), expectedRoundId);
    }
    
    function testUpdateAnswerAsAuthorizedUser() public {
        // First authorize the user
        vm.prank(owner);
        aggregator.addAuthorizedAddress(authorizedUser);
        
        int256 newPrice = 52000e8;
        vm.prank(authorizedUser);
        aggregator.updateAnswer(newPrice);
        
        assertEq(aggregator.latestAnswer(), newPrice);
    }
    
    function testUpdateAnswerUnauthorized() public {
        int256 newPrice = 53000e8;
        
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.UnauthorizedCaller.selector, unauthorizedUser));
        aggregator.updateAnswer(newPrice);
    }
    
    function testUpdateAnswerInvalidPriceZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.InvalidPrice.selector, int256(0)));
        aggregator.updateAnswer(0);
    }
    
    function testUpdateAnswerInvalidPriceNegative() public {
        int256 negativePrice = -5000;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.InvalidPrice.selector, negativePrice));
        aggregator.updateAnswer(negativePrice);
    }

    // ============ Round Data Tests ============
    
    function testGetRoundDataValid() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = 
            aggregator.getRoundData(FIRST_ROUND_ID);
        
        assertEq(roundId, FIRST_ROUND_ID);
        assertEq(answer, INITIAL_PRICE);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertEq(answeredInRound, FIRST_ROUND_ID);
    }
    
    function testGetRoundDataInvalidRoundIdZero() public view {
        // Now returns zeros instead of reverting
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = 
            aggregator.getRoundData(0);
        
        assertEq(roundId, 0);
        assertEq(answer, 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
    }
    
    function testGetRoundDataInvalidRoundIdTooHigh() public view {
        uint80 invalidRoundId = 999;
        // Now returns zeros instead of reverting
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = 
            aggregator.getRoundData(invalidRoundId);
        
        assertEq(roundId, 0);
        assertEq(answer, 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
    }
    
    function testLatestRoundData() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = 
            aggregator.latestRoundData();
        
        assertEq(roundId, FIRST_ROUND_ID);
        assertEq(answer, INITIAL_PRICE);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertEq(answeredInRound, FIRST_ROUND_ID);
    }

    // ============ Multiple Rounds Tests ============
    
    function testMultipleRounds() public {
        int256[] memory prices = new int256[](3);
        prices[0] = 51000e8;
        prices[1] = 52000e8;
        prices[2] = 53000e8;
        
        for (uint256 i = 0; i < prices.length; i++) {
            vm.prank(owner);
            aggregator.updateAnswer(prices[i]);
            
            uint80 expectedRoundId = FIRST_ROUND_ID + uint80(i + 1);
            assertEq(aggregator.latestAnswer(), prices[i]);
            assertEq(aggregator.latestRound(), expectedRoundId);
            
            (uint80 currentRoundId, int256 currentAnswer, , , uint80 currentAnsweredInRound) = 
                aggregator.getRoundData(expectedRoundId);
            assertEq(currentRoundId, expectedRoundId);
            assertEq(currentAnswer, prices[i]);
            assertEq(currentAnsweredInRound, expectedRoundId);
        }
        
        // Verify we can still access old rounds
        (uint80 firstRoundId, int256 firstAnswer, , , ) = aggregator.getRoundData(FIRST_ROUND_ID);
        assertEq(firstRoundId, FIRST_ROUND_ID);
        assertEq(firstAnswer, INITIAL_PRICE);
    }

    // ============ View Function Tests ============
    
    function testDecimals() public view {
        assertEq(aggregator.decimals(), DECIMALS);
    }
    
    function testDescription() public view {
        assertEq(aggregator.description(), DESCRIPTION);
    }
    
    function testVersion() public view {
        assertEq(aggregator.version(), VERSION);
    }
    
    function testLatestRound() public view {
        assertEq(aggregator.latestRound(), FIRST_ROUND_ID);
    }
    
    function testLatestAnswer() public {
        assertEq(aggregator.latestAnswer(), INITIAL_PRICE);
        
        int256 newPrice = 55000e8;
        vm.prank(owner);
        aggregator.updateAnswer(newPrice);
        assertEq(aggregator.latestAnswer(), newPrice);
    }
    
    function testLatestTimestamp() public {
        uint256 initialTimestamp = aggregator.latestTimestamp();
        assertGt(initialTimestamp, 0);
        
        vm.warp(block.timestamp + 3600); // Fast forward 1 hour
        vm.prank(owner);
        aggregator.updateAnswer(55000e8);
        
        uint256 newTimestamp = aggregator.latestTimestamp();
        assertGt(newTimestamp, initialTimestamp);
        assertEq(newTimestamp, block.timestamp);
    }

    // ============ Chainlink Compatibility Tests ============
    
    function testGetAnswer() public {
        // Test getting answer for first round
        assertEq(aggregator.getAnswer(FIRST_ROUND_ID), INITIAL_PRICE);
        
        // Add a new round and test
        int256 newPrice = 55000e8;
        vm.prank(owner);
        aggregator.updateAnswer(newPrice);
        
        uint80 secondRoundId = FIRST_ROUND_ID + 1;
        assertEq(aggregator.getAnswer(secondRoundId), newPrice);
        assertEq(aggregator.getAnswer(FIRST_ROUND_ID), INITIAL_PRICE); // Old round still accessible
    }
    
    function testGetAnswerInvalidRound() public view {
        // Now returns 0 instead of reverting
        assertEq(aggregator.getAnswer(0), 0);
        assertEq(aggregator.getAnswer(999), 0);
        assertEq(aggregator.getAnswer(type(uint256).max), 0); // Test uint256 max
    }
    
    function testGetTimestamp() public {
        // Test getting timestamp for first round
        uint256 timestamp1 = aggregator.getTimestamp(FIRST_ROUND_ID);
        assertGt(timestamp1, 0);
        
        // Add a new round and test
        vm.warp(block.timestamp + 3600); // Fast forward 1 hour
        vm.prank(owner);
        aggregator.updateAnswer(55000e8);
        
        uint80 secondRoundId = FIRST_ROUND_ID + 1;
        uint256 timestamp2 = aggregator.getTimestamp(secondRoundId);
        assertGt(timestamp2, timestamp1);
        assertEq(timestamp2, block.timestamp);
    }
    
    function testGetTimestampInvalidRound() public view {
        // Now returns 0 instead of reverting
        assertEq(aggregator.getTimestamp(0), 0);
        assertEq(aggregator.getTimestamp(999), 0);
        assertEq(aggregator.getTimestamp(type(uint256).max), 0); // Test uint256 max
    }

    // ============ Helper Function Tests ============
    
    function testRoundExists() public view {
        assertTrue(aggregator.roundExists(FIRST_ROUND_ID));
        assertFalse(aggregator.roundExists(0));
        assertFalse(aggregator.roundExists(999));
    }
    
    function testGetCurrentPhaseInfo() public view {
        (uint16 phaseId, uint64 roundId) = aggregator.getCurrentPhaseInfo();
        assertEq(phaseId, 1);
        assertEq(roundId, 2); // Next round to be created
    }
    
    function testGetPhaseId() public view {
        uint16 phaseId = aggregator.getPhaseId(FIRST_ROUND_ID);
        assertEq(phaseId, 1);
    }
    
    function testGetOriginalRoundId() public view {
        uint64 originalRoundId = aggregator.getOriginalRoundId(FIRST_ROUND_ID);
        assertEq(originalRoundId, 1);
    }

    // ============ Event Tests ============
    
    function testUpdateAnswerEvents() public {
        int256 newPrice = 60000e8;
        uint80 expectedRoundId = FIRST_ROUND_ID + 1;
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit AnswerUpdated(newPrice, expectedRoundId, block.timestamp);
        vm.expectEmit(true, true, false, true);
        emit NewRound(expectedRoundId, owner, block.timestamp);
        
        aggregator.updateAnswer(newPrice);
    }

    // ============ Fuzz Tests ============
    
    function testFuzzValidPriceUpdates(int256 price) public {
        vm.assume(price > 0);
        vm.assume(price < type(int256).max);
        
        vm.prank(owner);
        aggregator.updateAnswer(price);
        
        assertEq(aggregator.latestAnswer(), price);
    }
    
    function testFuzzInvalidPriceUpdates(int256 price) public {
        vm.assume(price <= 0);
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.InvalidPrice.selector, price));
        aggregator.updateAnswer(price);
    }
    
    function testFuzzGetRoundData(uint80 roundId) public view {
        // Test with current valid range (only first round exists initially)
        if (roundId == FIRST_ROUND_ID) {
            (uint80 returnedRoundId, int256 answer, , , ) = aggregator.getRoundData(roundId);
            assertEq(returnedRoundId, FIRST_ROUND_ID);
            assertEq(answer, INITIAL_PRICE);
        } else {
            // Should return zeros instead of reverting
            (uint80 returnedRoundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = 
                aggregator.getRoundData(roundId);
            assertEq(returnedRoundId, 0);
            assertEq(answer, 0);
            assertEq(startedAt, 0);
            assertEq(updatedAt, 0);
            assertEq(answeredInRound, 0);
        }
    }

    // ============ Integration Tests ============
    
    function testCompleteWorkflow() public {
        // 1. Initial state verification
        assertEq(aggregator.decimals(), DECIMALS);
        assertEq(aggregator.version(), VERSION);
        assertEq(aggregator.latestRound(), FIRST_ROUND_ID);
        assertEq(aggregator.latestAnswer(), INITIAL_PRICE);
        
        // 2. Add authorized user
        vm.prank(owner);
        aggregator.addAuthorizedAddress(authorizedUser);
        
        // 3. Set bounds
        vm.prank(owner);
        aggregator.setBounds(30000e8, 80000e8, true);
        
        // 4. Update price from authorized user
        int256 price2 = 55000e8;
        vm.prank(authorizedUser);
        aggregator.updateAnswer(price2);
        
        // 5. Update price from owner
        int256 price3 = 60000e8;
        vm.prank(owner);
        aggregator.updateAnswer(price3);
        
        // 6. Verify all rounds are accessible
        uint80 secondRoundId = FIRST_ROUND_ID + 1;
        uint80 thirdRoundId = FIRST_ROUND_ID + 2;
        
        (uint80 roundId1, int256 answer1, , , ) = aggregator.getRoundData(FIRST_ROUND_ID);
        assertEq(roundId1, FIRST_ROUND_ID);
        assertEq(answer1, INITIAL_PRICE);
        
        (uint80 roundId2, int256 answer2, , , ) = aggregator.getRoundData(secondRoundId);
        assertEq(roundId2, secondRoundId);
        assertEq(answer2, price2);
        
        (uint80 roundId3, int256 answer3, , , ) = aggregator.getRoundData(thirdRoundId);
        assertEq(roundId3, thirdRoundId);
        assertEq(answer3, price3);
        
        // 7. Verify latest data
        assertEq(aggregator.latestRound(), thirdRoundId);
        assertEq(aggregator.latestAnswer(), price3);
        
        // 8. Remove authorization and verify access denied
        vm.prank(owner);
        aggregator.removeAuthorizedAddress(authorizedUser);
        
        vm.prank(authorizedUser);
        vm.expectRevert(abi.encodeWithSelector(CapyfiAggregatorV3.UnauthorizedCaller.selector, authorizedUser));
        aggregator.updateAnswer(65000e8);
    }

    // ============ Edge Case Tests ============
    
    function testTimestampAccuracy() public {
        uint256 beforeUpdate = block.timestamp;
        
        vm.prank(owner);
        aggregator.updateAnswer(51000e8);
        
        uint256 latestTimestamp = aggregator.latestTimestamp();
        assertEq(latestTimestamp, beforeUpdate);
        
        (, , uint256 startedAt, uint256 updatedAt, ) = aggregator.latestRoundData();
        assertEq(startedAt, beforeUpdate);
        assertEq(updatedAt, beforeUpdate);
    }
    
    function testRoundIdFormat() view public {
        // Verify round ID format matches Chainlink: (phaseId << 64) + originalId
        assertEq(aggregator.latestRound(), FIRST_ROUND_ID);
        
        // Extract phase and original round ID
        uint16 phaseId = aggregator.getPhaseId(FIRST_ROUND_ID);
        uint64 originalRoundId = aggregator.getOriginalRoundId(FIRST_ROUND_ID);
        
        assertEq(phaseId, 1);
        assertEq(originalRoundId, 1);
        
        // Verify reconstruction
        uint80 reconstructed = uint80((uint256(phaseId) << 64) + originalRoundId);
        assertEq(reconstructed, FIRST_ROUND_ID);
    }
} 