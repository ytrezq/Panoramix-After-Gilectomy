// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import { MockERC20 } from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";

import { MapleWithdrawalManagerStorage } from "../../contracts/proxy/MapleWithdrawalManagerStorage.sol";

contract MockFactory {

    bool _isInstance;

    function isInstance(address) external view returns (bool isInstance_) {
        isInstance_ = _isInstance;
    }

    function __setIsInstance(bool isInstance_) external {
        _isInstance = isInstance_;
    }

}

contract MockGlobals {

    address public governor;
    address public operationalAdmin;
    address public securityAdmin;

    bool internal _canDeploy;
    bool internal _isFunctionPaused;
    bool internal _isInstance;
    bool internal _isValidScheduledCall;

    bool public protocolPaused;

    constructor (address governor_) {
        governor = governor_;
    }

    function canDeploy(address) external view returns (bool) {
        return _canDeploy;
    }

    function isFunctionPaused(bytes4) external view returns (bool isFunctionPaused_) {
        isFunctionPaused_ = _isFunctionPaused;
    }

    function isInstanceOf(bytes32, address) external view returns (bool isInstance_) {
        isInstance_ = _isInstance;
    }

    function isValidScheduledCall(address, address, bytes32, bytes calldata) external view returns (bool isValid_) {
        isValid_ = _isValidScheduledCall;
    }

    function unscheduleCall(address, bytes32, bytes calldata) external {}

    function __setCanDeploy(bool canDeploy_) external {
        _canDeploy = canDeploy_;
    }

    function __setFunctionPaused(bool paused_) external {
        _isFunctionPaused = paused_;
    }

    function __setIsInstanceOf(bool isInstance_) external {
        _isInstance = isInstance_;
    }

    function __setIsValidScheduledCall(bool isValid_) external {
        _isValidScheduledCall = isValid_;
    }

    function __setOperationalAdmin(address operationalAdmin_) external {
        operationalAdmin = operationalAdmin_;
    }

    function __setSecurityAdmin(address securityAdmin_) external {
        securityAdmin = securityAdmin_;
    }

}

contract MockPool is MockERC20 {

    address public manager;
    address public poolDelegate;

    uint256 public sharePrice;

    MockERC20 _asset;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address asset_,
        address poolDelegate_
    )
        MockERC20(name_, symbol_, decimals_)
    {
        _asset = MockERC20(asset_);

        poolDelegate = poolDelegate_;
        sharePrice   = 1;
    }

    function asset() external view returns (address asset_) {
        asset_ = address(_asset);
    }

    function redeem(uint256, address, address) external returns (uint256 assets_) {
        assets_;  // Ignore variable
    }

    function __setPoolManager(address poolManager_) external {
        manager = poolManager_;
    }

}

contract MockPoolManager {

    address public factory;
    address public globals;
    address public pool;
    address public poolDelegate;

    uint256 public totalAssets;
    uint256 public unrealizedLosses;

    constructor(address pool_, address poolDelegate_, address globals_) {
        globals      = globals_;
        pool         = pool_;
        poolDelegate = poolDelegate_;
    }

    function __setFactory(address factory_) external {
        factory = factory_;
    }

    function __setTotalAssets(uint256 totalAssets_) external  {
        totalAssets = totalAssets_;
    }

}

contract MockWithdrawalManagerMigrator is MapleWithdrawalManagerStorage {

    fallback() external {
        pool = abi.decode(msg.data, (address));
    }

}
