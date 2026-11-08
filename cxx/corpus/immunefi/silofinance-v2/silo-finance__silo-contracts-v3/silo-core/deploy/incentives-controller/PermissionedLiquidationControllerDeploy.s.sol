// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {SiloIncentivesControllerDeployments} from "./SiloIncentivesControllerDeployments.sol";

import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {console2} from "forge-std/console2.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {CommonDeploy} from "../_CommonDeploy.sol";
import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {
    IPermissionedLiquidationControllerFactory
} from "silo-core/contracts/interfaces/IPermissionedLiquidationControllerFactory.sol";

/*
    SILO_CONFIG=0xfAa8b214A896Dfd41FA0aaE07D55E6b15b59357a \
    DEBT=false \
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/incentives-controller/PermissionedLiquidationControllerDeploy.s.sol \
        --ffi --rpc-url $RPC_MAINNET --broadcast --verify

    resume verification:
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/incentives-controller/PermissionedLiquidationControllerDeploy.s.sol \
        --ffi --rpc-url $RPC_MAINNET \
        --verify \
        --verifier-url $VERIFIER_URL_MAINNET \
        --private-key $PRIVATE_KEY \
        --resume
 */
contract PermissionedLiquidationControllerDeploy is CommonDeploy, StdCheats {
    error FactoryNotFound();

    IPermissionedLiquidationControllerFactory factory;

    function run() public {
        // if we care only about liquidation, not pausing, then we don't have to deploy for debt share token
        if (!vm.envBool("DEBT")) {
            console2.log("\n\tSkipping debt share token deployment\n");
            console2.log("\tif this deployment is for pausing, then please use DEBT=true.\n");
        }

        ISiloConfig siloConfig = ISiloConfig(vm.envAddress("SILO_CONFIG"));
        (address silo0, address silo1) = siloConfig.getSilos();

        address notifier = IShareToken(silo0).hookReceiver();

        factory = IPermissionedLiquidationControllerFactory(
            SiloCoreDeployments.get(
                SiloCoreContracts.PERMISSIONED_LIQUIDATION_CONTROLLER_FACTORY, ChainsLib.chainAlias()
            )
        );

        require(
            address(factory) != address(0),
            string.concat(SiloCoreContracts.PERMISSIONED_LIQUIDATION_CONTROLLER_FACTORY, " not found")
        );

        console2.log("SILO ID:", siloConfig.SILO_ID(), ", config: ", vm.toString(address(siloConfig)));

        console2.log("Deploying for silo 0");
        (address incentivesControllerC0, address incentivesControllerP0, address incentivesControllerD0) =
            _deployForSilo(siloConfig, silo0, notifier);

        _qa({
            _siloConfig: siloConfig,
            _hook: notifier,
            _incentivesControllerC: incentivesControllerC0,
            _incentivesControllerP: incentivesControllerP0,
            _incentivesControllerD: incentivesControllerD0
        });

        console2.log("Deploying for silo 1");
        (address incentivesControllerC1, address incentivesControllerP1, address incentivesControllerD1) =
            _deployForSilo(siloConfig, silo1, notifier);

        _qa({
            _siloConfig: siloConfig,
            _hook: notifier,
            _incentivesControllerC: incentivesControllerC1,
            _incentivesControllerP: incentivesControllerP1,
            _incentivesControllerD: incentivesControllerD1
        });

        _save(incentivesControllerC0);
        _save(incentivesControllerP0);
        _save(incentivesControllerD0);

        _save(incentivesControllerC1);
        _save(incentivesControllerP1);
        _save(incentivesControllerD1);
    }

    function _save(address _incentivesController) internal {
        if (_incentivesController == address(0)) return;

        SiloIncentivesControllerDeployments.save({
            _chain: ChainsLib.chainAlias(),
            _shareToken: ISiloIncentivesController(_incentivesController).SHARE_TOKEN(),
            _deployed: _incentivesController
        });
    }

    function _deployForSilo(ISiloConfig _siloConfig, address _silo, address _hook)
        private
        returns (address incentivesControllerC, address incentivesControllerP, address incentivesControllerD)
    {
        ISiloConfig.ConfigData memory config = _siloConfig.getConfig(_silo);
        
        if (config.lt == 0) {
            console2.log("LT is 0, not collateral silo, skipping deployment");
            return (address(0), address(0), address(0));
        }

        address collateralShareTokenAddress = config.collateralShareToken;
        address protectedShareTokenAddress = config.protectedShareToken;
        address debtShareTokenAddress = config.debtShareToken;

        ISiloIncentivesController debtGauge =
            IGaugeHookReceiver(_hook).configuredGauges(IShareToken(debtShareTokenAddress));
        
        bool deployForDebt = vm.envBool("DEBT") &&address(debtGauge) == address(0);

        vm.startBroadcast(uint256(vm.envBytes32("PRIVATE_KEY")));

        incentivesControllerC = factory.create(IShareToken(collateralShareTokenAddress));

        incentivesControllerP = factory.create(IShareToken(protectedShareTokenAddress));

        if (deployForDebt) {
            incentivesControllerD = factory.create(IShareToken(debtShareTokenAddress));
        }

        vm.stopBroadcast();

        // hook receiver ownership acceptance data
        console2.log(
            "\nHook(%s).setGauge(\n\tgauge: %s,\n\tcollateralShareToken: %s\n)", _hook, incentivesControllerC, collateralShareTokenAddress
        );

        console2.log(
            "\nHook(%s).setGauge(\n\tgauge: %s,\n\tprotectedShareToken: %s\n)", _hook, incentivesControllerP, protectedShareTokenAddress
        );

        if (deployForDebt) {
            console2.log(
                "\nHook(%s).setGauge(\n\tgauge: %s,\n\tdebtShareToken: %s\n)", _hook, incentivesControllerD, debtShareTokenAddress
            );
        }
    }

    function _qa(
        ISiloConfig _siloConfig,
        address _hook,
        address _incentivesControllerC,
        address _incentivesControllerP,
        address _incentivesControllerD
    ) internal {
        if (_incentivesControllerC == address(0) && _incentivesControllerP == address(0) && _incentivesControllerD == address(0)) {
            console2.log("No incentives controllers deployed, skipping QA");
            return;
        }

        console2.log("--- QA ---");

        bool deployForDebt = _incentivesControllerD != address(0);
        IShareToken shareToken;

        vm.startPrank(Ownable(_hook).owner());

        if (_incentivesControllerC != address(0)) {
            shareToken = IShareToken(ISiloIncentivesController(_incentivesControllerC).SHARE_TOKEN());
            ISiloIncentivesController gauge = IGaugeHookReceiver(_hook).configuredGauges(shareToken);
            
            if (address(gauge) != address(0)) {
                console2.log("existing gauge: ", address(gauge));
                revert("Gauge already configured for collateral share token");
            }

            IGaugeHookReceiver(_hook)
                .setGauge({
                    _gauge: ISiloIncentivesController(_incentivesControllerC),
                    _shareToken: shareToken
                });
        }

        if (_incentivesControllerP != address(0)) {
            shareToken = IShareToken(ISiloIncentivesController(_incentivesControllerP).SHARE_TOKEN());
            ISiloIncentivesController gauge = IGaugeHookReceiver(_hook).configuredGauges(shareToken);
            
            if (address(gauge) != address(0)) {
                console2.log("existing gauge: ", address(gauge));
                revert("Gauge already configured for protected share token");
            }
            
            IGaugeHookReceiver(_hook)
                .setGauge({
                    _gauge: ISiloIncentivesController(_incentivesControllerP),
                    _shareToken: shareToken
                });
        }

        if (deployForDebt && _incentivesControllerD != address(0)) {
            IGaugeHookReceiver(_hook)
                .setGauge({
                    _gauge: ISiloIncentivesController(_incentivesControllerD),
                    _shareToken: IShareToken(ISiloIncentivesController(_incentivesControllerD).SHARE_TOKEN())
                });
        }

        vm.stopPrank();

        _qaSiloSmoke(_siloConfig);

        vm.startPrank(Ownable(_hook).owner());

        shareToken = IShareToken(ISiloIncentivesController(_incentivesControllerC).SHARE_TOKEN());
        IGaugeHookReceiver(_hook).removeGauge(shareToken);

        shareToken = IShareToken(ISiloIncentivesController(_incentivesControllerP).SHARE_TOKEN());
        IGaugeHookReceiver(_hook).removeGauge(shareToken);

        if (deployForDebt) {
            shareToken = IShareToken(ISiloIncentivesController(_incentivesControllerD).SHARE_TOKEN());
            IGaugeHookReceiver(_hook).removeGauge(shareToken);
        }

        vm.stopPrank();

        console2.log("--- QA PASS ---");
    }

    function _qaSiloSmoke(ISiloConfig siloConfig) private {
        address depositor = makeAddr("depositor");
        (address silo0Addr, address silo1Addr) = siloConfig.getSilos();
        ISilo silo0 = ISilo(silo0Addr);
        ISilo silo1 = ISilo(silo1Addr);

        (uint256 unit0, uint256 unit1) = _qaDealForSilos(silo0, silo1, depositor);

        vm.startPrank(depositor);

        _qaDepositOnSilo(silo0, depositor, unit0 * 100);
        _qaDepositOnSilo(silo1, depositor, unit1 * 100);

        vm.warp(block.timestamp + 1 days);

        require(_qaBorrow(silo0, depositor) || _qaBorrow(silo1, depositor), "QA: borrow failed");
    }

    function _qaDealForSilos(ISilo silo0, ISilo silo1, address depositor)
        private
        returns (uint256 unit0, uint256 unit1)
    {
        address asset0 = silo0.asset();
        address asset1 = silo1.asset();
        unit0 = 10 ** uint256(IERC20Metadata(asset0).decimals());
        unit1 = 10 ** uint256(IERC20Metadata(asset1).decimals());
        deal(asset0, depositor, unit0 * 2_000);
        deal(asset1, depositor, unit1 * 2_000);
    }

    function _qaDepositOnSilo(ISilo _silo, address _depositor, uint256 _amount) private {
        address asset = _silo.asset();
        IERC20(asset).approve(address(_silo), type(uint256).max);
        _silo.deposit(_amount, _depositor, ISilo.CollateralType.Protected);
        _silo.deposit(_amount, _depositor, ISilo.CollateralType.Collateral);
    }

    function _qaBorrow(ISilo _silo, address _depositor) internal returns (bool success) {
        uint256 maxBorrow0 = _silo.maxBorrow(_depositor);

        if (maxBorrow0 == 0) return false;

        uint256 shares = _silo.borrow(maxBorrow0, _depositor, _depositor);

        vm.warp(block.timestamp + 1 days);

        _silo.repayShares(shares, _depositor);
        success = true;
    }
}
