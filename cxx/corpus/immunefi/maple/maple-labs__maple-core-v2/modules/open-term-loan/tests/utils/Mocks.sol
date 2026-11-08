// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../../modules/forge-std/src/Test.sol";

import { MockERC20 } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

// TODO: Eventually propose this to `forge-std`.
contract Spied is Test {

    bool internal assertCalls;
    bool internal captureCall;

    uint256 callCount;

    bytes[] internal calls;

    modifier spied() {
        if (captureCall) {
            calls.push(msg.data);
            captureCall = false;
        } else {
            if (assertCalls) {
                assertEq(msg.data, calls[callCount++], "Unexpected call spied");
            }

            _;
        }
    }

    function __expectCall() public {
        assertCalls = true;
        captureCall = true;
    }

}

contract MockFactory is Spied {

    address public mapleGlobals;

    mapping(address => bool) public isInstance;

    function upgradeInstance(uint256 version_, bytes calldata arguments_) external spied {}

    function __setGlobals(address globals_) external {
        mapleGlobals = globals_;
    }

    function __setIsInstance(address instance, bool isInstance_) external {
        isInstance[instance] = isInstance_;
    }

}

contract MockGlobals {

    bool internal _canDeploy;
    bool internal _isFunctionPaused;

    address public governor;
    address public securityAdmin;

    bool public protocolPaused;

    mapping(address => bool) public isBorrower;
    mapping(address => bool) public isPoolAsset;

    mapping(address => uint256) public platformServiceFeeRate;

    mapping(bytes32 => mapping(address => bool)) public isInstanceOf;

    function canDeploy(address) external view returns (bool canDeploy_) {
        canDeploy_ = _canDeploy;
    }

    function isFunctionPaused(bytes4) external view returns (bool isFunctionPaused_) {
        isFunctionPaused_ = _isFunctionPaused;
    }

    function __setCanDeploy(bool canDeploy_) external {
        _canDeploy = canDeploy_;
    }

    function __setFunctionPaused(bool paused_) external {
        _isFunctionPaused = paused_;
    }

    function __setGovernor(address governor_) external {
        governor = governor_;
    }

    function __setIsBorrower(address borrower_, bool isBorrower_) external {
        isBorrower[borrower_] = isBorrower_;
    }

    function __setIsInstanceOf(bytes32 instanceId_, address instance_, bool isInstance_) external {
        isInstanceOf[instanceId_][instance_] = isInstance_;
    }

    function __setIsPoolAsset(address poolAsset_, bool isPoolAsset_) external {
        isPoolAsset[poolAsset_] = isPoolAsset_;
    }

    function __setPlatformServiceFeeRate(address poolManager_, uint256 platformServiceFeeRate_) external {
        platformServiceFeeRate[poolManager_] = platformServiceFeeRate_;
    }

    function __setProtocolPaused(bool paused_) external {
        protocolPaused = paused_;
    }

    function __setSecurityAdmin(address securityAdmin_) external {
        securityAdmin = securityAdmin_;
    }

}

contract MockImplementation {

    fallback() external {}

}

contract MockLender is Spied {

    address public factory;
    address public fundsAsset;
    address public poolManager;

    function claim(
        int256  principal_,
        uint256 interest_,
        uint256 delegateServiceFee_,
        uint256 platformServiceFee_,
        uint40  paymentDueDate_
    ) external spied {}

    function __setFactory(address factory_) external {
        factory = factory_;
    }

    function __setFundsAsset(address fundsAsset_) external {
        fundsAsset = fundsAsset_;
    }

    function __setPoolManager(address poolManager_) external {
        poolManager = poolManager_;
    }

}

contract MockMigrator {

    fallback() external {}

}

contract MockRevertingERC20 is MockERC20 {

    constructor(string memory name_, string memory symbol_, uint8 decimals_) MockERC20(name_, symbol_, decimals_) {}

    function transfer(address, uint256) public override pure returns (bool success_) {
        success_;
        require(false);
    }

    function transferFrom(address, address, uint256) public override pure returns (bool success_) {
        success_;
        require(false);
    }

}

contract MockRevertingRefinancer {

    function revertingFunction() external pure {
        require(false);
    }

}
