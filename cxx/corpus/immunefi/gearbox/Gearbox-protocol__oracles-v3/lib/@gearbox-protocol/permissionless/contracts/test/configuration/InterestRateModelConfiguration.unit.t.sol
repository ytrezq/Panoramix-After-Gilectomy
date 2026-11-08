// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {ConfigurationTestHelper} from "./ConfigurationTestHelper.sol";
import {IContractsRegister} from "../../interfaces/IContractsRegister.sol";
import {DeployParams} from "../../interfaces/Types.sol";
import {MockIRM} from "../mocks/MockIRM.sol";
import {GeneralMock} from "@gearbox-protocol/core-v3/contracts/test/mocks/GeneralMock.sol";
import {CrossChainCall} from "../helpers/GlobalSetup.sol";

contract InterestRateModelConfigurationUnitTest is ConfigurationTestHelper {
    function setUp() public override {
        super.setUp();
    }

    /// REGULAR CONFIGURATION TESTS ///

    function test_IRM_01_configure() public {
        CrossChainCall[] memory calls = new CrossChainCall[](1);
        bytes32 bytecodeHash =
            _uploadByteCodeAndSign(bytecodeAuthor, auditor, type(MockIRM).creationCode, "IRM::MOCK", 3_10);
        calls[0] = _generateAllowPublicContractCall(bytecodeHash);
        _submitBatchAndSign("Allow public contracts", calls);

        vm.prank(admin);
        address newIRM = marketConfigurator.updateInterestRateModel(
            address(pool),
            DeployParams({postfix: "MOCK", salt: 0, constructorParams: abi.encode(address(pool), addressProvider)})
        );

        bytes memory arbitraryData = abi.encodeCall(MockIRM.setFlag, (true));

        vm.expectCall(newIRM, arbitraryData);

        vm.prank(admin);
        marketConfigurator.configureInterestRateModel(address(pool), arbitraryData);

        assertTrue(MockIRM(payable(newIRM)).flag(), "IRM flag must be true");
    }
}
