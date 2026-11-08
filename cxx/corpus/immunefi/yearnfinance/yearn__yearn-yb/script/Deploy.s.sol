// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";
import { Locker } from "src/Locker.sol";
import { Operator } from "src/Operator.sol";
import { YToken } from "src/YToken.sol";
import { Protocol, YB, YBS, CreateX } from "src/utils/Constants.sol";
import { SafeHelper } from "script/utils/SafeHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { IYBSRegistry } from "src/interfaces/ybs/IYBSRegistry.sol";

contract Deploy is Script, SafeHelper, CreateXHelper, TenderlyHelper {

    Locker locker;
    Operator operator;
    YToken yToken;
    address nftHelper;

    function run() public isBatch(Protocol.OWNER) {
        deployMode = DeployMode.FORK;
        maxGasPerBatch = 15_000_000;

        // 1. Deploy Locker
        locker = Locker(payable(deployLocker()));

        // 2. Deploy Operator
        operator = Operator(payable(deployOperator()));

        // 3. Deploy Token
        yToken = YToken(deployYToken());

        // 4. Set Operator
        _setOperator();

        nftHelper = deployNFTHelper();


        console.log("--- Protocol deployed ---");
        console.log("locker", address(locker));
        console.log("operator", address(operator));
        console.log("yToken", address(yToken));
        console.log("nftHelper", address(nftHelper));

        // (address ybs, address distributor, address utils) = deployYBS();
        // console.log("--- YBS deployed ---");
        // console.log("ybs", ybs);
        // console.log("distributor", distributor);
        // console.log("utils", utils);

        if (deployMode == DeployMode.PRODUCTION) executeBatch(true, 0);
    }

    function _setOperator() public {
        addToBatch(
            address(locker),
                abi.encodeWithSelector(Locker.setOperator.selector, address(operator))
        );
    }

    function deployLocker() public returns (address) {
        bytes32 salt = CreateX.SALT_LOCKER;
        bytes memory constructorArgs = abi.encode(
            Protocol.OWNER,
            YB.TOKEN,
            YB.VEYB
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("Locker.sol:Locker"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address deployedAddress = computeCreate3AddressFromSaltPreimage(salt, Protocol.OWNER, true, false);
        require(deployedAddress.code.length > 0, "deployment failed");
        return deployedAddress;
    }

    function deployOperator() public returns (address) {
        bytes32 salt = CreateX.SALT_OPERATOR;
        bytes memory constructorArgs = abi.encode(
            Protocol.LOCKER,
            YB.GAUGE_CONTROLLER,
            YB.DAO_VOTING,
            Protocol.YTOKEN
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("Operator.sol:Operator"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address deployedAddress = computeCreate3AddressFromSaltPreimage(salt, Protocol.OWNER, true, false);
        require(deployedAddress.code.length > 0, "deployment failed");
        return deployedAddress;
    }

    function deployYToken() public returns (address) {
        bytes32 salt = CreateX.SALT_YTOKEN;
        bytes memory constructorArgs = abi.encode(
            Protocol.LOCKER,
            YB.TOKEN,
            "Yearn YB Token",
            "yYB"
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("YToken.sol:YToken"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address deployedAddress = computeCreate3AddressFromSaltPreimage(salt, Protocol.OWNER, true, false);
        require(deployedAddress.code.length > 0, "deployment failed");
        return deployedAddress;
    }

    function deployYBS() public returns (address ybs, address distributor, address utils) {
        bytes memory result = addToBatch(
            address(YBS.REGISTRY),
            abi.encodeWithSelector(IYBSRegistry.createNewDeployment.selector,
                YBS.STAKE_TOKEN,
                4, // max_stake_growth_weeks
                0, // start_time
                YBS.REWARD_TOKEN
            )
        );
        (ybs, distributor, utils) = abi.decode(result, (address, address, address));
    }

    function deployNFTHelper() public returns (address) {
        bytes32 salt = CreateX.SALT_NFTHelper;
        bytes memory constructorArgs = abi.encode(
            YB.GAUGE_CONTROLLER,
            YB.VEYB
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("NFTHelper.sol:NFTHelper"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address deployedAddress = computeCreate3AddressFromSaltPreimage(salt, Protocol.OWNER, true, false);
        require(deployedAddress.code.length > 0, "deployment failed");
        return deployedAddress;
    }
}