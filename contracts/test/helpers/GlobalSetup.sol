// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {InstanceManagerHelper} from "../../test/helpers/InstanceManagerHelper.sol";
import {CrossChainMultisig, CrossChainCall} from "../../global/CrossChainMultisig.sol";
import {InstanceManager} from "../../instance/InstanceManager.sol";
import {PriceFeedStore} from "../../instance/PriceFeedStore.sol";
import {IBytecodeRepository} from "../../interfaces/IBytecodeRepository.sol";
import {IAddressProvider} from "../../interfaces/IAddressProvider.sol";
import {IInstanceManager} from "../../interfaces/IInstanceManager.sol";
import {Domain} from "../../libraries/Domain.sol";

import {IWETH} from "@gearbox-protocol/core-v3/contracts/interfaces/external/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {
    AP_ACCOUNT_FACTORY_DEFAULT,
    AP_BOT_LIST,
    AP_GEAR_STAKING,
    AP_PRICE_FEED_STORE,
    AP_INTEREST_RATE_MODEL_FACTORY,
    AP_CREDIT_FACTORY,
    AP_POOL_FACTORY,
    AP_PRICE_ORACLE_FACTORY,
    AP_RATE_KEEPER_FACTORY,
    AP_MARKET_CONFIGURATOR_FACTORY,
    AP_LOSS_POLICY_FACTORY,
    AP_GOVERNOR,
    AP_TREASURY_SPLITTER,
    AP_POOL,
    AP_POOL_QUOTA_KEEPER,
    AP_PRICE_ORACLE,
    AP_MARKET_CONFIGURATOR,
    AP_ACL,
    AP_CONTRACTS_REGISTER,
    AP_INTEREST_RATE_MODEL_LINEAR,
    AP_RATE_KEEPER_TUMBLER,
    AP_RATE_KEEPER_GAUGE,
    AP_LOSS_POLICY_ALIASED,
    AP_CREDIT_MANAGER,
    AP_CREDIT_FACADE,
    AP_CREDIT_CONFIGURATOR,
    AP_ZERO_PRICE_FEED,
    DOMAIN_ADAPTER,
    DOMAIN_BOT,
    DOMAIN_DEGEN_NFT,
    DOMAIN_IRM,
    DOMAIN_LOSS_POLICY,
    DOMAIN_PRICE_FEED,
    DOMAIN_RATE_KEEPER,
    DOMAIN_ZAPPER
} from "../../libraries/ContractLiterals.sol";
import {SignedBatch, Bytecode} from "../../interfaces/Types.sol";

import {CreditFactory} from "../../factories/CreditFactory.sol";
import {InterestRateModelFactory} from "../../factories/InterestRateModelFactory.sol";
import {LossPolicyFactory} from "../../factories/LossPolicyFactory.sol";
import {PoolFactory} from "../../factories/PoolFactory.sol";
import {PriceOracleFactory} from "../../factories/PriceOracleFactory.sol";
import {RateKeeperFactory} from "../../factories/RateKeeperFactory.sol";

import {MarketConfigurator} from "../../market/MarketConfigurator.sol";
import {MarketConfiguratorFactory} from "../../instance/MarketConfiguratorFactory.sol";
import {ACL} from "../../market/ACL.sol";
import {ContractsRegister} from "../../market/ContractsRegister.sol";
import {Governor} from "../../market/Governor.sol";
import {TreasurySplitter} from "../../market/TreasurySplitter.sol";

// Core contracts
import {BotListV3} from "@gearbox-protocol/core-v3/contracts/core/BotListV3.sol";
import {AliasedLossPolicyV3} from "@gearbox-protocol/core-v3/contracts/core/AliasedLossPolicyV3.sol";
import {GearStakingV3} from "@gearbox-protocol/core-v3/contracts/core/GearStakingV3.sol";
import {PoolV3} from "@gearbox-protocol/core-v3/contracts/pool/PoolV3.sol";
import {PoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/pool/PoolQuotaKeeperV3.sol";
import {DefaultAccountFactoryV3} from "@gearbox-protocol/core-v3/contracts/core/DefaultAccountFactoryV3.sol";
import {PriceOracleV3} from "@gearbox-protocol/core-v3/contracts/core/PriceOracleV3.sol";
import {LinearInterestRateModelV3} from "@gearbox-protocol/core-v3/contracts/pool/LinearInterestRateModelV3.sol";
import {TumblerV3} from "@gearbox-protocol/core-v3/contracts/pool/TumblerV3.sol";
import {GaugeV3} from "@gearbox-protocol/core-v3/contracts/pool/GaugeV3.sol";
import {CreditManagerV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditManagerV3.sol";
import {CreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditFacadeV3.sol";
import {CreditConfiguratorV3} from "@gearbox-protocol/core-v3/contracts/credit/CreditConfiguratorV3.sol";

import {ZeroPriceFeed} from "../../helpers/ZeroPriceFeed.sol";

import {VmSafe} from "forge-std/Vm.sol";

struct UploadableContract {
    bytes initCode;
    bytes32 contractType;
    uint256 version;
}

struct DeploySystemContractCall {
    bytes32 contractType;
    uint256 version;
    bool saveVersion;
}

// It deploys all the system contracts and related ones
contract GlobalSetup is Test, InstanceManagerHelper {
    UploadableContract[] internal contractsToUpload;

    constructor() {
        _setCoreContracts();
        _setInterestRateModels();
        _setLossPolicies();
        _setRateKeepers();
    }

    function _deployGlobalContracts(
        VmSafe.Wallet[] memory _initialSigners,
        VmSafe.Wallet memory _bytecodeAuthor,
        VmSafe.Wallet memory _auditor,
        string memory auditorName,
        uint8 _threshold,
        address _dao
    ) internal {
        _deployInstanceManager(_initialSigners, _threshold, _dao);

        CrossChainCall[] memory calls = new CrossChainCall[](1);
        calls[0] = _generateAddAuditorCall(_auditor.addr, auditorName);
        _submitBatchAndSign("Add auditor", calls);

        bytes32[8] memory publicDomains = [
            DOMAIN_ADAPTER,
            DOMAIN_BOT,
            DOMAIN_DEGEN_NFT,
            DOMAIN_IRM,
            DOMAIN_LOSS_POLICY,
            DOMAIN_PRICE_FEED,
            DOMAIN_RATE_KEEPER,
            DOMAIN_ZAPPER
        ];
        calls = new CrossChainCall[](publicDomains.length);
        for (uint256 i = 0; i < publicDomains.length; ++i) {
            calls[i] = _generateAddPublicDomainCall(publicDomains[i]);
        }
        _submitBatchAndSign("Add public domains", calls);

        uint256 len = contractsToUpload.length;
        calls = new CrossChainCall[](len);
        for (uint256 i = 0; i < len; ++i) {
            bytes32 bytecodeHash = _uploadByteCodeAndSign(
                _bytecodeAuthor,
                _auditor,
                contractsToUpload[i].initCode,
                contractsToUpload[i].contractType,
                contractsToUpload[i].version
            );

            bool isPublicContract = IBytecodeRepository(bytecodeRepository)
                .isPublicDomain(Domain.extractDomain(contractsToUpload[i].contractType));
            // NOTE: allowing public contracts doesn't require CCG permissions but it's convenient to execute in batch
            calls[i] = isPublicContract
                ? _generateAllowPublicContractCall(bytecodeHash)
                : _generateAllowSystemContractCall(bytecodeHash);
        }
        _submitBatchAndSign("Allow contracts", calls);

        DeploySystemContractCall[10] memory deployCalls = [
            DeploySystemContractCall({contractType: AP_BOT_LIST, version: 3_10, saveVersion: false}),
            DeploySystemContractCall({contractType: AP_GEAR_STAKING, version: 3_10, saveVersion: false}),
            DeploySystemContractCall({contractType: AP_PRICE_FEED_STORE, version: 3_10, saveVersion: false}),
            DeploySystemContractCall({contractType: AP_MARKET_CONFIGURATOR_FACTORY, version: 3_10, saveVersion: false}),
            DeploySystemContractCall({contractType: AP_POOL_FACTORY, version: 3_10, saveVersion: true}),
            DeploySystemContractCall({contractType: AP_CREDIT_FACTORY, version: 3_10, saveVersion: true}),
            DeploySystemContractCall({contractType: AP_PRICE_ORACLE_FACTORY, version: 3_10, saveVersion: true}),
            DeploySystemContractCall({contractType: AP_INTEREST_RATE_MODEL_FACTORY, version: 3_10, saveVersion: true}),
            DeploySystemContractCall({contractType: AP_RATE_KEEPER_FACTORY, version: 3_11, saveVersion: true}),
            DeploySystemContractCall({contractType: AP_LOSS_POLICY_FACTORY, version: 3_10, saveVersion: true})
        ];
        len = deployCalls.length;
        calls = new CrossChainCall[](len);
        for (uint256 i = 0; i < len; ++i) {
            calls[i] = _generateDeploySystemContractCall(
                deployCalls[i].contractType, deployCalls[i].version, deployCalls[i].saveVersion
            );
        }
        _submitBatchAndSign("Deploy system contracts", calls);
    }

    function _attachGlobalContracts(address[] memory _initialSigners, uint8 _threshold, address _dao) internal {
        _attachInstanceManager(_initialSigners, _threshold, _dao);
    }

    function _fundActors(address[] memory actors, uint256 amount) internal {
        for (uint256 i = 0; i < actors.length; ++i) {
            payable(actors[i]).transfer(amount);
        }
    }

    function _getFundsBack(VmSafe.Wallet[] memory wallets, address to) internal {
        for (uint256 i = 0; i < wallets.length; ++i) {
            _startPrankOrBroadcast(wallets[i].addr);
            payable(to).transfer(wallets[i].addr.balance);
            _stopPrankOrBroadcast();
        }
    }

    function _exportJson() internal {
        // Store address manager state as JSON
        string memory json = vm.serializeAddress("addresses", "instanceManager", address(instanceManager));
        json = vm.serializeAddress("addresses", "bytecodeRepository", address(bytecodeRepository));
        json = vm.serializeAddress("addresses", "multisig", address(multisig));
        json = vm.serializeAddress("addresses", "addressProvider", address(instanceManager.addressProvider()));

        vm.writeJson(json, "./addresses.json");
    }

    function _setCoreContracts() internal {
        contractsToUpload.push(
            UploadableContract({initCode: type(PoolFactory).creationCode, contractType: AP_POOL_FACTORY, version: 3_10})
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CreditFactory).creationCode, contractType: AP_CREDIT_FACTORY, version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(InterestRateModelFactory).creationCode,
                contractType: AP_INTEREST_RATE_MODEL_FACTORY,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(PriceFeedStore).creationCode, contractType: AP_PRICE_FEED_STORE, version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(PriceOracleFactory).creationCode, contractType: AP_PRICE_ORACLE_FACTORY, version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(RateKeeperFactory).creationCode, contractType: AP_RATE_KEEPER_FACTORY, version: 3_11
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(MarketConfiguratorFactory).creationCode,
                contractType: AP_MARKET_CONFIGURATOR_FACTORY,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({initCode: type(Governor).creationCode, contractType: AP_GOVERNOR, version: 3_10})
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(TreasurySplitter).creationCode, contractType: AP_TREASURY_SPLITTER, version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({initCode: type(PoolV3).creationCode, contractType: AP_POOL, version: 3_10})
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(PoolQuotaKeeperV3).creationCode, contractType: AP_POOL_QUOTA_KEEPER, version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({initCode: type(BotListV3).creationCode, contractType: AP_BOT_LIST, version: 3_10})
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(GearStakingV3).creationCode, contractType: AP_GEAR_STAKING, version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(DefaultAccountFactoryV3).creationCode,
                contractType: AP_ACCOUNT_FACTORY_DEFAULT,
                version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(PriceOracleV3).creationCode, contractType: AP_PRICE_ORACLE, version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(MarketConfigurator).creationCode, contractType: AP_MARKET_CONFIGURATOR, version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({initCode: type(ACL).creationCode, contractType: AP_ACL, version: 3_10})
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(ContractsRegister).creationCode, contractType: AP_CONTRACTS_REGISTER, version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(LossPolicyFactory).creationCode, contractType: AP_LOSS_POLICY_FACTORY, version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CreditManagerV3).creationCode, contractType: AP_CREDIT_MANAGER, version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CreditFacadeV3).creationCode, contractType: AP_CREDIT_FACADE, version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(CreditConfiguratorV3).creationCode, contractType: AP_CREDIT_CONFIGURATOR, version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(ZeroPriceFeed).creationCode, contractType: AP_ZERO_PRICE_FEED, version: 3_10
            })
        );
    }

    function _setInterestRateModels() internal {
        contractsToUpload.push(
            UploadableContract({
                initCode: type(LinearInterestRateModelV3).creationCode, contractType: "IRM::LINEAR", version: 3_10
            })
        );
    }

    function _setLossPolicies() internal {
        contractsToUpload.push(
            UploadableContract({
                initCode: type(AliasedLossPolicyV3).creationCode, contractType: "LOSS_POLICY::ALIASED", version: 3_10
            })
        );
    }

    function _setRateKeepers() internal {
        contractsToUpload.push(
            UploadableContract({
                initCode: type(GaugeV3).creationCode, contractType: "RATE_KEEPER::GAUGE", version: 3_10
            })
        );

        contractsToUpload.push(
            UploadableContract({
                initCode: type(TumblerV3).creationCode, contractType: "RATE_KEEPER::TUMBLER", version: 3_10
            })
        );
    }

    // function _setupPriceFeedStore() internal {
    //     // _addPriceFeed(CHAINLINK_ETH_USD, 1 days);
    //     // _addPriceFeed(CHAINLINK_USDC_USD, 1 days);

    //     // _allowPriceFeed(WETH, CHAINLINK_ETH_USD);
    //     // _allowPriceFeed(USDC, CHAINLINK_USDC_USD);
    // }
}
