// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {Utils} from "../lib/Utils.sol";
import {DeployerCommon} from "./DeployerCommon.sol";

abstract contract VyperDeployer is DeployerCommon {
    /// @notice Deploy smart contract
    /// @param _fileName The smart contract file name with an extension: `Counter.vy`
    /// @return deployedAddress An address of the deployed smart contract
    function _deploy(string memory _fileName, bytes memory _args) internal returns (address deployedAddress) {
        deployedAddress = _deploy(_contractBaseDir(), _deploymentsSubDir(), _fileName, _args);
    }

    /// @notice Deploy smart contract
    /// @param _folder The smart contract allocation folder
    /// @param _subDir The directory for the ABI allocation
    /// @param _fileName The smart contract file name with an extension: `Counter.vy`
    /// @return deployedAddress An address of the deployed smart contract
    function _deploy(string memory _folder, string memory _subDir, string memory _fileName, bytes memory _args)
        internal
        returns (address deployedAddress)
    {
        string memory path = string(abi.encodePacked(_folder, "/", _fileName));

        string memory bytecode;
        string memory deployedByteCode;
        string memory contractABI;
        string memory compilerVersion;

        (deployedAddress, bytecode, deployedByteCode, contractABI, compilerVersion) = _deployContract(path, _args);

        string memory empty;

        _deployments.push(
            Deployment({
                name: _fileName,
                fileName: _fileName,
                deploymentsSubDir: _subDir,
                addr: deployedAddress,
                bytecode: bytecode,
                deployedByteCode: deployedByteCode,
                contractABI: contractABI,
                compilerVersion: compilerVersion,
                forgeOutDir: empty,
                synced: false,
                deployedAtBlock: 0
            })
        );

        return deployedAddress;
    }

    ///@notice Compiles a Vyper contract with constructor arguments
    /// and returns the address that the contract was deployed to
    ///@notice If deployment fails, an error will be thrown
    ///@param _filePath - The file name of the Vyper contract.
    /// For example, the file name for "SimpleStore.vy" is "SimpleStore"
    ///@param _args - The constructor arguments
    ///@return deployedAddress - The address that the contract was deployed to
    ///@return bytecode - The bytecode of the deployed contract
    ///@return deployedByteCode - The deployed bytecode of the deployed contract
    ///@return contractABI - The ABI of the deployed contract
    ///@return compliverVersion - Vyper compiler version
    function _deployContract(string memory _filePath, bytes memory _args)
        internal
        returns (
            address deployedAddress,
            string memory bytecode,
            string memory deployedByteCode,
            string memory contractABI,
            string memory compliverVersion
        )
    {
        // create a list of strings with the commands necessary to compile Vyper contracts
        string[] memory cmds = new string[](2);
        cmds[0] = "vyper";
        cmds[1] = _filePath;

        // compile the Vyper contract and return the bytecode
        bytes memory _bytecode = vm.ffi(cmds);

        // add `_args` to the deployment bytecode
        _bytecode = abi.encodePacked(_bytecode, _args);

        assembly {
            // solhint-disable-line no-inline-assembly
            // deploy the bytecode with the `create` instruction
            deployedAddress := create(0, add(_bytecode, 0x20), mload(_bytecode))
        }

        if (deployedAddress == address(0)) revert("FailedToDeploy");

        bytecode = vm.toString(_bytecode);
        deployedByteCode = vm.toString(Utils.getCodeAt(address(deployedAddress)));

        // get smart contract ABI
        string[] memory getABICdms = new string[](4);
        getABICdms[0] = "vyper";
        getABICdms[1] = "-f";
        getABICdms[2] = "abi";
        getABICdms[3] = _filePath;

        contractABI = string(vm.ffi(getABICdms));

        // get compile version
        cmds[1] = "--version";

        compliverVersion = string(vm.ffi(cmds));
    }
}
