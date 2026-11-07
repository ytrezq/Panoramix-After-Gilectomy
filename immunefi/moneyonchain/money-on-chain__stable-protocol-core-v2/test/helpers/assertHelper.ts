import { expect } from "chai";
import { pEth } from "./utils";

export function assertPrec(
  expected: string | number | BigInt | bigint,
  actual: string | number | BigInt | bigint,
  message?: string,
  tolerance = 0,
) {
  if (typeof expected === "string" || typeof expected === "number") {
    expected = pEth(expected);
  }
  if (typeof actual === "string" || typeof actual === "number") {
    actual = pEth(actual);
  }
  expect(expected, message).to.be.closeTo(actual, tolerance);
}
