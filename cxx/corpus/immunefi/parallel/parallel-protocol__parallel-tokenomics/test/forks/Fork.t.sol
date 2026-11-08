// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "../Base.t.sol";

/// @notice Common logic needed by all fork tests.
abstract contract Fork_Test is Base_Test {
    address bal;
    address aura;

    function setUp() public virtual override {
        // Fork Polygon Mainnet at a specific block number.
        vm.createSelectFork({ blockNumber: 21_816_469, urlOrAlias: "mainnet" });

        // The base is set up after the fork is selected so that the base test contracts are deployed on the fork.
        Base_Test.setUp();

        _setForkContracts();

        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(bal);
        rewardTokens[1] = address(aura);

        sprl2 = _deploySPRL2(
            address(auraBpt),
            users.daoTreasury.addr,
            address(accessManager),
            DEFAULT_PENALTY_PERCENTAGE,
            DEFAULT_TIME_LOCK_DURATION,
            sPRL2.BPTConfigParams({
                balancerRouter: balancerV3RouterMock,
                auraBoosterLite: auraBoosterLiteMock,
                auraRewardsPool: auraRewardPoolMock,
                balancerBPT: bpt,
                prl: prl,
                weth: weth,
                rewardTokens: rewardTokens,
                permit2: permit2
            })
        );
    }

    function _setForkContracts() internal virtual {
        permit2 = Permit2Mock(0x000000000022D473030F116dDEE9F6B43aC78BA3);
        vm.label({ account: address(permit2), newLabel: "Permit2" });

        auraBpt = ERC20Mock(0x473dA6619e3bf97f946C6Cc991952c010e25eC3E);
        vm.label({ account: address(auraBpt), newLabel: "AuraBPT" });
        balancerV3RouterMock = BalancerV3RouterMock(0x5C6fb490BDFD3246EB0bB062c168DeCAF4bD9FDd);
        vm.label({ account: address(balancerV3RouterMock), newLabel: "BalancerV3RouterMock" });
        auraBoosterLiteMock = AuraBoosterLiteMock(0xA57b8d98dAE62B26Ec3bcC4a365338157060B234);
        vm.label({ account: address(auraBoosterLiteMock), newLabel: "AuraBoosterLiteMock" });
        auraRewardPoolMock = AuraRewardPoolMock(0x473dA6619e3bf97f946C6Cc991952c010e25eC3E);
        vm.label({ account: address(auraRewardPoolMock), newLabel: "AuraRewardPoolMock" });

        bal = 0xba100000625a3754423978a60c9317c58a424e3D;
        vm.label({ account: address(bal), newLabel: "BAL" });
        aura = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;
        vm.label({ account: address(aura), newLabel: "Aura" });
        bpt = ERC20Mock(0x5512fdDC40842b257e2A7742Be3DaDcf31574d53);
        vm.label({ account: address(bpt), newLabel: "BPT" });
        prl = ERC20Mock(0x04C154b66CB340F3Ae24111CC767e0184Ed00Cc6);
        vm.label({ account: address(prl), newLabel: "PRL" });
        weth = WrappedNativeMock(0x1e6ffa4e9F63d10B8820A3ab52566Af881Dab53c);
        vm.label({ account: address(weth), newLabel: "WETH" });
    }
}
