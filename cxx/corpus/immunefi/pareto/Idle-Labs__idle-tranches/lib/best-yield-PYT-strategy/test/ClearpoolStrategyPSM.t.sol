// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../src/interfaces/IIdleCDO.sol";
import "../src/interfaces/IIdleToken.sol";
import "../src/interfaces/IPoolMaster.sol";
import "../src/ClearpoolStrategyPSM.sol";
import "@oz-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

contract TestClearpoolStrategyPSM is Test {
  using stdStorage for StdStorage;
  uint256 public constant blockForTest = 17081240;

  address public constant IDLE_TOKEN = 0x3fE7940616e5Bc47b0775a0dccf6237893353bB4; // idleUSDC
  address public constant UNDERLYING = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // USDC
  address public constant AA_TRANCHE = 0x43eD68703006add5F99ce36b5182392362369C1c; // AA_cpWIN-USDC
  address public constant CDO = 0x5dcA0B3Ed7594A6613c1A2acd367d56E1f74F92D; // clearpool cdo
  address public constant CP_TOKEN = 0x4a90c14335E81829D7cb0002605f555B8a784106; // cpWIN-USDC
  IIdleToken public idleToken;
  IIdleCDO public idleCDO;
  IERC20Upgradeable public underlying;
  IERC20Upgradeable public tranche;
  IdlePYT public strategy;
  uint256 public initialTrancheBalance;

  function _forkAt(uint256 _block) internal {
    vm.selectFork(vm.createFork(vm.envString("ETH_RPC_URL"), _block));
  }
  function setUp() public {
    _forkAt(blockForTest);
    idleToken = IIdleToken(IDLE_TOKEN);
    idleCDO = IIdleCDO(CDO);
    underlying = IERC20Upgradeable(UNDERLYING);
    tranche = IERC20Upgradeable(AA_TRANCHE);
    strategy = new IdlePYTClearPSM();
    stdstore
      .target(address(strategy))
      .sig(strategy.token.selector)
      .checked_write(address(0));
    strategy.initialize(AA_TRANCHE, IDLE_TOKEN, CDO);
    // give 10M to this contract
    deal(address(underlying), address(this), 100000000 * 1e6, true);
    // approve idleToken to spend underlyings
    underlying.approve(IDLE_TOKEN, type(uint256).max);

    vm.label(address(strategy), "strategy");
    vm.label(UNDERLYING, "underlying");
    vm.label(IDLE_TOKEN, "idleToken");
    vm.label(CDO, "idleCDO");
    vm.label(AA_TRANCHE, "AATranche");
  }

  function testInitialize() public {
    assertTrue(address(strategy.idleCDO()) == CDO);
    assertTrue(strategy.token() == AA_TRANCHE);
    assertTrue(strategy.underlying() == UNDERLYING);
    assertTrue(strategy.idleToken() == IDLE_TOKEN);
    assertTrue(underlying.allowance(address(strategy), CDO) == type(uint256).max);
  }

  function testCannotMint() public {
    vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
    strategy.mint();
  }

  function testMint() public {
    uint256 _amount = 1000e6;
    // move idleToken funds in to the tested strategy
    _updateIdleTokenStrategy(address(strategy));
    initialTrancheBalance = tranche.balanceOf(address(idleToken));
    uint256 _tranchePrice = strategy.getPriceInToken();
    // deposit
    idleToken.mintIdleToken(_amount, true, address(0));
    // put funds in the strategy
    vm.prank(idleToken.rebalancer());
    idleToken.rebalance();

    uint256 trancheBal = tranche.balanceOf(address(idleToken));
    assertEq(trancheBal - initialTrancheBalance, _amount * 1e18 / _tranchePrice);
  }

  function testCannotRedeem() public {
    vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
    strategy.redeem(address(this));
  }

  function testRedeem() public {
    uint256 balPre = underlying.balanceOf(address(this));
    deposit(1000e6);
    skip(1 days);
    vm.roll(block.number + 1); // avoid reentrancy check
    idleToken.redeemIdleToken(idleToken.balanceOf(address(this)));
    assertGt(underlying.balanceOf(address(this)), balPre);
  }

  function testPrice() public {
    assertEq(strategy.getPriceInToken(), idleCDO.virtualPrice(address(tranche)));
  }

  function testAPR() public {
    uint256 apr = idleCDO.getApr(address(tranche));
    // fee is 15% 
    apr = apr * 85 / 100;
    assertEq(strategy.getAPR(), apr);
  }

  function testAvailableLiquidity() virtual public {
    underlying.approve(address(idleCDO), type(uint256).max);
    uint256 amount = 100e6;
    idleCDO.depositBB(amount);

    IPoolMaster cpToken = IPoolMaster(IIdleCDOStrategyClear(idleCDO.strategy()).cpToken());

    // we need to scale availableToWithdraw by 1e12 because we use DAI
    assertEq(
      strategy.availableLiquidity(), 
      underlying.balanceOf(address(idleCDO)) + cpToken.availableToWithdraw() * 1e12
    );
  }

  function deposit(uint256 _amount) public {
    // move idleToken funds in to the tested strategy
    _updateIdleTokenStrategy(address(strategy));
    initialTrancheBalance = tranche.balanceOf(address(idleToken));
    // deposit
    idleToken.mintIdleToken(_amount, true, address(0));
    // put funds in the strategy
    vm.prank(idleToken.rebalancer());
    idleToken.rebalance();
  }

  // WARN: Don't call this in the setUp otherwise it won't work
  function _updateIdleTokenStrategy(address _strategy) internal {
    // replace last strategy
    address[] memory allTokens = idleToken.getAllAvailableTokens();
    uint256 len = allTokens.length;
    address[] memory protocolTokens = new address[](len);
    address[] memory wrappers = new address[](len);
    address[] memory _newGovTokens = new address[](len);
    address[] memory _newGovTokensEqualLen = new address[](len);

    // loop through all the tokens and add populate the arrays
    // for the setAllAvailableTokensAndWrappers call
    for (uint256 i = 0; i < len - 1; i++) {
      protocolTokens[i] = allTokens[i];
      wrappers[i] = idleToken.protocolWrappers(allTokens[i]);
      _newGovTokensEqualLen[i] = idleToken.getProtocolTokenToGov(allTokens[i]);
    }
    _newGovTokens = idleToken.getGovTokens();
    protocolTokens[len - 1] = strategy.token();
    wrappers[len - 1] = _strategy;
    _newGovTokensEqualLen[len - 1] = address(0);

    // add the strategy to the idleToken and set unlent to 0 for easy calc
    vm.startPrank(idleToken.owner());
    idleToken.setAllAvailableTokensAndWrappers(protocolTokens, wrappers, _newGovTokens, _newGovTokensEqualLen);
    idleToken.setMaxUnlentPerc(0);
    idleToken.setFee(0);
    vm.stopPrank();

    // put funds in the strategy
    vm.startPrank(idleToken.rebalancer());
    // set allocations
    uint256[] memory alloc = new uint256[](len);
    alloc[len - 1] = 100000; // all in current strategy
    idleToken.setAllocations(alloc);

    // rebalance
    idleToken.rebalance();
    vm.stopPrank();
  }
}
