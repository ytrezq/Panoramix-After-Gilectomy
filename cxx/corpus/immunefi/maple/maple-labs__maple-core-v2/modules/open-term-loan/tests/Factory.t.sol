// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test }  from "../modules/forge-std/src/Test.sol";
import { Proxy } from "../modules/maple-proxy-factory/modules/proxy-factory/contracts/Proxy.sol";

import { MapleLoan }            from "../contracts/MapleLoan.sol";
import { MapleLoanFactory }     from "../contracts/MapleLoanFactory.sol";
import { MapleLoanInitializer } from "../contracts/MapleLoanInitializer.sol";

import { MockFactory, MockGlobals, MockLender } from "./utils/Mocks.sol";

contract FactoryTests is Test {

    address borrower;
    address fundsAsset;
    address governor;
    address implementation;
    address initializer;
    address poolManager;

    MapleLoanFactory factory;
    MockFactory      lenderFactory;
    MockGlobals      globals;
    MockLender       lender;

    function setUp() external {
        borrower       = makeAddr("borrower");
        fundsAsset     = makeAddr("fundsAsset");
        globals        = new MockGlobals();
        governor       = makeAddr("governor");
        implementation = address(new MapleLoan());
        initializer    = address(new MapleLoanInitializer());
        lender         = new MockLender();
        lenderFactory  = new MockFactory();
        poolManager    = makeAddr("poolManager");

        globals.__setGovernor(governor);
        globals.__setIsBorrower(borrower, true);
        globals.__setIsPoolAsset(fundsAsset, true);
        globals.__setIsInstanceOf("OT_LOAN_MANAGER_FACTORY", address(lenderFactory), true);

        lender.__setFactory(address(lenderFactory));
        lender.__setPoolManager(poolManager);
        lender.__setFundsAsset(fundsAsset);

        lenderFactory.__setGlobals(address(globals));
        lenderFactory.__setIsInstance(address(lender), true);

        factory = new MapleLoanFactory(address(globals));

        vm.startPrank(governor);
        factory.registerImplementation(1, implementation, initializer);
        factory.setDefaultVersion(1);
        vm.stopPrank();
    }

    function test_createInstance_cannotDeploy(bytes32 salt_) external {
        bytes memory arguments = MapleLoanInitializer(initializer).encodeArguments(
            borrower,
            address(lender),
            fundsAsset,
            1,
            [uint32(1), 1, 1],
            [uint64(1), 1, 1, 1]
        );

        vm.expectRevert("LF:CI:CANNOT_DEPLOY");
        factory.createInstance(arguments, salt_);
    }

    function test_createInstance(bytes32 salt_) external {
        globals.__setCanDeploy(true);

        bytes memory arguments = MapleLoanInitializer(initializer).encodeArguments(
            borrower,
            address(lender),
            fundsAsset,
            1,
            [uint32(1), 1, 1],
            [uint64(1), 1, 1, 1]
        );

        address loan = factory.createInstance(arguments, salt_);

        address expectedAddress = address(uint160(uint256(keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(factory),
                keccak256(abi.encodePacked(arguments, salt_)),
                keccak256(abi.encodePacked(type(Proxy).creationCode, abi.encode(address(factory), address(0))))
            )
        ))));

        // TODO: Change back to hardcoded address once IPFS hashes can be removed on compilation in Foundry.
        assertEq(loan, expectedAddress);

        assertEq(MapleLoan(loan).implementation(), implementation);

        assertTrue(!factory.isLoan(address(1)));
        assertTrue( factory.isLoan(loan));

        assertEq(MapleLoan(loan).HUNDRED_PERCENT(), 1e6);
    }

}
