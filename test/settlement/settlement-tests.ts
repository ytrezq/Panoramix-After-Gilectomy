import { expect } from "chai";
import { MocCARC20 } from "../../typechain";
import { fixtureDeployedMocRC20 } from "../rc20/fixture";
import { ERRORS, timedDescribe, time } from "../helpers/utils";

const getTimeToNextSettlement = async (mocImpl: MocCARC20) => {
  const now = BigInt(await time.latest());
  const nextSettlement = await mocImpl.nextSettlementTime();
  return nextSettlement < now ? 0 : nextSettlement - now;
};

timedDescribe("Feature: Moc Settlement time triggering", () => {
  let mocImpl: MocCARC20;
  before(async () => {
    const fixtureDeploy = fixtureDeployedMocRC20(2, undefined);
    ({ mocImpl } = await fixtureDeploy());
  });

  describe("GIVEN a MocCARC20 implementation deployed", () => {
    describe("WHEN settlement is executed before next time to settlement", () => {
      it("THEN tx reverts because time to settlement has not passed", async () => {
        await expect(mocImpl.execSettlement()).to.be.revertedWithCustomError(
          mocImpl,
          ERRORS.MISSING_TIME_TO_SETTLEMENT,
        );
      });
    });

    describe("AND time to next settlement has passed", () => {
      before(async () => {
        await time.increaseTo(await mocImpl.nextSettlementTime());
      });
      it("THEN time remaining to next settlement is 0", async () => {
        expect(await getTimeToNextSettlement(mocImpl)).to.be.equals(0);
      });
      describe("WHEN settlement is executed", () => {
        before(async () => {
          await mocImpl.execSettlement();
        });
        it("THEN time remaining for next settlement is equal to time between settlements", async () => {
          expect(await getTimeToNextSettlement(mocImpl)).to.be.equals(await mocImpl.settlementTimeSpan());
        });
        describe("AND settlement is executed again", () => {
          it("THEN tx reverts because time to settlement has not passed", async () => {
            await expect(mocImpl.execSettlement()).to.be.revertedWithCustomError(
              mocImpl,
              ERRORS.MISSING_TIME_TO_SETTLEMENT,
            );
          });
        });
      });
    });
  });
});
