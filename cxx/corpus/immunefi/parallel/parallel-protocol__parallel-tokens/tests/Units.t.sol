// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "tests/Base.t.sol";

/// @notice Common logic for units tests.
abstract contract Units_Test is Base_Test {
    BridgeableTokenP.ConfigParams configParams;

    function setUp() public virtual override {
        Base_Test.setUp();

        configParams = BridgeableTokenP.ConfigParams({
             dailyCreditLimit: DEFAULT_DAILY_CREDIT_LIMIT,
            globalCreditLimit: DEFAULT_GLOBAL_CREDIT_LIMIT,
            dailyDebitLimit: DEFAULT_DAILY_DEBIT_LIMIT,
            globalDebitLimit: DEFAULT_GLOBAL_DEBIT_LIMIT,
            feesRecipient: users.feesRecipient.addr,
            feesRate: DEFAULT_FEE_RATE,
            isIsolateMode: false
        });

        setUpEndpoints(1, LibraryType.UltraLightNode);
        aBridgeableTokenp = new BridgeableTokenP(
            "aLz-EURp",
            "aLzEURp",
            address(aEURp),
            address(endpoints[aEid]),
            address(accessManager),
            configParams
        );
        vm.startPrank(users.admin.addr);
        accessManager.setTargetFunctionRole(address(aBridgeableTokenp), getGovernorBridgeableTokenPSelectorAccess(), GOVERNOR_ROLE);
        accessManager.setTargetFunctionRole(address(aBridgeableTokenp), getGuardianBridgeableTokenPSelectorAccess(), GUARDIAN_ROLE);
        accessManager.grantRole(MINTER_ROLE_aEURp, address(aBridgeableTokenp),0);
        vm.stopPrank();

        _deployFlashParallelToken(address(accessManager), users.feesRecipient.addr);
        vm.startPrank(users.admin.addr);
        accessManager.setTargetFunctionRole(address(flashParallelToken), getGovernorFlashParallelTokenSelectorAccess(), GOVERNOR_ROLE);
        accessManager.grantRole(MINTER_ROLE_aEURp, address(flashParallelToken),0);
        vm.stopPrank();
    }
}
