import { getNamedAccounts, ethers } from "hardhat";
import { Address } from "hardhat-deploy/types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { ContractTransactionResponse } from "ethers";
import { expect } from "chai";
import {
  CONSTANTS,
  ERRORS,
  ethersGetBalance,
  ethersSendValue,
  pEth,
  resetFork,
  timedDescribe,
} from "../../helpers/utils";
import {
  ERC20,
  ERC20__factory,
  GovernorMock,
  MocReverseAuction,
  MocSwapperV3,
  MocSwapperV3__factory,
  MocSwapperV3MultiHop,
  MocSwapperV3MultiHop__factory,
} from "../../../typechain";
import { assertPrec } from "../../helpers/assertHelper";
const helpers = require("@nomicfoundation/hardhat-network-helpers");

timedDescribe("Feature: MocReverseAuction - rsk fork", function () {
  let governorMock: GovernorMock;
  let deployer: Address;
  let mocSwapperV3: MocSwapperV3;
  let mocSwapperV3MultiHop: MocSwapperV3MultiHop;
  let mocReverseAuctionMocToRbtc: MocReverseAuction;
  let mocReverseAuctionRbtcToMoc: MocReverseAuction;
  let mocReverseAuctionMocToRif: MocReverseAuction;
  let mocReverseAuctionRifToMoc: MocReverseAuction;
  let mocToken: ERC20;
  let rifToken: ERC20;
  const orderThreshold = pEth(2);
  const slippage = 0;
  const outputAccount = "0x0000000000000000000000000000000000000111";
  const holderAddress = "0xb151984e9d1911EBd3e0a32cEFd1F55023C1b30c"; // https://explorer.rootstock.io/address/0xb151984e9d1911EBd3e0a32cEFd1F55023C1b30c
  const WRBTC = "0x542fDA317318eBF1d3DEAf76E0b632741A7e677d"; // https://explorer.rootstock.io/address/0x542fda317318ebf1d3deaf76e0b632741a7e677d
  const MOC = "0x9AC7fE28967B30E3A4e6e03286d715b42B453D10"; // https://explorer.rootstock.io/address/0x9AC7fE28967B30E3A4e6e03286d715b42B453D10
  const RIF = "0x2AcC95758f8b5F583470ba265EB685a8F45fC9D5"; // https://explorer.rootstock.io/address/0x2AcC95758f8b5F583470ba265EB685a8F45fC9D5
  const swapRouterV2 = "0x0B14ff67f0014046b4b99057Aec4509640b3947A"; // https://explorer.rootstock.io/address/0x0B14ff67f0014046b4b99057Aec4509640b3947A
  const fee = 3000;
  const RBTC = CONSTANTS.ZERO_ADDRESS;

  describe("GIVEN MocReverseAuction deployed for MOC/RBTC and MOC/RIF", () => {
    async function baseSetup() {
      // use mainnet fork
      await resetFork(process.env["RSK_MAINNET_RPC"] || "https://public-node.rsk.co", 7637100);
      await helpers.impersonateAccount(holderAddress);
      const holderSigner = await ethers.getSigner(holderAddress);
      mocToken = ERC20__factory.connect(MOC, holderSigner);
      rifToken = ERC20__factory.connect(RIF, holderSigner);

      ({ deployer } = await getNamedAccounts());
      const signer = await ethers.getSigner(deployer);

      const dataProviderMockFactory = await ethers.getContractFactory("DataProviderMock");
      const providerSwappingMOCtoRBTC = (await dataProviderMockFactory.deploy(pEth(1))).target.toString();
      const providerSwappingRBTCtoMOC = (await dataProviderMockFactory.deploy(pEth(1))).target.toString();
      const providerSwappingMOCtoRIF = (await dataProviderMockFactory.deploy(pEth(10))).target.toString();
      const providerSwappingRIFtoMOC = (await dataProviderMockFactory.deploy(pEth(1))).target.toString();

      const priceProviderMockFactory = await ethers.getContractFactory("PriceProviderMock");
      const priceProvider = (await priceProviderMockFactory.deploy(0)).target.toString();

      // deploy governorMock
      const governorMockFactory = await ethers.getContractFactory("GovernorMock");
      governorMock = await governorMockFactory.deploy();

      // deploy MocSwapperV3
      const erc1967ProxyFactory = await ethers.getContractFactory("ERC1967Proxy");
      const mocSwapperV3Factory = await ethers.getContractFactory("MocSwapperV3");
      const mocSwapperV3Impl = await mocSwapperV3Factory.deploy();
      let erc1967Proxy = await erc1967ProxyFactory.deploy(mocSwapperV3Impl.target, "0x");
      mocSwapperV3 = MocSwapperV3__factory.connect(erc1967Proxy.target.toString(), signer);
      await mocSwapperV3.initialize(governorMock.target, governorMock.target /*pauser*/, swapRouterV2, WRBTC);
      // set path MocSwapperV3 for RBTC -> MOC
      await mocSwapperV3.setPool(RBTC, MOC, fee, providerSwappingRBTCtoMOC);
      await mocSwapperV3.setPool(MOC, RBTC, fee, providerSwappingMOCtoRBTC);

      // deploy MocSwapperV3MultiHop
      const mocSwapperV3MultiHopFactory = await ethers.getContractFactory("MocSwapperV3MultiHop");
      const mocSwapperV3MultiHopImpl = await mocSwapperV3MultiHopFactory.deploy();
      erc1967Proxy = await erc1967ProxyFactory.deploy(mocSwapperV3MultiHopImpl.target, "0x");
      mocSwapperV3MultiHop = MocSwapperV3MultiHop__factory.connect(erc1967Proxy.target.toString(), signer);
      await mocSwapperV3MultiHop.initialize(governorMock.target, governorMock.target /*pauser*/, swapRouterV2, WRBTC);
      // set path MocSwapperV3MultiHop for MOC -> RIF
      await mocSwapperV3MultiHop.setPath(RIF, MOC, [WRBTC], [fee, fee], providerSwappingRIFtoMOC);
      await mocSwapperV3MultiHop.setPath(MOC, RIF, [WRBTC], [fee, fee], providerSwappingMOCtoRIF);

      const mocReverseAuctionFactory = await ethers.getContractFactory("MocReverseAuction");
      // deploy MocReverseAuction MOC -> RBTC
      mocReverseAuctionMocToRbtc = await mocReverseAuctionFactory.deploy(
        governorMock.target,
        mocSwapperV3.target,
        MOC,
        RBTC,
        outputAccount,
        orderThreshold,
        priceProvider,
        slippage,
      );
      // deploy MocReverseAuction RBTC -> MOC
      mocReverseAuctionRbtcToMoc = await mocReverseAuctionFactory.deploy(
        governorMock.target,
        mocSwapperV3.target,
        RBTC,
        MOC,
        outputAccount,
        orderThreshold,
        priceProvider,
        slippage,
      );
      // deploy MocReverseAuction MOC -> RIF
      mocReverseAuctionMocToRif = await mocReverseAuctionFactory.deploy(
        governorMock.target,
        mocSwapperV3MultiHop.target,
        MOC,
        RIF,
        outputAccount,
        orderThreshold,
        priceProvider,
        slippage,
      );
      // deploy MocReverseAuction RIF -> MOC
      mocReverseAuctionRifToMoc = await mocReverseAuctionFactory.deploy(
        governorMock.target,
        mocSwapperV3MultiHop.target,
        RIF,
        MOC,
        outputAccount,
        orderThreshold,
        priceProvider,
        slippage,
      );
    }

    describe("AND MocReverseAuction MOC to RBTC has 10 MOCs", () => {
      describe("WHEN trigger is executed", async () => {
        let tx: ContractTransactionResponse;
        before(async () => {
          await loadFixture(baseSetup);
          await mocToken.transfer(mocReverseAuctionMocToRbtc.target, pEth(10));
          expect(await mocReverseAuctionMocToRbtc.readyToTriggerOrders()).to.be.equal(true);
          tx = await mocReverseAuctionMocToRbtc.triggerOrders();
        });
        it("THEN MocReverseAuction MOC balance decrease by 1", async () => {
          assertPrec(await mocToken.balanceOf(mocReverseAuctionMocToRbtc.target), 9);
        });
        it("THEN readyToTriggerOrders is still true", async () => {
          expect(await mocReverseAuctionMocToRbtc.readyToTriggerOrders()).to.be.equal(true);
        });
        describe("WHEN orderThreshold is set to 10 MOC", () => {
          before(async () => {
            await mocReverseAuctionMocToRbtc.setOrderThreshold(pEth(10));
          });
          it("THEN readyToTriggerOrders is false", async () => {
            expect(await mocReverseAuctionMocToRbtc.readyToTriggerOrders()).to.be.equal(false);
          });
        });
        it("THEN outputAccount RBTC balance increase by 0.00000078", async () => {
          assertPrec(await ethersGetBalance(outputAccount), "0.000000787570796534");
        });
        it("THEN Triggered event is emitted", async () => {
          await expect(tx)
            .to.emit(mocReverseAuctionMocToRbtc, "Triggered")
            .withArgs(MOC, RBTC, pEth(1), pEth("0.000000787570796534"), outputAccount);
        });
        describe("WHEN emergency withdraw is called", async () => {
          before(async function () {
            tx = await mocReverseAuctionMocToRbtc.emergencyWithdraw(MOC, outputAccount);
          });
          it("THEN the MocReverseAuction sends all MOCs to the outputAccount", async () => {
            assertPrec(await mocToken.balanceOf(outputAccount), 9);
            assertPrec(await mocToken.balanceOf(mocReverseAuctionMocToRbtc.target), 0);
          });
          it("THEN an EmergencyWithdraw event is emitted", async () => {
            await expect(tx)
              .to.emit(mocReverseAuctionMocToRbtc, "EmergencyWithdraw")
              .withArgs(MOC, outputAccount, pEth(9));
          });
        });
        describe("WHEN coinbase is sent to the MocReverseAuction", () => {
          it("THEN tx reverts because it cannot accept coinbase", async () => {
            await expect(
              ethersSendValue(holderAddress, mocReverseAuctionMocToRbtc.target.toString(), 1n),
            ).to.be.revertedWithCustomError(mocReverseAuctionMocToRbtc, "NotCoinbase");
          });
        });
      });
    });
    describe("AND MocReverseAuction RBTC to MOC has 1 RBTC", () => {
      describe("WHEN trigger is executed", async () => {
        let tx: ContractTransactionResponse;
        before(async () => {
          await loadFixture(baseSetup);
          await ethersSendValue(holderAddress, mocReverseAuctionRbtcToMoc.target.toString(), pEth(1));
          // even with readyToTriggerOrders returning false, triggerOrders can still be called
          expect(await mocReverseAuctionRbtcToMoc.readyToTriggerOrders()).to.be.equal(false);
          tx = await mocReverseAuctionRbtcToMoc.triggerOrders();
        });
        it("THEN MocReverseAuction RBTC balance decrease by 1", async () => {
          assertPrec(await ethersGetBalance(mocReverseAuctionRbtcToMoc.target.toString()), 0);
        });
        it("THEN readyToTriggerOrders is false", async () => {
          expect(await mocReverseAuctionRbtcToMoc.readyToTriggerOrders()).to.be.equal(false);
        });
        it("THEN outputAccount MOC balance increase by 486401.18", async () => {
          assertPrec(await mocToken.balanceOf(outputAccount), "486401.184163885048820734");
        });
        it("THEN Triggered event is emitted", async () => {
          await expect(tx)
            .to.emit(mocReverseAuctionRbtcToMoc, "Triggered")
            .withArgs(RBTC, MOC, pEth(1), pEth("486401.184163885048820734"), outputAccount);
        });
      });
    });
    describe("AND MocReverseAuction MOC to RIF has 1 MOC", () => {
      describe("WHEN trigger is executed", async () => {
        let tx: ContractTransactionResponse;
        before(async () => {
          await loadFixture(baseSetup);
          await mocToken.transfer(mocReverseAuctionMocToRif.target, pEth(1));
          tx = await mocReverseAuctionMocToRif.triggerOrders();
        });
        it("THEN MocReverseAuction MOC balance decrease by 1", async () => {
          assertPrec(await mocToken.balanceOf(mocReverseAuctionMocToRif.target), 0);
        });
        it("THEN outputAccount RIF balance increase by 1.61", async () => {
          assertPrec(await rifToken.balanceOf(outputAccount), "1.611060345820710450");
        });
        it("THEN Triggered event is emitted", async () => {
          await expect(tx)
            .to.emit(mocReverseAuctionMocToRif, "Triggered")
            .withArgs(MOC, RIF, pEth(1), pEth("1.611060345820710450"), outputAccount);
        });
      });
    });
    describe("AND MocReverseAuction RIF to MOC has 10 RIFs", () => {
      describe("WHEN trigger is executed", async () => {
        let tx: ContractTransactionResponse;
        before(async () => {
          await loadFixture(baseSetup);
          await rifToken.transfer(mocReverseAuctionRifToMoc.target, pEth(10));
          tx = await mocReverseAuctionRifToMoc.triggerOrders();
        });
        it("THEN MocReverseAuction RIF balance decrease by 1", async () => {
          assertPrec(await rifToken.balanceOf(mocReverseAuctionRifToMoc.target), 9);
        });
        it("THEN outputAccount MOC balance increase by 0.61", async () => {
          assertPrec(await mocToken.balanceOf(outputAccount), "0.613290352354496729");
        });
        it("THEN Triggered event is emitted", async () => {
          await expect(tx)
            .to.emit(mocReverseAuctionRifToMoc, "Triggered")
            .withArgs(RIF, MOC, pEth(1), pEth("0.613290352354496729"), outputAccount);
        });
      });
    });
    describe("WHEN governor does not authorize changes", function () {
      let expectRevertNotAuthorized: (it: any) => any;
      before(async function () {
        await governorMock.setIsAuthorized(false);
        expectRevertNotAuthorized = it =>
          expect(it).to.be.revertedWithCustomError(mocReverseAuctionMocToRbtc, ERRORS.NOT_AUTH_CHANGER);
      });
      it("THEN emergencyWithdraw fails", async function () {
        await expectRevertNotAuthorized(mocReverseAuctionMocToRbtc.emergencyWithdraw(MOC, outputAccount));
      });
      it("THEN setTokenIn fails", async function () {
        await expectRevertNotAuthorized(mocReverseAuctionMocToRbtc.setTokenIn(MOC));
      });
      it("THEN set setTokenOut fails", async function () {
        await expectRevertNotAuthorized(mocReverseAuctionMocToRbtc.setTokenOut(MOC));
      });
      it("THEN setMocSwapper fails", async function () {
        await expectRevertNotAuthorized(mocReverseAuctionMocToRbtc.setMocSwapper(MOC));
      });
      it("THEN setOutputAccount fails", async function () {
        await expectRevertNotAuthorized(mocReverseAuctionMocToRbtc.setOutputAccount(MOC));
      });
      it("THEN setOrderThreshold fails", async function () {
        await expectRevertNotAuthorized(mocReverseAuctionMocToRbtc.setOrderThreshold(pEth(1)));
      });
      it("THEN setPriceProvider fails", async function () {
        await expectRevertNotAuthorized(mocReverseAuctionMocToRbtc.setPriceProvider(MOC));
      });
      it("THEN setSlippage fails", async function () {
        await expectRevertNotAuthorized(mocReverseAuctionMocToRbtc.setSlippage(1));
      });
    });
    describe("WHEN governor authorizes changes", function () {
      before(async function () {
        await governorMock.setIsAuthorized(true);
      });
      it("THEN setTokenIn succeeds", async function () {
        await mocReverseAuctionMocToRbtc.setTokenIn(RIF);
        expect(await mocReverseAuctionMocToRbtc.tokenIn()).to.be.equal(RIF);
      });
      it("THEN set setTokenOut succeeds", async function () {
        await mocReverseAuctionMocToRbtc.setTokenOut(MOC);
        expect(await mocReverseAuctionMocToRbtc.tokenOut()).to.be.equal(MOC);
      });
      it("THEN setMocSwapper succeeds", async function () {
        await mocReverseAuctionMocToRbtc.setMocSwapper(MOC);
        expect(await mocReverseAuctionMocToRbtc.mocSwapper()).to.be.equal(MOC);
      });
      it("THEN setOutputAccount succeeds", async function () {
        await mocReverseAuctionMocToRbtc.setOutputAccount(MOC);
        expect(await mocReverseAuctionMocToRbtc.outputAccount()).to.be.equal(MOC);
      });
      it("THEN setOrderThreshold succeeds", async function () {
        await mocReverseAuctionMocToRbtc.setOrderThreshold(pEth(1));
        expect(await mocReverseAuctionMocToRbtc.orderThreshold()).to.be.equal(pEth(1));
      });
      it("THEN setPriceProvider succeeds", async function () {
        await mocReverseAuctionMocToRbtc.setPriceProvider(MOC);
        expect(await mocReverseAuctionMocToRbtc.priceProvider()).to.be.equal(MOC);
      });
      it("THEN setSlippage succeeds", async function () {
        await mocReverseAuctionMocToRbtc.setSlippage(pEth("0.05"));
        expect(await mocReverseAuctionMocToRbtc.slippage()).to.be.equal(pEth("0.05"));
      });
    });
    after(async () => {
      await resetFork();
    });
  });
});
