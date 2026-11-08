// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Test } from "forge-std/Test.sol";
import { RootPriceOracle } from "src/extras/RootPriceOracle.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { IPriceOracle } from "src/extras/IPriceOracle.sol";
import { IRootPriceOracle } from "src/extras/IRootPriceOracle.sol";
import { MockOracle, MockFeed } from "test/mock/oracle/MockOracle.sol";

contract RootPriceOracleTest is Test, Create2Deployer {
    RootPriceOracle _rootPriceOracle;
    MockOracle _mockPythPriceOracle;
    MockOracle _mockSpotPriceOracle;
    MockFeed _mockSpotFeed;
    MockFeed _mockPythFeed;

    uint256 internal constant MOCK_PYTH_PRICE = 100;
    uint256 internal constant MOCK_SPOT_PRICE = 90;
    uint256 internal constant UNAVAILABILITY_TIMESTAMP = 0;
    uint256 internal constant AVAILABILITY_TIMESTAMP = 100;

    address token = makeAddr("token");
    address initialAdmin = makeAddr("initialAdmin");
    address manager = makeAddr("manager");

    function setUp() public {
        _mockPythPriceOracle = new MockOracle();
        _mockPythFeed = new MockFeed();
        _mockPythPriceOracle.setPriceFeed(address(token), _mockPythFeed);

        _mockSpotPriceOracle = new MockOracle();
        _mockSpotFeed = new MockFeed();
        _mockSpotPriceOracle.setPriceFeed(address(token), _mockSpotFeed);

        _rootPriceOracle = new RootPriceOracle();
        _rootPriceOracle.initialize(initialAdmin);

        vm.startPrank(initialAdmin);
        _rootPriceOracle.grantRole(_rootPriceOracle.MANAGER_ROLE(), manager);
        vm.stopPrank();
    }

    function _setPythOracle() internal {
        vm.expectEmit();
        emit IRootPriceOracle.PythOracleSet(address(_mockPythPriceOracle));
        vm.prank(manager);
        _rootPriceOracle.setPythOracle(address(_mockPythPriceOracle));
        assertEq(address(_rootPriceOracle.pythOracle()), address(_mockPythPriceOracle));
    }

    function _setSpotOracle() internal {
        vm.expectEmit();
        emit IRootPriceOracle.SpotOracleSet(address(_mockSpotPriceOracle));
        vm.prank(manager);
        _rootPriceOracle.setSpotOracle(address(_mockSpotPriceOracle));
        assertEq(address(_rootPriceOracle.spotOracle()), address(_mockSpotPriceOracle));
    }

    function _setBothOracles() internal {
        _setPythOracle();
        _setSpotOracle();
    }

    function test_setUp() public view {
        assertEq(address(_mockPythPriceOracle.feeds(address(token))), address(_mockPythFeed));
        assertEq(address(_mockSpotPriceOracle.feeds(address(token))), address(_mockSpotFeed));
        assert(_rootPriceOracle.hasRole(_rootPriceOracle.DEFAULT_ADMIN_ROLE(), initialAdmin));
    }

    function test_constructor_revertsWhen_initialAdminIsZeroAddress() public {
        RootPriceOracle tmp = new RootPriceOracle();
        vm.expectRevert(IPriceOracle.ZeroAddress.selector);
        tmp.initialize(address(0));
    }

    function test_setSpotOracle_setsNewSpotOracle_andEmitsEvent() public {
        address newSpotOracle = makeAddr("newSpotOracle");
        assertNotEq(address(_rootPriceOracle.spotOracle()), newSpotOracle);

        vm.expectEmit();
        emit IRootPriceOracle.SpotOracleSet(newSpotOracle);

        vm.startPrank(manager);
        _rootPriceOracle.setSpotOracle(newSpotOracle);
        vm.stopPrank();

        assertEq(address(_rootPriceOracle.spotOracle()), newSpotOracle);
    }

    function test_setSpotOracle_revertsWhen_newSpotOracleIsZeroAddress() public {
        vm.expectRevert(IPriceOracle.ZeroAddress.selector);
        vm.startPrank(manager);
        _rootPriceOracle.setSpotOracle(address(0));
        vm.stopPrank();
    }

    function test_setSpotOracle_revertsWhen_callerIsNotManager() public {
        address newSpotOracle = makeAddr("newSpotOracle");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, initialAdmin, _rootPriceOracle.MANAGER_ROLE()
            )
        );

        vm.startPrank(initialAdmin);
        _rootPriceOracle.setSpotOracle(newSpotOracle);
        vm.stopPrank();
    }

    function test_setPythOracle_setsNewPythOracle_andEmitsEvent() public {
        address newPythOracle = makeAddr("newPythOracle");

        assertNotEq(address(_rootPriceOracle.pythOracle()), newPythOracle);

        vm.expectEmit();
        emit IRootPriceOracle.PythOracleSet(newPythOracle);

        vm.startPrank(manager);
        _rootPriceOracle.setPythOracle(newPythOracle);
        vm.stopPrank();

        assertEq(address(_rootPriceOracle.pythOracle()), newPythOracle);
    }

    function test_setPythOracle_revertsWhen_newPythOracleIsZeroAddress() public {
        vm.expectRevert(IPriceOracle.ZeroAddress.selector);
        vm.startPrank(manager);
        _rootPriceOracle.setPythOracle(address(0));
        vm.stopPrank();
    }

    function test_setPythOracle_revertsWhen_callerIsNotManager() public {
        address newPythOracle = makeAddr("newPythOracle");

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, initialAdmin, _rootPriceOracle.MANAGER_ROLE()
            )
        );
        vm.prank(initialAdmin);
        _rootPriceOracle.setPythOracle(newPythOracle);
    }

    function test_getPrice_returnsPythPriceWhen_onlyPythOracleIsSet() public {
        _setPythOracle();
        _setMockPythPrice(MOCK_PYTH_PRICE, AVAILABILITY_TIMESTAMP);
        assert(_mockPythPriceOracle.priceAvailable(token));
        IPriceOracle.Data memory price = _rootPriceOracle.getPrice(address(token));
        assertEq(price.price, MOCK_PYTH_PRICE);
    }

    function test_getPrice_returnsPythPriceWhen_onlyPythOracleIsAvailable() public {
        _setPythOracle();
        _setMockPythPrice(MOCK_PYTH_PRICE, AVAILABILITY_TIMESTAMP);
        _setMockSpotPrice(MOCK_SPOT_PRICE, UNAVAILABILITY_TIMESTAMP);
        assert(_mockPythPriceOracle.priceAvailable(token));
        assert(!_mockSpotPriceOracle.priceAvailable(token));
        IPriceOracle.Data memory price = _rootPriceOracle.getPrice(address(token));
        assertEq(price.price, MOCK_PYTH_PRICE);
    }

    function test_getPrice_returnsPriceWithMaxDeviationFromOneWAD_whenBothOraclesAreAvailable() public {
        uint256 expectedPrice = MOCK_SPOT_PRICE;
        _setBothOracles();

        _setMockPythPrice(MOCK_PYTH_PRICE, AVAILABILITY_TIMESTAMP);
        _setMockSpotPrice(MOCK_SPOT_PRICE, AVAILABILITY_TIMESTAMP);

        IPriceOracle.Data memory price = _rootPriceOracle.getPrice(address(token));
        assertEq(price.price, expectedPrice);
    }

    function test_getPrice_revertsWhen_pythOracleIsNotSet() public {
        _setSpotOracle();
        assertEq(address(_rootPriceOracle.pythOracle()), address(0));
        _setMockSpotPrice(MOCK_SPOT_PRICE, AVAILABILITY_TIMESTAMP);
        assert(_mockSpotPriceOracle.priceAvailable(token));
        vm.expectRevert(IRootPriceOracle.UnreliablePrice.selector);
        _rootPriceOracle.getPrice(address(token));
    }

    function test_getPrice_revertsWhen_pythOracleIsNotAvailable() public {
        _setBothOracles();
        _setMockPythPrice(MOCK_PYTH_PRICE, UNAVAILABILITY_TIMESTAMP);
        _setMockSpotPrice(MOCK_SPOT_PRICE, AVAILABILITY_TIMESTAMP);
        assert(!_mockPythPriceOracle.priceAvailable(token));
        assert(_mockSpotPriceOracle.priceAvailable(token));
        vm.expectRevert(IRootPriceOracle.UnreliablePrice.selector);
        _rootPriceOracle.getPrice(address(token));
    }

    function test_getPriceUnsafe_returnsPythPriceWhen_onlyPythOracleIsAvailable() public {
        _setBothOracles();
        _setMockPythPrice(MOCK_PYTH_PRICE, AVAILABILITY_TIMESTAMP);
        _setMockSpotPrice(MOCK_SPOT_PRICE, UNAVAILABILITY_TIMESTAMP);
        assert(_mockPythPriceOracle.priceAvailable(token));
        assert(!_mockSpotPriceOracle.priceAvailable(token));
        IPriceOracle.Data memory price = _rootPriceOracle.getPriceUnsafe(address(token));
        assertEq(price.price, MOCK_PYTH_PRICE);
    }

    function test_getPriceUnsafe_returnsPriceWithMaxDeviationFromOneWAD_whenBothOraclesAreAvailable() public {
        uint256 expectedPrice = MOCK_SPOT_PRICE;
        _setBothOracles();

        _setMockPythPrice(MOCK_PYTH_PRICE, AVAILABILITY_TIMESTAMP);
        _setMockSpotPrice(MOCK_SPOT_PRICE, AVAILABILITY_TIMESTAMP);

        IPriceOracle.Data memory price = _rootPriceOracle.getPriceUnsafe(address(token));
        assertEq(price.price, expectedPrice);
    }

    function test_getPriceUnsafe_revertsWhen_pythOracleIsNotAvailable() public {
        _setBothOracles();
        _setMockPythPrice(MOCK_PYTH_PRICE, UNAVAILABILITY_TIMESTAMP);
        _setMockSpotPrice(MOCK_SPOT_PRICE, AVAILABILITY_TIMESTAMP);
        assert(!_mockPythPriceOracle.priceAvailable(token));
        assert(_mockSpotPriceOracle.priceAvailable(token));
        vm.expectRevert(IRootPriceOracle.UnreliablePrice.selector);
        _rootPriceOracle.getPriceUnsafe(address(token));
    }

    function test_getPriceNoOlderThan_returnsPythPriceWhen_onlyPythOracleIsAvailable() public {
        _setBothOracles();
        _setMockPythPrice(MOCK_PYTH_PRICE, AVAILABILITY_TIMESTAMP);
        _setMockSpotPrice(MOCK_SPOT_PRICE, UNAVAILABILITY_TIMESTAMP);
        assert(_mockPythPriceOracle.priceAvailable(token));
        assert(!_mockSpotPriceOracle.priceAvailable(token));
        IPriceOracle.Data memory price = _rootPriceOracle.getPriceNoOlderThan(address(token), AVAILABILITY_TIMESTAMP);
        assertEq(price.price, MOCK_PYTH_PRICE);
    }

    function test_getPriceNoOlderThan_returnsPriceWithMaxDeviationFromOneWAD_whenBothOraclesAreAvailable() public {
        uint256 expectedPrice = MOCK_SPOT_PRICE;
        _setBothOracles();

        _setMockPythPrice(MOCK_PYTH_PRICE, AVAILABILITY_TIMESTAMP);
        _setMockSpotPrice(MOCK_SPOT_PRICE, AVAILABILITY_TIMESTAMP);

        IPriceOracle.Data memory price = _rootPriceOracle.getPriceNoOlderThan(address(token), AVAILABILITY_TIMESTAMP);
        assertEq(price.price, expectedPrice);
    }

    function test_getPriceNoOlderThan_revertsWhen_pythOracleIsNotAvailable() public {
        _setBothOracles();
        _setMockPythPrice(MOCK_PYTH_PRICE, UNAVAILABILITY_TIMESTAMP);
        _setMockSpotPrice(MOCK_SPOT_PRICE, AVAILABILITY_TIMESTAMP);
        assert(!_mockPythPriceOracle.priceAvailable(token));
        assert(_mockSpotPriceOracle.priceAvailable(token));
        vm.expectRevert(IRootPriceOracle.UnreliablePrice.selector);
        _rootPriceOracle.getPriceNoOlderThan(address(token), AVAILABILITY_TIMESTAMP);
    }

    function test_priceAvailable_returnsFalseWhen_pythOracleIsNotSet() public {
        RootPriceOracle rootPriceOracle = new RootPriceOracle();
        rootPriceOracle.initialize(initialAdmin);
        assert(!rootPriceOracle.priceAvailable(token));
    }

    function _setMockPythPrice(uint256 pythPrice, uint256 timestamp) internal {
        vm.warp(timestamp);
        _mockPythFeed.setPrice(pythPrice);
        assertEq(_mockPythFeed.getPrice().price, pythPrice);
        assertEq(_mockPythFeed.getPrice().publishTime, timestamp);
    }

    function _setMockSpotPrice(uint256 spotPrice, uint256 timestamp) internal {
        vm.warp(timestamp);
        _mockSpotFeed.setPrice(spotPrice);

        assertEq(_mockSpotFeed.getPrice().price, spotPrice);
        assertEq(_mockSpotFeed.getPrice().publishTime, timestamp);
    }
}
