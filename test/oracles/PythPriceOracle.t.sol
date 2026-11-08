// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import { PythPriceOracle } from "src/extras/PythPriceOracle.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { IPriceOracle } from "src/extras/IPriceOracle.sol";
import { MockPyth, PythStructs } from "test/mock/oracle/MockPyth.sol";

contract PythPriceOracleTest is Test, Create2Deployer {
    PythPriceOracle _pythPriceOracle;
    MockPyth _mockedPyth;
    address _governance = makeAddr("governance");
    address _manager = makeAddr("manager");

    function setUp() public {
        PythPriceOracle _pythPriceOracleImpl = new PythPriceOracle();
        _pythPriceOracle = PythPriceOracle(deployProxyWithCreate2(address(_pythPriceOracleImpl), 0));
        _mockedPyth = new MockPyth();
    }

    modifier initialize() {
        _pythPriceOracle.initialize(_governance);
        vm.prank(_governance);
        _pythPriceOracle.setPythSource(address(_mockedPyth));

        bytes32 role_ = _pythPriceOracle.MANAGER_ROLE();
        vm.prank(_governance);
        _pythPriceOracle.grantRole(role_, _manager);
        assert(_pythPriceOracle.hasRole(_pythPriceOracle.MANAGER_ROLE(), _manager));
        _;
    }

    function test_initialize_zeroAddress() public {
        // Governance address cannot be zero
        vm.expectRevert(IPriceOracle.ZeroAddress.selector);
        _pythPriceOracle.initialize(address(0));

        // Pyth oracle address cannot be zero
        _pythPriceOracle.initialize(address(0x1));
        vm.prank(address(0x1));
        vm.expectRevert(IPriceOracle.ZeroAddress.selector);
        _pythPriceOracle.setPythSource(address(0));
    }

    function testFuzz_initialize(address governance_, address pythOracle_) public {
        assumeNotZeroAddress(pythOracle_);
        assumeNotZeroAddress(governance_);

        _pythPriceOracle.initialize(governance_);
        vm.prank(governance_);
        _pythPriceOracle.setPythSource(pythOracle_);

        assertEq(address(_pythPriceOracle.pyth()), pythOracle_);
    }

    function test_setPriceFeed() public initialize {
        address asset = makeAddr("USDC");
        bytes32 feed = "priceFeed";

        _mockedPyth.setReturn(feed, PythStructs.Price(1, 1, -1, block.timestamp));
        _setPriceFeed(asset, feed);

        assertEq(_pythPriceOracle.feeds(asset), feed);
    }

    function test_setPriceFeed_WrongFeed() public {
        // Initialize with wrong Pyth oracle address in order to revert when try to call getPrice
        // TODO: Update if setter is add
        _pythPriceOracle.initialize(_governance);
        vm.prank(_governance);
        _pythPriceOracle.setPythSource(address(0x2));
        bytes32 role_ = _pythPriceOracle.MANAGER_ROLE();
        vm.prank(_governance);
        _pythPriceOracle.grantRole(role_, _manager);
        assert(_pythPriceOracle.hasRole(_pythPriceOracle.MANAGER_ROLE(), _manager));

        vm.expectRevert();
        _setPriceFeed(address(0x1), "wrongFeed");
    }

    function test_getPrice() public initialize {
        bytes32 feed = "priceFeed";
        _mockedPyth.setReturn(feed, PythStructs.Price(1, 1, -1, block.timestamp));
        _setPriceFeed(address(0x1), "priceFeed");

        IPriceOracle.Data memory priceData = _pythPriceOracle.getPrice(address(0x1));
        assertEq(priceData.price, 1e17);
        assertEq(priceData.publishTime, block.timestamp);
    }

    function _setPriceFeed(address asset, bytes32 feed) internal {
        vm.prank(_manager);
        _pythPriceOracle.setPriceFeed(asset, feed);
    }
}
