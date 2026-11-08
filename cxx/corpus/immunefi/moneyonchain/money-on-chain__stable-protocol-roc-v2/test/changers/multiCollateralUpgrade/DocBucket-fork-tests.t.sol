// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import { BaseFork } from "./helpers/BaseFork.sol";
import { MocQueueExecFees } from "moc-main-latest/contracts/queue/MocQueueExecFees.sol";
import { IPriceProvider } from "moc-main-latest/contracts/interfaces/IPriceProvider.sol";
import "forge-std/console.sol";

interface IGovernedRegistryView {
    function getAddress(bytes32 _key) external view returns (address);
    function addressArrayContains(bytes32 _key, address value) external view returns (bool);
    function getAddressArrayLength(bytes32 _key) external view returns (uint256);
}

interface IBufferBaseView {
    function getOutput(uint256 idx) external view returns (address, uint256, uint256, uint256);
    function getThreshold() external view returns (uint256);
    function liquidate() external;
    function flush(uint256 idx) external;
}

/// @title Fork Tests with Ignition Deployed Contracts
/// @notice Fork tests that use contracts deployed by Hardhat Ignition
contract DocBucketForkTests is BaseFork {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 private constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 private constant MOC_FLOW_REVERSE_AUCTIONS =
        0x0428ec087e0cce276a71d1caf1afe4da32a2d48b3ebe579040612b5bd262ff73;
    bytes32 private constant MOC_MULTI_COLLATERAL_GUARD = keccak256("moc.multi-collateral-guard");
    // MOC_FLOW_BUFFERS = keccak256(MOC_FLOW\1\BUFFERS)
    bytes32 private constant MOC_FLOW_BUFFERS = 0x4cb845794d5472a713e41e8e4ddc566dab8d695f1dc6c8edd43dad9d55112a22;

    function setUp() public override {
        super.setUp();
    }

    function test_RegistryIsUpdatedAfterChanger() public {
        IGovernedRegistryView registry = IGovernedRegistryView(address(changer.governedRegistry()));
        uint256 reverseAuctionsBefore = registry.getAddressArrayLength(MOC_FLOW_REVERSE_AUCTIONS);
        uint256 buffersBefore = registry.getAddressArrayLength(MOC_FLOW_BUFFERS);
        assertGt(reverseAuctionsBefore, 0, "Reverse auctions array should have entries before changer");
        assertGt(buffersBefore, 0, "Buffers array should have entries before changer");

        _executeChanger();
        uint256 reverseAuctionsAfter = registry.getAddressArrayLength(MOC_FLOW_REVERSE_AUCTIONS);
        uint256 buffersAfter = registry.getAddressArrayLength(MOC_FLOW_BUFFERS);

        assertEq(
            registry.getAddress(MOC_MULTI_COLLATERAL_GUARD),
            address(mocMultiCollateralGuard),
            "Registry guard should match deployed mocMultiCollateralGuard"
        );
        assertEq(reverseAuctionsAfter, reverseAuctionsBefore + 2, "Reverse auctions array length should increase by 2");
        assertTrue(
            registry.addressArrayContains(MOC_FLOW_REVERSE_AUCTIONS, address(reverseAuctionDocToMoc)),
            "Registry should contain DOC->MOC reverse auction"
        );
        assertTrue(
            registry.addressArrayContains(MOC_FLOW_REVERSE_AUCTIONS, address(reverseAuctionMocToDoc)),
            "Registry should contain MOC->DOC reverse auction"
        );
        assertEq(buffersAfter, buffersBefore + 1, "Buffers array length should increase by 1");
        assertTrue(
            registry.addressArrayContains(MOC_FLOW_BUFFERS, rocrRewardsBuffer),
            "Registry buffers should contain rocr rewards buffer"
        );
    }

    function test_SameTpsBothBuckets() public {
        _executeChanger();
        assertEq(address(rifBucket.tpTokens(0)), address(docBucket.tpTokens(0)), "Same TP added to both buckets");
        assertEq(rifBucket.getTpAmount(), docBucket.getTpAmount(), "Same TP amount added to both buckets");
    }

    function test_SameTpRolesBothBuckets() public {
        _executeChanger();

        assertEq(usdRifToken.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1, "1 Admin");
        assertEq(usdRifToken.getRoleMemberCount(MINTER_ROLE), 2, "2 Minters");
        assertEq(usdRifToken.getRoleMemberCount(BURNER_ROLE), 2, "2 Burners");

        assertTrue(usdRifToken.hasRole(DEFAULT_ADMIN_ROLE, address(rifBucket)), "rifBucket is the Admin");
        assertTrue(usdRifToken.hasRole(MINTER_ROLE, address(rifBucket)), "rifBucket is a Minter");
        assertTrue(usdRifToken.hasRole(BURNER_ROLE, address(rifBucket)), "rifBucket is a Burner");

        assertTrue(usdRifToken.hasRole(MINTER_ROLE, address(docBucket)), "docBucket is a Minter");
        assertTrue(usdRifToken.hasRole(BURNER_ROLE, address(docBucket)), "docBucket is a Burner");
    }

    function test_TCTokenRightRoles() public {
        _executeChanger();

        assertEq(docProToken.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1, "1 Admin");
        assertEq(docProToken.getRoleMemberCount(MINTER_ROLE), 1, "1 Minter");
        assertEq(docProToken.getRoleMemberCount(BURNER_ROLE), 1, "1 Burner");

        assertTrue(docProToken.hasRole(DEFAULT_ADMIN_ROLE, address(docBucket)), "Admin role only for DOC bucket");
        assertTrue(docProToken.hasRole(MINTER_ROLE, address(docBucket)), "docBucket is a Minter");
        assertTrue(docProToken.hasRole(BURNER_ROLE, address(docBucket)), "docBucket is a Burner");
    }

    function test_CombinedValuesSameRifBucket() public {
        _executeChanger();

        assertEq(
            rifBucket.getCglb(),
            mocMultiCollateralGuard.getCombinedCglb(),
            "Combined coverage same as RIF bucket"
        );
        assertEq(
            rifBucket.getCtargemaCA(),
            mocMultiCollateralGuard.getCombinedCtargemaCA(),
            "Combined ctargema same as RIF bucket"
        );
    }

    function test_CannotOperateDocBucketBeforeChanger() public {
        uint256 qTC = 1 ether;
        uint256 qTP = 1 ether;
        uint256 qACmax = 10 ether;

        uint256 execFee = _getExecCost(docQueue, MocQueueExecFees.OperType.mintTC);

        vm.startPrank(holder);

        vm.expectRevert(abi.encodeWithSignature("NotMocBucket()"));
        docBucket.mintTC{ value: execFee }(qTC, qACmax, holder, VENDOR);

        execFee = _getExecCost(docQueue, MocQueueExecFees.OperType.mintTP);
        vm.expectRevert(abi.encodeWithSignature("NotMocBucket()"));
        docBucket.mintTP{ value: execFee }(address(usdRifToken), qTP, qACmax, holder, VENDOR);

        deal(address(usdRifToken), holder, qTP);
        execFee = _getExecCost(docQueue, MocQueueExecFees.OperType.redeemTP);
        vm.expectRevert(abi.encodeWithSignature("NotMocBucket()"));
        docBucket.redeemTP{ value: execFee }(address(usdRifToken), qTP, 0, holder, VENDOR);

        deal(address(docProToken), holder, qTC);
        execFee = _getExecCost(docQueue, MocQueueExecFees.OperType.redeemTC);
        vm.expectRevert(abi.encodeWithSignature("NotMocBucket()"));
        docBucket.redeemTC{ value: execFee }(qTC, 0, holder, VENDOR);
    }

    function test_MintTCDocBucket() public {
        uint256 qTC = 1 ether;
        uint256 qACmax = 10 ether;

        _executeChanger();

        uint256 rifCglbBefore = rifBucket.getCglb();
        uint256 combinedCglbBefore = mocMultiCollateralGuard.getCombinedCglb();

        uint256 execFee = _getExecCost(docQueue, MocQueueExecFees.OperType.mintTC);
        vm.prank(holder);
        docBucket.mintTC{ value: execFee }(qTC, qACmax, holder, VENDOR);

        vm.roll(block.number + docQueue.minOperWaitingBlk());
        mocMultiCollateralGuard.execute();

        assertEq(docProToken.balanceOf(holder), qTC, "Holder received TC tokens");
        // Rif bucket coverage is not affected by DOC minting, so it should remain the same
        assertEq(rifBucket.getCglb(), rifCglbBefore, "RIF bucket coverage unchanged");
        // Combined coverage should also remain unchanged since DOC bucket is still empty of TP
        assertEq(mocMultiCollateralGuard.getCombinedCglb(), combinedCglbBefore, "Combined coverage unchanged");
    }

    function test_MintTPDocBucket() public {
        uint256 qTC = 2 ether;
        uint256 qTP = 1 ether;
        uint256 qACmax = 100 ether;

        _executeChanger();

        uint256 tpBalanceBefore = usdRifToken.balanceOf(holder);
        uint256 rifCglbBefore = rifBucket.getCglb();
        uint256 combinedCglbBefore = mocMultiCollateralGuard.getCombinedCglb();

        vm.startPrank(holder);

        // mint TC before to ensure DOC bucket has some collateral
        uint256 execFee = _getExecCost(docQueue, MocQueueExecFees.OperType.mintTC);
        docBucket.mintTC{ value: execFee }(qTC, qACmax, holder, VENDOR);

        execFee = _getExecCost(docQueue, MocQueueExecFees.OperType.mintTP);
        docBucket.mintTP{ value: execFee }(address(usdRifToken), qTP, qACmax, holder, VENDOR);

        vm.roll(block.number + docQueue.minOperWaitingBlk());
        mocMultiCollateralGuard.execute();

        assertEq(usdRifToken.balanceOf(holder), tpBalanceBefore + qTP, "Holder received TP tokens");
        // Rif bucket coverage should not be affected by DOC minting, so it should remain the same
        assertEq(rifBucket.getCglb(), rifCglbBefore, "RIF bucket coverage unchanged");
        assertLt(docBucket.getCglb(), rifBucket.getCglb(), "DOC bucket coverage should be less than RIF");
        // Combined coverage should decrease since DOC bucket now has TP collateral and less coverage than RIF bucket
        assertLt(mocMultiCollateralGuard.getCombinedCglb(), combinedCglbBefore, "Combined coverage decreased");
    }

    function test_RedeemTPDocBucket() public {
        // holder has some TP tokens from RIF bucket
        deal(address(usdRifToken), holder, 10 ether);

        _executeChanger();

        // mint TC and TP before to ensure DOC bucket has collateral
        _addTCandTP();
        vm.startPrank(holder);
        uint256 nTP = docBucket.getNTP(address(usdRifToken));

        // Try to redeem more TP than the DOC bucket has, should fail
        uint256 tpBalanceBefore = usdRifToken.balanceOf(holder);
        uint256 qTP = nTP + 2 ether; // redeem TPs holders has but DOC bucket doesn't have
        uint256 execFee = _getExecCost(docQueue, MocQueueExecFees.OperType.redeemTP);
        docBucket.redeemTP{ value: execFee }(address(usdRifToken), qTP, 0, holder, VENDOR);
        vm.roll(block.number + docQueue.minOperWaitingBlk());
        mocMultiCollateralGuard.execute();

        assertEq(usdRifToken.balanceOf(holder), tpBalanceBefore, "Holder did not receive TPs");

        // Now redeem the TP tokens
        qTP = nTP / 2; // redeem half of the TP tokens DOC bucket has, should succeed
        docBucket.redeemTP{ value: execFee }(address(usdRifToken), qTP, 0, holder, VENDOR);

        vm.roll(block.number + docQueue.minOperWaitingBlk());
        mocMultiCollateralGuard.execute();

        assertEq(usdRifToken.balanceOf(holder), tpBalanceBefore - qTP, "Holder redeemed TP tokens");
    }

    function test_FeeFlow() public {
        _executeChanger();

        // force price provider to return a valid price so that fees are charged and sent to fee flow
        IPriceProvider priceProvider = IPriceProvider(docBucket.feeTokenPriceProvider());
        (bytes32 price, ) = priceProvider.peek();
        bytes memory data = abi.encodeWithSelector(IPriceProvider.peek.selector);
        bytes memory forcedReturnData = abi.encode(price, true);
        vm.mockCall(address(priceProvider), data, forcedReturnData);

        uint256 pTCacBefore = docBucket.getPTCac();
        uint256 docFeeFlowBalanceBefore = docToken.balanceOf(address(feeFlow));
        uint256 mocFeeFlowBalanceBefore = mocToken.balanceOf(address(feeFlow));
        // mint TC and TP before to ensure DOC bucket has collateral
        _addTCandTP();

        // mint more tokens but using the mocToken to pay fees, which should be forwarded to fee flow
        vm.startPrank(holder);
        deal(address(mocToken), holder, 10000 ether);
        mocToken.approve(address(docBucket), 10000 ether);
        _addTCandTP();

        assertGt(docBucket.getPTCac(), pTCacBefore, "pTCac should increase because feeRetainer for DOC fees");

        uint256 docFeeFlowBalanceAfter = docToken.balanceOf(address(feeFlow));
        uint256 mocFeeFlowBalanceAfter = mocToken.balanceOf(address(feeFlow));

        assertGt(docFeeFlowBalanceAfter, docFeeFlowBalanceBefore, "Fee flow received fees from DOC bucket operations");
        assertGt(mocFeeFlowBalanceAfter, mocFeeFlowBalanceBefore, "Fee flow received fees from MOC bucket operations");

        // trigger split and check that the configured recipients receive the funds
        address acTokenRecipient1 = feeFlow.acTokenAddressRecipient1();
        address acTokenRecipient2 = feeFlow.acTokenAddressRecipient2();
        uint256 acTokenRecipient1BalanceBefore = docToken.balanceOf(acTokenRecipient1);
        uint256 reverseAuctionDocToMocBalanceBefore = docToken.balanceOf(address(reverseAuctionDocToMoc));
        uint256 acTokenRecipient2BalanceBefore = docToken.balanceOf(acTokenRecipient2);
        address feeTokenRecipient1 = feeFlow.feeTokenAddressRecipient1();
        address feeTokenRecipient2 = feeFlow.feeTokenAddressRecipient2();
        uint256 feeTokenRecipient1BalanceBefore = mocToken.balanceOf(feeTokenRecipient1);
        uint256 feeTokenRecipient2BalanceBefore = mocToken.balanceOf(feeTokenRecipient2);
        assertEq(feeTokenRecipient2, rocrRewardsBuffer, "Fee token recipient 2 should be rocrRewardsBuffer");

        feeFlow.split();

        assertEq(docToken.balanceOf(address(feeFlow)), 0, "Fee flow balance should be 0 after split");
        assertEq(mocToken.balanceOf(address(feeFlow)), 0, "Fee flow balance should be 0 after split");

        assertGt(
            docToken.balanceOf(acTokenRecipient1),
            acTokenRecipient1BalanceBefore,
            "AC token recipient 1 (foundation) received DOC tokens"
        );
        assertGt(
            docToken.balanceOf(address(reverseAuctionDocToMoc)),
            reverseAuctionDocToMocBalanceBefore,
            "Reverse auction DOC to MOC received DOC tokens"
        );
        assertGt(
            docToken.balanceOf(acTokenRecipient2),
            acTokenRecipient2BalanceBefore,
            "AC token recipient 2 (reverse auction) received DOC tokens"
        );
        assertGt(
            mocToken.balanceOf(feeTokenRecipient1),
            feeTokenRecipient1BalanceBefore,
            "Fee token recipient 1 received MOC tokens"
        );
        assertGt(
            mocToken.balanceOf(feeTokenRecipient2),
            feeTokenRecipient2BalanceBefore,
            "Fee token recipient 2 received MOC tokens"
        );

        // Split rocrRewardsBuffer and verify both outputs receive MOC
        IBufferBaseView rocrBuffer = IBufferBaseView(rocrRewardsBuffer);
        (address mocRewardsBufferFromBuffer, , , ) = rocrBuffer.getOutput(0);
        (address reverseAuctionMocToDocOutput, , , ) = rocrBuffer.getOutput(1);
        uint256 mocRewardsBufferBalanceBefore = mocToken.balanceOf(mocRewardsBufferFromBuffer);
        uint256 reverseAuctionMocToDocBalanceBefore = mocToken.balanceOf(reverseAuctionMocToDocOutput);

        // Ensure buffer is above liquidate/flush thresholds for deterministic execution in fork tests
        (, , , uint256 output0Threshold) = rocrBuffer.getOutput(0);
        (, , , uint256 output1Threshold) = rocrBuffer.getOutput(1);
        uint256 targetBufferBalance = rocrBuffer.getThreshold();
        uint256 minForFlush = (output0Threshold + output1Threshold) + 1;
        if (minForFlush > targetBufferBalance) targetBufferBalance = minForFlush;

        uint256 bufferBalance = mocToken.balanceOf(rocrRewardsBuffer);
        if (bufferBalance <= targetBufferBalance) {
            deal(address(mocToken), rocrRewardsBuffer, targetBufferBalance + 1000 ether);
        }

        rocrBuffer.liquidate();
        rocrBuffer.flush(0);
        rocrBuffer.flush(1);

        assertGt(
            mocToken.balanceOf(mocRewardsBufferFromBuffer),
            mocRewardsBufferBalanceBefore,
            "rocrRewardsBuffer output 0 received MOC tokens"
        );
        assertGt(
            mocToken.balanceOf(reverseAuctionMocToDocOutput),
            reverseAuctionMocToDocBalanceBefore,
            "rocrRewardsBuffer output 1 (reverseAuctionMOCtoDOC) received MOC tokens"
        );

        // trigger the reverse auction to ensure it can execute with the received DOC
        address docToMocOutputAccount = reverseAuctionDocToMoc.outputAccount();
        assertEq(
            docToMocOutputAccount,
            mocRewardsBufferFromBuffer,
            "DOC->MOC reverse auction output account should be mocRewardsBuffer"
        );
        uint256 outputAccountBalanceBefore = mocToken.balanceOf(docToMocOutputAccount);
        reverseAuctionDocToMoc.triggerOrders();

        assertEq(
            docToken.balanceOf(address(reverseAuctionDocToMoc)),
            0,
            "Reverse auction DOC to MOC balance should be 0 after triggering orders"
        );

        assertGt(
            mocToken.balanceOf(docToMocOutputAccount),
            outputAccountBalanceBefore,
            "mocRewardsBuffer received MOC tokens"
        );

        // Execute MOC->DOC reverse auction and verify DOC bucket receives DOC
        uint256 docBucketDocBalanceBefore = docToken.balanceOf(address(docBucket));
        uint256 reverseAuctionMocToDocBalanceBeforeTrigger = mocToken.balanceOf(address(reverseAuctionMocToDoc));
        reverseAuctionMocToDoc.triggerOrders();

        assertLt(
            mocToken.balanceOf(address(reverseAuctionMocToDoc)),
            reverseAuctionMocToDocBalanceBeforeTrigger,
            "Reverse auction MOC to DOC balance should decrease after triggering orders"
        );
        assertGt(
            docToken.balanceOf(address(docBucket)),
            docBucketDocBalanceBefore,
            "DocBucket received DOC tokens from reverse auction MOC to DOC"
        );

        uint256 nACcbBeforeRefresh = docBucket.nACcb();
        docBucket.refreshACBalance();
        assertGt(docBucket.nACcb(), nACcbBeforeRefresh, "DocBucket nACcb should increase after refreshACBalance");
    }

    function test_MicroLiquidation() public {
        _executeChanger();

        // mint TC and TP before to ensure DOC bucket has collateral
        _addTCandTP();

        // RIF price goes down
        uint256 newPrice = 0.0065 ether;
        bytes memory data = abi.encodeWithSelector(IPriceProvider.peek.selector);
        bytes memory forcedReturnData = abi.encode(newPrice, true);
        vm.mockCall(address(rifPriceProvider), data, forcedReturnData);

        uint256 rifCglb = rifBucket.getCglb();
        uint256 docCglb = docBucket.getCglb();

        uint256 rifBalanceBefore = rifToken.balanceOf(address(rifBucket));
        uint256 docBalanceBefore = docToken.balanceOf(address(docBucket));

        // MicroLiquidation is available
        assertTrue(
            mocMultiCollateralGuard.isMicroLiquidationAvailable(rifBucket),
            "Micro liquidation should be available"
        );
        // Execute MicroLiquidation
        mocMultiCollateralGuard.execMicroLiquidation(rifBucket);

        assertGt(rifBucket.getCglb(), rifCglb, "RIF bucket coverage should increase after micro liquidation");
        assertGt(docBucket.getCglb(), docCglb, "DOC bucket coverage should increase after micro liquidation");

        assertLt(
            rifToken.balanceOf(address(rifBucket)),
            rifBalanceBefore,
            "RIF bucket should have less RIF after micro liquidation"
        );
        assertGt(
            docToken.balanceOf(address(docBucket)),
            docBalanceBefore,
            "DOC bucket should have more DOC after micro liquidation"
        );
    }

    function test_Liquidation() public {
        _executeChanger();

        // mint TC and TP before to ensure DOC bucket has collateral
        _addTCandTP();

        // RIF price goes down
        uint256 newPrice = 0.003 ether;
        bytes memory data = abi.encodeWithSelector(IPriceProvider.peek.selector);
        bytes memory forcedReturnData = abi.encode(newPrice, true);
        vm.mockCall(address(rifPriceProvider), data, forcedReturnData);

        // Force to true because liqEnabled flag is false
        vm.mockCall(address(rifBucket), abi.encodeWithSignature("liqEnabled()"), abi.encode(true));

        uint256 rifCglb = rifBucket.getCglb();
        uint256 docCglb = docBucket.getCglb();

        uint256 rifBalanceBefore = rifToken.balanceOf(address(rifBucket));
        uint256 docBalanceBefore = docToken.balanceOf(address(docBucket));

        // Liquidation is available
        assertTrue(mocMultiCollateralGuard.isLiquidationAvailable(rifBucket), "Liquidation should be available");
        // Execute Liquidation
        mocMultiCollateralGuard.execLiquidation(rifBucket);

        // liquidationExecCost introduces a small degree in the coverage, so we check that it remains almost the same
        assertApproxEqAbs(
            rifBucket.getCglb(),
            rifCglb,
            100000,
            "RIF bucket coverage should remain almost the same after liquidation"
        );
        assertGt(docBucket.getCglb(), docCglb, "DOC bucket coverage should increase after liquidation");

        assertLt(
            rifToken.balanceOf(address(rifBucket)),
            rifBalanceBefore,
            "RIF bucket should have less RIF after liquidation"
        );
        assertGt(
            docToken.balanceOf(address(docBucket)),
            docBalanceBefore,
            "DOC bucket should have more DOC after liquidation"
        );
    }

    function _addTCandTP() internal {
        uint256 qTC = 200 ether;
        uint256 qTP = 100 ether;
        uint256 qACmax = 1000 ether;

        vm.startPrank(holder);

        uint256 execFee = _getExecCost(docQueue, MocQueueExecFees.OperType.mintTC);
        docBucket.mintTC{ value: execFee }(qTC, qACmax, holder, VENDOR);

        execFee = _getExecCost(docQueue, MocQueueExecFees.OperType.mintTP);
        docBucket.mintTP{ value: execFee }(address(usdRifToken), qTP, qACmax, holder, VENDOR);

        vm.roll(block.number + docQueue.minOperWaitingBlk());
        mocMultiCollateralGuard.execute();

        vm.stopPrank();
    }
}
