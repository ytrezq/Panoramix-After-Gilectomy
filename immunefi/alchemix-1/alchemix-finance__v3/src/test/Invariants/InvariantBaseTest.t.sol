// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../InvariantsTest.t.sol";

contract InvariantBaseTest is InvariantsTest {
    address internal immutable USER;

    uint256 internal immutable MAX_TEST_VALUE = 1e28;
    
    uint256 public maxTokenIdMinted;
    bytes32 internal constant POS_MINT_SIG = keccak256("AlchemistV3PositionNFTMinted(address,uint256)");

    constructor() {
        USER = makeAddr("User");
    }

    function setUp() public virtual override {
        selectors.push(this.depositCollateral.selector);
        selectors.push(this.withdrawCollateral.selector);
        selectors.push(this.borrowCollateral.selector);
        selectors.push(this.repayDebt.selector);
        selectors.push(this.repayDebtViaBurn.selector);
        selectors.push(this.transmuterStake.selector);
        selectors.push(this.transmuterClaim.selector);
        selectors.push(this.mine.selector);

        super.setUp();
    }

    function _targetSenders() internal virtual override {
        _targetSender(makeAddr("Sender1"));
        _targetSender(makeAddr("Sender2"));
        _targetSender(makeAddr("Sender3"));
        _targetSender(makeAddr("Sender4"));
        _targetSender(makeAddr("Sender5"));
        _targetSender(makeAddr("Sender6"));
        _targetSender(makeAddr("Sender7"));
        _targetSender(makeAddr("Sender8"));
    }

    function _updateMaxTokenIdFromLogs() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            // Event is emitted by the Alchemist contract (NOT the NFT contract).
            if (logs[i].emitter != address(alchemist)) continue;
            if (logs[i].topics.length != 3) continue;
            if (logs[i].topics[0] != POS_MINT_SIG) continue;

            // topics[2] is the indexed tokenId
            uint256 tokenId = uint256(logs[i].topics[2]);
            if (tokenId > maxTokenIdMinted) maxTokenIdMinted = tokenId;
        }
    }

    function _deposit(uint256 tokenId, uint256 amount, address onBehalf) internal logCall(onBehalf, "deposit") {
        vm.recordLogs();
        deal(mockVaultCollateral, onBehalf, amount);
        vm.startPrank(onBehalf);
        IERC20(mockVaultCollateral).approve(address(vault), amount * 2);
        vault.mint(amount, onBehalf);

        alchemist.deposit(amount, onBehalf, tokenId);
        vm.stopPrank();

        _updateMaxTokenIdFromLogs();

        _checkDebtInvariant("deposit");
    }

    function _borrow(uint256 tokenId, uint256 amount, address onBehalf) internal logCall(onBehalf, "borrow") {
        vm.prank(onBehalf);
        alchemist.mint(tokenId, amount, onBehalf);
        _checkDebtInvariant("borrow");
    }

    function _withdraw(uint256 tokenId, uint256 amount, address onBehalf) internal logCall(onBehalf, "withdraw") {
        vm.prank(onBehalf);
        alchemist.withdraw(amount, onBehalf, tokenId);
        _checkDebtInvariant("withdraw");
    }

    function _repay(uint256 tokenId, uint256 amount, address onBehalf) internal logCall(onBehalf, "repay") {
        vm.roll(block.number + 1);
        deal(mockVaultCollateral, onBehalf, amount * 2);
        vm.startPrank(onBehalf);
        IERC20(mockVaultCollateral).approve(address(vault), amount);
        vault.mint(amount, onBehalf);

        alchemist.repay(amount, tokenId);
        vm.stopPrank();
        _checkDebtInvariant("repay");
    }

    function _burn(uint256 tokenId, uint256 amount, address onBehalf) internal logCall(onBehalf, "burn") {
        vm.prank(onBehalf);
        alchemist.burn(amount, tokenId);
        _checkDebtInvariant("burn");
    }

    function _stake(uint256 amount, address onBehalf) internal logCall(onBehalf, "stake") {
        vm.startPrank(onBehalf);
        alToken.mint(onBehalf, amount);
        alToken.approve(address(transmuterLogic), amount);
        transmuterLogic.createRedemption(amount, onBehalf);
        vm.stopPrank();
        _checkDebtInvariant("stake");
    }

    function _claim(uint256 tokenId, address onBehalf) internal logCall(onBehalf, "claim") {
        vm.roll(block.number + (1000000));
        vm.startPrank(onBehalf);
        _logDebts("BEFORE_CLAIM");
        transmuterLogic.claimRedemption(tokenId);
        _logDebts("AFTER_CLAIM");
        vm.stopPrank();
        _checkDebtInvariant("claim");
    }

    /* HANDLERS */

    function depositCollateral(uint256 amount, uint256 onBehalfSeed) external {
        address onBehalf = _randomDepositor(targetSenders(), onBehalfSeed);
        if (onBehalf == address(0)) return;

        amount = bound(amount, 0, MAX_TEST_VALUE);
        if (amount == 0) return;

        uint256 tokenId;

        try AlchemistNFTHelper.getFirstTokenId(onBehalf, address(alchemistNFT)) {
            tokenId = AlchemistNFTHelper.getFirstTokenId(onBehalf, address(alchemistNFT));
        } catch {
            tokenId = 0;
        }

        _deposit(tokenId, amount, onBehalf);
    }

    function withdrawCollateral(uint256 amount, uint256 onBehalfSeed) external {
        address onBehalf = _randomWithdrawer(targetSenders(), onBehalfSeed);
        if (onBehalf == address(0)) return;

        uint256 tokenId = AlchemistNFTHelper.getFirstTokenId(onBehalf, address(alchemistNFT));

        (uint256 collat, uint256 debt,) = alchemist.getCDP(tokenId);
        uint256 debtToCollateral = alchemist.convertDebtTokensToYield(debt);
        uint256 maxWithdraw = alchemist.getMaxWithdrawable(tokenId);
        amount = bound(amount, 0, maxWithdraw);
        if (amount == 0) return;

        _withdraw(tokenId, amount, onBehalf);
    }

    function borrowCollateral(uint256 amount, uint256 onBehalfSeed) external {
        address onBehalf = _randomMinter(targetSenders(), onBehalfSeed);
        if (onBehalf == address(0)) return;

        // To ensure no repay or mint on the same block which is not allowed
        vm.roll(block.number + 1);

        uint256 tokenId = AlchemistNFTHelper.getFirstTokenId(onBehalf, address(alchemistNFT));

        amount = bound(amount, 0, alchemist.getMaxBorrowable(tokenId));
        if (amount == 0) return;

        _borrow(tokenId, amount, onBehalf);
    }

    function repayDebt(uint256 amount, uint256 onBehalfSeed) external {
        address onBehalf = _randomRepayer(targetSenders(), onBehalfSeed);
        if (onBehalf == address(0)) return;

        uint256 tokenId = AlchemistNFTHelper.getFirstTokenId(onBehalf, address(alchemistNFT));
        (, uint256 debt,) = alchemist.getCDP(tokenId);

        uint256 maxRepayShares = alchemist.convertDebtTokensToYield(debt);
        amount = bound(amount, 0, maxRepayShares);
        if (amount == 0) return;

        _repay(tokenId, amount, onBehalf);
    }

    function repayDebtViaBurn(uint256 amount, uint256 onBehalfSeed) external {
        address onBehalf = _randomBurner(targetSenders(), onBehalfSeed);
        if (onBehalf == address(0)) return;

        // Roll before we check CDP so new earmark does not accumulate and cause illegal state after checking account
        vm.roll(block.number + 1);

        uint256 tokenId = AlchemistNFTHelper.getFirstTokenId(onBehalf, address(alchemistNFT));

        (, uint256 debt, uint256 earmarked) = alchemist.getCDP(tokenId);

        uint256 burnable = (debt - earmarked) > (alchemist.totalSyntheticsIssued() - transmuterLogic.totalLocked()) 
        ? (alchemist.totalSyntheticsIssued() - transmuterLogic.totalLocked()) 
        : (debt - earmarked);

        amount = bound(amount, 0, burnable);
        if (amount == 0) return;

        _burn(tokenId, amount, onBehalf);
    }

    function transmuterStake(uint256 amount, uint256 onBehalfSeed) external {
        address onBehalf = _randomNonZero(targetSenders(), onBehalfSeed);
        if (onBehalf == address(0)) return;

        uint256 maxStakeable = alchemist.totalSyntheticsIssued() - transmuterLogic.totalLocked();

        amount = bound(amount, 0, maxStakeable);
        if (amount == 0) return;

        _stake(amount, onBehalf);
    }

    function transmuterClaim(uint256 onBehalfSeed) external {
        address onBehalf = _randomClaimer(targetSenders(), onBehalfSeed);
        if (onBehalf == address(0)) return;

        _claim(IERC721Enumerable(address(transmuterLogic)).tokenOfOwnerByIndex(onBehalf, 0), onBehalf);
    }

    function _sumDebts() internal view returns (uint256 total) {
        address[] memory users = targetSenders();
        for (uint256 i; i < users.length; ++i) {
            uint256 tokenId = AlchemistNFTHelper.getFirstTokenId(users[i], address(alchemistNFT));
            if (tokenId != 0) {
                (, uint256 debt,) = alchemist.getCDP(tokenId);
                total += debt;
            }
        }
    }

    function _checkDebtInvariant(string memory where) internal view {
        uint256 sum = _sumDebts();
        uint256 tot = alchemist.totalDebt();
        if (sum > tot ? (sum - tot) > 1e12 : (tot - sum) > 1e12) {
            console2.log("Debt invariant broke at:", where);
            console2.log("sumDebts:", sum);
            console2.log("totalDebt:", tot);
            console2.log("delta:", sum > tot ? sum - tot : tot - sum);
        }
    }

    function _logDebts(string memory tag) internal {
        uint256 sum;

        for (uint256 i = 1; i <= 10; i++) {
            (uint256 col, uint256 debt, uint256 earmarked) = alchemist.getCDP(i);
            if (col == 0 && debt == 0 && earmarked == 0) continue;
            console2.log(tag, "cdp", i);
            console2.log("debt", debt);
            console2.log("earmarked", earmarked);
            console2.log("col", col);
            sum += debt;
        }
        console2.log(tag, "sumDebts", sum);
        console2.log(tag, "totalDebt", alchemist.totalDebt());
        console2.log(tag, "cumulativeEarmarked", alchemist.cumulativeEarmarked());
        console2.log(tag, "lastEarmarkBlock", alchemist.lastEarmarkBlock());
        console2.log(tag, "lastRedemptionBlock", alchemist.lastRedemptionBlock());
    }
}
