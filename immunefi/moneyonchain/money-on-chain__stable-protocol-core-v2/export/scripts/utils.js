"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.deployCARC20With = exports.deployCARC20 = exports.addPeggedTokens = exports.addMissingPriceProviders = exports.getNetworkDeployParams = exports.deployVendors = exports.getGovernorAddresses = exports.deployMultiCollateralGuard = exports.deployQueue = exports.deployCollateralToken = exports.deployUUPSArtifact = exports.waitForTxConfirmation = exports.noVendor = exports.BURNER_ROLE = exports.MINTER_ROLE = exports.DEFAULT_ADMIN_ROLE = exports.CONSTANTS = void 0;
const hardhat_1 = require("hardhat");
exports.CONSTANTS = {
    ZERO_ADDRESS: hardhat_1.ethers.ZeroAddress,
    MAX_UINT256: hardhat_1.ethers.MaxUint256,
    MAX_BALANCE: hardhat_1.ethers.MaxUint256 / BigInt(1e17),
    PRECISION: BigInt(1e18),
    ONE: BigInt(1e18),
    SWAP_FEE: 3000n,
};
exports.DEFAULT_ADMIN_ROLE = hardhat_1.ethers.ZeroHash;
exports.MINTER_ROLE = hardhat_1.ethers.keccak256(hardhat_1.ethers.toUtf8Bytes("MINTER_ROLE"));
exports.BURNER_ROLE = hardhat_1.ethers.keccak256(hardhat_1.ethers.toUtf8Bytes("BURNER_ROLE"));
exports.noVendor = exports.CONSTANTS.ZERO_ADDRESS;
const waitForTxConfirmation = async (tx, confirmations = 1) => {
    return (await tx).wait(confirmations);
};
exports.waitForTxConfirmation = waitForTxConfirmation;
const deployUUPSArtifact = async ({ hre, artifactBaseName, contract, initializeArgs, }) => {
    const { deployments: { deploy }, getNamedAccounts, } = hre;
    const { deployer } = await getNamedAccounts();
    const gasLimit = (0, exports.getNetworkDeployParams)(hre).gasLimit;
    artifactBaseName = artifactBaseName || contract;
    let execute;
    if (initializeArgs) {
        execute = {
            init: {
                methodName: "initialize",
                args: initializeArgs,
            },
        };
    }
    const deployResult = await deploy(`${artifactBaseName}Proxy`, {
        contract,
        from: deployer,
        proxy: {
            proxyContract: "ERC1967Proxy",
            proxyArgs: ["{implementation}", "{data}"],
            execute,
        },
        gasLimit,
    });
    console.log(`${contract}, as ${artifactBaseName} implementation deployed at ${deployResult.implementation}`);
    console.log(`${artifactBaseName}Proxy ERC1967Proxy deployed at ${deployResult.address}`);
    return deployResult;
};
exports.deployUUPSArtifact = deployUUPSArtifact;
const deployCollateralToken = (artifactBaseName) => async (hre) => {
    const { ctParams } = (0, exports.getNetworkDeployParams)(hre);
    const { governorAddress } = await (0, exports.getGovernorAddresses)(hre);
    const { deployer } = await hre.getNamedAccounts();
    await (0, exports.deployUUPSArtifact)({
        hre,
        artifactBaseName,
        contract: "MocRC20",
        initializeArgs: [
            ctParams.name,
            ctParams.symbol,
            deployer, // proper Moc roles are gonna be assigned after it's deployed
            governorAddress,
        ],
    });
    return hre.network.live; // prevents re execution on live networks
};
exports.deployCollateralToken = deployCollateralToken;
const deployQueue = async (hre, artifactBaseName, mocMultiCollateralGuard) => {
    const { queueParams, mocAddresses } = (0, exports.getNetworkDeployParams)(hre);
    // use interimGovernor to add the bucket on the deployment
    const { interimGovernor } = await (0, exports.getGovernorAddresses)(hre);
    console.log("[WARNING] Using InterimGovernor for MocQueue:", interimGovernor);
    let mocQueueContract = "MocQueue";
    if (hre.network.tags.testing) {
        console.log("[ONLY TESTING] Using MocQueueBasefeeMock for ", artifactBaseName);
        mocQueueContract = "MocQueueBasefeeMock";
    }
    return (0, exports.deployUUPSArtifact)({
        hre,
        artifactBaseName,
        contract: mocQueueContract,
        initializeArgs: [
            interimGovernor,
            mocAddresses.pauserAddress,
            mocMultiCollateralGuard,
            queueParams.minOperWaitingBlk,
            queueParams.maxOperWaitingBlk,
            queueParams.execCostParams,
        ],
    });
};
exports.deployQueue = deployQueue;
const deployMultiCollateralGuard = (artifactBaseName) => async (hre) => {
    const { multiCollateralParams, mocAddresses } = (0, exports.getNetworkDeployParams)(hre);
    // use interimGovernor to add the bucket on the deployment
    const { interimGovernor } = await (0, exports.getGovernorAddresses)(hre);
    console.log("[WARNING] Using InterimGovernor for MocMultiCollateralGuard:", interimGovernor);
    await (0, exports.deployUUPSArtifact)({
        hre,
        artifactBaseName,
        contract: "MocMultiCollateralGuard",
        initializeArgs: [
            interimGovernor,
            mocAddresses.pauserAddress,
            multiCollateralParams.microLiquidationExecCost,
            multiCollateralParams.liquidationExecCost,
            multiCollateralParams.coinbaseExecFeeRecipient,
            multiCollateralParams.maxOperPerBatch,
            multiCollateralParams.useMaxLastPublicationBlock,
        ],
    });
    return hre.network.live; // prevents re execution on live networks
};
exports.deployMultiCollateralGuard = deployMultiCollateralGuard;
const getGovernorAddresses = async (hre) => {
    let { mocAddresses: { governorAddress }, gasLimit, } = (0, exports.getNetworkDeployParams)(hre);
    const { deployments: { deploy }, getNamedAccounts, } = hre;
    const { deployer } = await getNamedAccounts();
    if (!governorAddress && !hre.network.tags.testing)
        throw new Error("Governor address param is required for non testing environments.");
    // We need a governor for intermediate protected actions if a real governor was provided
    // after all the setups will be changed to it
    // InterimGovernor can be re-use by all solutions, so it's deployed using "deploy"
    const interimGovernor = (await deploy("InterimGovernor", {
        contract: "InterimGovernor",
        from: deployer,
        gasLimit,
    })).address;
    if (!governorAddress) {
        // GovernorMock can be re-use by all solutions, so it's deployed using "deploy"
        const governorMock = (await deploy("GovernorMock", {
            contract: "GovernorMock",
            from: deployer,
            gasLimit,
        })).address;
        console.log("[ONLY TESTING] Using GovernorMock:", governorMock);
        governorAddress = governorMock;
    }
    return { governorAddress, interimGovernor };
};
exports.getGovernorAddresses = getGovernorAddresses;
const deployVendors = (artifactBaseName) => async (hre) => {
    let { mocAddresses: { pauserAddress, vendorsGuardianAddress }, vendorsParams: { maxMarkup }, } = (0, exports.getNetworkDeployParams)(hre);
    const { governorAddress } = await (0, exports.getGovernorAddresses)(hre);
    await (0, exports.deployUUPSArtifact)({
        hre,
        artifactBaseName,
        contract: "MocVendors",
        initializeArgs: [vendorsGuardianAddress, governorAddress, pauserAddress, maxMarkup],
    });
    return hre.network.live; // prevents re execution on live networks
};
exports.deployVendors = deployVendors;
const getNetworkDeployParams = (hre) => {
    return hre.config.networks[hre.network.name].deployParameters;
};
exports.getNetworkDeployParams = getNetworkDeployParams;
const addMissingPriceProviders = async ({ hre, tpParams, gasLimit, }) => {
    const { deployments: { deploy }, getNamedAccounts, } = hre;
    const { deployer } = await getNamedAccounts();
    for (let tpParam of tpParams) {
        if (!tpParam.priceProviderAddress) {
            const tpPriceProvider = await deploy("PriceProviderMock", {
                from: deployer,
                args: [hardhat_1.ethers.parseEther("1")],
                gasLimit,
            });
            tpParam.priceProviderAddress = tpPriceProvider.address;
            console.log(`Deploying Fake PriceProvider for ${tpParam.name} at ${tpPriceProvider.address}`);
        }
    }
};
exports.addMissingPriceProviders = addMissingPriceProviders;
const addPeggedTokens = async (hre, governorAddress, mocCore, tpParams) => {
    const gasLimit = (0, exports.getNetworkDeployParams)(hre).gasLimit;
    if (tpParams) {
        const { deployments } = hre;
        const [signer] = await hardhat_1.ethers.getSigners();
        for (let i = 0; i < tpParams.tpParams.length; i++) {
            const tpArtifact = tpParams.tpParams[i].artifact || "MocRC20";
            await (0, exports.deployUUPSArtifact)({ hre, artifactBaseName: tpParams.tpParams[i].name, contract: tpArtifact });
            const mocRC20TP = await deployments.getOrNull(tpParams.tpParams[i].name + "Proxy");
            if (!mocRC20TP)
                throw new Error(`No ${tpParams.tpParams[i].name} deployed`);
            const mocRC20Proxy = await hardhat_1.ethers.getContractAt("MocRC20", mocRC20TP.address, signer);
            console.log(`Initializing ${tpParams.tpParams[i].name} PeggedToken...`);
            await (0, exports.waitForTxConfirmation)(mocRC20Proxy.initialize(tpParams.tpParams[i].name, tpParams.tpParams[i].symbol, mocCore.address, governorAddress, {
                gasLimit,
            }));
            await (0, exports.addMissingPriceProviders)({ hre, tpParams: tpParams.tpParams, gasLimit });
            console.log(`Adding ${tpParams.tpParams[i].name} as PeggedToken ${i}...`);
            await (0, exports.waitForTxConfirmation)(mocCore.addPeggedToken({
                tpTokenAddress: mocRC20Proxy.target.toString(),
                ...tpParams[i],
            }, {
                gasLimit,
            }));
        }
    }
};
exports.addPeggedTokens = addPeggedTokens;
const deployCARC20 = async (hre, mocCARC20Variant, ctVariant, extraInitParams = {}) => {
    const { deployments, getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    const signer = await hardhat_1.ethers.getSigner(deployer);
    const defaultDeployParams = (0, exports.getNetworkDeployParams)(hre);
    const { tpParams, liquidationParams, gasLimit } = defaultDeployParams;
    const { governorAddress } = await (0, exports.getGovernorAddresses)(hre);
    const deployedTCContract = await deployments.getOrNull(ctVariant + "Proxy");
    if (!deployedTCContract)
        throw new Error(`No ${ctVariant} deployed.`);
    const collateralToken = await hardhat_1.ethers.getContractAt("MocRC20", deployedTCContract.address, signer);
    const deployedMocQueue = await deployments.getOrNull("MocQueueCARC20Proxy");
    if (!deployedMocQueue)
        throw new Error("No MocQueue deployed.");
    const deployedMocMultiCollateralGuard = await deployments.getOrNull("MocMultiCollateralGuardCARC20Proxy");
    if (!deployedMocMultiCollateralGuard)
        throw new Error("No MocMultiCollateralGuard deployed.");
    const mocCARC20 = await (0, exports.deployCARC20With)(hre, mocCARC20Variant, extraInitParams, defaultDeployParams, await collateralToken.getAddress(), deployedMocQueue.address);
    console.log("Delegating CT roles to Moc", mocCARC20.address);
    // Assign TC Roles, and renounce deployer ADMIN
    await (0, exports.waitForTxConfirmation)(collateralToken.transferAllRoles(mocCARC20.address));
    console.log("initialization completed!");
    // Governor is mocked, and we can:
    // - add pegged tokens
    // - register the bucket on the queue
    // - register the bucket on the multicollateralGuard
    const mocCore = await hardhat_1.ethers.getContractAt("MocCARC20", mocCARC20.address, signer);
    if (tpParams) {
        await (0, exports.addMissingPriceProviders)({ hre, tpParams: tpParams.tpParams, gasLimit });
        await (0, exports.addPeggedTokens)(hre, governorAddress, mocCore, tpParams);
        console.log(`[ATTENTION] Changing governor for MocCore. Governor address: ${governorAddress}`);
        await (0, exports.waitForTxConfirmation)(mocCore.changeGovernor(governorAddress));
    }
    const mocQueue = await hardhat_1.ethers.getContractAt("MocQueue", deployedMocQueue.address, signer);
    console.log(`Registering MocRC20 bucket as enqueuer: ${mocCARC20.address}`);
    await (0, exports.waitForTxConfirmation)(mocQueue.registerBucket(mocCARC20.address));
    const mocMultiCollateralGuard = await hardhat_1.ethers.getContractAt("MocMultiCollateralGuard", deployedMocMultiCollateralGuard.address, signer);
    let acCoinbasePriceProviderAddress = liquidationParams.acCoinbasePriceProviderAddress;
    // for tests we deploy a AC coinbase and max AC to swap mocked providers
    if (hre.network.tags.testing) {
        const deploy = async (artifact, contract, args) => {
            const deployedArtifact = await deployments.deploy(artifact, {
                contract,
                from: deployer,
                gasLimit,
                args,
            });
            console.log(`[ONLY TESTING] ${artifact} deployed to: ${deployedArtifact.address}`);
            return deployedArtifact.address;
        };
        acCoinbasePriceProviderAddress = await deploy("ACCoinbasePriceProviderMock", "PriceProviderMock", [
            hardhat_1.ethers.parseEther("1"),
        ]);
    }
    await (0, exports.waitForTxConfirmation)(mocMultiCollateralGuard.addBucket(mocCARC20.address, {
        acCoinbasePriceProvider: acCoinbasePriceProviderAddress,
        rebalanceExecFeeRecipient: hardhat_1.ethers.Wallet.createRandom(),
        rtcThrld: liquidationParams.rtcThrld,
        microLiquidationThrld: liquidationParams.microLiquidationThrld,
        penaltyRate: liquidationParams.penaltyRate,
    }, []));
    console.log(`[ATTENTION] Changing governor for MocQueue and MocMultiCollateralGuard. Governor address: ${governorAddress}`);
    await (0, exports.waitForTxConfirmation)(mocQueue.changeGovernor(governorAddress));
    await (0, exports.waitForTxConfirmation)(mocMultiCollateralGuard.changeGovernor(governorAddress));
};
exports.deployCARC20 = deployCARC20;
const deployCARC20With = async (hre, mocCARC20Variant, extraInitParams = {}, deployParameters, tcTokenAddress, mocQueueAddress) => {
    const { deployments, getNamedAccounts } = hre;
    const { deployer, pauser } = await getNamedAccounts();
    const { coreParams, settlementParams, feeParams, mocAddresses, tpParams, gasLimit } = deployParameters;
    const deployedMocExpansionContract = await deployments.getOrNull("MocCARC20Expansion");
    if (!deployedMocExpansionContract)
        throw new Error("No MocCARC20Expansion deployed.");
    const deployedMocVendors = await deployments.getOrNull("MocVendorsCARC20Proxy");
    if (!deployedMocVendors)
        throw new Error("No MocVendors deployed.");
    let { collateralAssetAddress, pauserAddress, feeTokenAddress, feeTokenPriceProviderAddress, mocFeeFlowAddress, mocAppreciationBeneficiaryAddress, tcInterestCollectorAddress, maxAbsoluteOpProviderAddress, maxOpDiffProviderAddress, } = mocAddresses;
    // for tests we deploy a Collateral Asset mock, a FeeToken mock and its price provider
    if (hre.network.tags.testing) {
        const deploy = async (artifact, contract, args) => {
            const deployedArtifact = await deployments.deploy(artifact, {
                contract,
                from: deployer,
                gasLimit,
                args,
            });
            console.log(`[ONLY TESTING] ${artifact} deployed to: ${deployedArtifact.address}`);
            return deployedArtifact.address;
        };
        // use deployments.deploy to get contract in fixture using deployments.getOrNull
        collateralAssetAddress = collateralAssetAddress || (await deploy("CollateralAssetCARC20", "ERC20Mock"));
        feeTokenAddress = await deploy("FeeTokenMock", "ERC20Mock");
        feeTokenPriceProviderAddress = await deploy("FeeTokenPriceProviderMock", "PriceProviderMock", [
            hardhat_1.ethers.parseEther("1"),
        ]);
        maxAbsoluteOpProviderAddress = await deploy("MaxAbsoluteOpProviderMock", "DataProviderMock", [
            exports.CONSTANTS.MAX_UINT256,
        ]);
        maxOpDiffProviderAddress = await deploy("MaxOpDiffProviderMock", "DataProviderMock", [exports.CONSTANTS.MAX_UINT256]);
        console.log(`[ONLY TESTING] Using Pauser: ${pauser}`);
        // While testing, we use deployer as pauser
        pauserAddress = pauser;
    }
    const { governorAddress, interimGovernor } = await (0, exports.getGovernorAddresses)(hre);
    const initializeArgs = [
        {
            initializeCoreParams: {
                initializeBaseBucketParams: {
                    mocQueueAddress,
                    feeTokenAddress,
                    feeTokenPriceProviderAddress,
                    tcTokenAddress,
                    mocFeeFlowAddress,
                    mocAppreciationBeneficiaryAddress,
                    protThrld: coreParams.protThrld,
                    liqThrld: coreParams.liqThrld,
                    operationsFeeParams: {
                        feeRetainer: feeParams.feeRetainer,
                        tcMintFee: feeParams.tcMintFee,
                        tcRedeemFee: feeParams.tcRedeemFee,
                        swapTPforTPFee: feeParams.swapTPforTPFee,
                        swapTPforTCFee: feeParams.swapTPforTCFee,
                        swapTCforTPFee: feeParams.swapTCforTPFee,
                        redeemTCandTPFee: feeParams.redeemTCandTPFee,
                        mintTCandTPFee: feeParams.mintTCandTPFee,
                        feeTokenPct: feeParams.feeTokenPct,
                    },
                    successFee: coreParams.successFee,
                    appreciationFactor: coreParams.appreciationFactor,
                    settlementTimeSpan: settlementParams.settlementTimeSpan,
                    tcInterestCollectorAddress,
                    tcInterestRate: coreParams.tcInterestRate,
                    tcInterestPaymentTimeSpan: coreParams.tcInterestPaymentTimeSpan,
                    maxAbsoluteOpProviderAddress,
                    maxOpDiffProviderAddress,
                    decayTimeSpan: coreParams.decayTimeSpan,
                    allowDifferentRecipient: coreParams.allowDifferentRecipient,
                },
                governorAddress: tpParams ? interimGovernor : governorAddress, // use interimGovernor to add TPs
                pauserAddress,
                mocCoreExpansion: deployedMocExpansionContract.address,
                emaCalculationTimeSpan: coreParams.emaCalculationTimeSpan,
                mocVendors: deployedMocVendors.address,
            },
            acTokenAddress: collateralAssetAddress,
            ...extraInitParams,
        },
    ];
    const mocCARC20 = (0, exports.deployUUPSArtifact)({
        hre,
        artifactBaseName: mocCARC20Variant,
        contract: "MocCARC20",
        initializeArgs,
    });
    return mocCARC20;
};
exports.deployCARC20With = deployCARC20With;
//# sourceMappingURL=utils.js.map