// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../src/interfaces/IIdleCDO.sol";
import "../src/interfaces/IIdleToken.sol";
import "../src/interfaces/IPoolMaster.sol";
import "../src/ClearpoolStrategy.sol";
import "@oz-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

contract TestClearpoolStrategy is Test {
  using stdStorage for StdStorage;

  address public constant IDLE_TOKEN = 0x5274891bEC421B39D23760c04A6755eCB444797C; // idleUSDC
  address public constant UNDERLYING = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
  address public constant AA_TRANCHE = 0xb86264c21418aA75F7c337B1821CcB4Ff4d57673; // AA_cpWIN-USDC
  address public constant CDO = 0xDBCEE5AE2E9DAf0F5d93473e08780C9f45DfEb93; // clearpool cdo
  address public constant CP_TOKEN = 0xCb288b6d30738db7E3998159d192615769794B5b; // cpWIN-USDC
  IIdleToken public idleToken;
  IIdleCDO public idleCDO;
  IERC20Upgradeable public underlying;
  IERC20Upgradeable public tranche;
  IdlePYT public strategy;
  uint256 public initialTrancheBalance;
  
  function setUp() public {
    idleToken = IIdleToken(IDLE_TOKEN);
    idleCDO = IIdleCDO(CDO);
    underlying = IERC20Upgradeable(UNDERLYING);
    tranche = IERC20Upgradeable(AA_TRANCHE);
    strategy = new IdlePYTClear();
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
    underlying.transfer(address(strategy), 1e6);
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

  function testNextSupplyRate() public {
    // deposit some tokens in the junior side to balance the ratio a bit
    underlying.approve(address(idleCDO), type(uint256).max);
    idleCDO.depositBB(1000000e6);
    vm.roll(block.number + 1);
    _updateIdleTokenStrategy(address(strategy));
    assertEq(strategy.nextSupplyRate(0), strategy.getAPR());

    uint256 apr = idleCDO.getApr(address(tranche));
    uint256 _amount = 1000000e6;
    // in PYTs apr increases for the specific tranche with more TVL
    assertGt(
      strategy.nextSupplyRate(_amount), 
      apr * 85 / 100
    );
  }

  function testAvailableLiquidity() virtual public {
    underlying.approve(address(idleCDO), type(uint256).max);
    uint256 amount = 100e6;
    idleCDO.depositBB(amount);

    IPoolMaster cpToken = IPoolMaster(IIdleCDOStrategyClear(idleCDO.strategy()).cpToken());

    assertEq(
      strategy.availableLiquidity(), 
      underlying.balanceOf(address(idleCDO)) + cpToken.availableToWithdraw()
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
    // set the strategy as one of the available ones
    address[] memory allTokens = idleToken.getAllAvailableTokens();
    uint256 len = allTokens.length;
    address[] memory protocolTokens = new address[](len + 1);
    address[] memory wrappers = new address[](len + 1);
    address[] memory _newGovTokens = new address[](len);
    address[] memory _newGovTokensEqualLen = new address[](len + 1);

    // loop through all the tokens and add populate the arrays
    // for the setAllAvailableTokensAndWrappers call
    for (uint256 i = 0; i < len; i++) {
      protocolTokens[i] = allTokens[i];
      wrappers[i] = idleToken.protocolWrappers(allTokens[i]);
      _newGovTokensEqualLen[i] = idleToken.getProtocolTokenToGov(allTokens[i]);
    }
    _newGovTokens = idleToken.getGovTokens();
    protocolTokens[len] = strategy.token();
    wrappers[len] = _strategy;
    _newGovTokensEqualLen[len] = address(0);

    // add the strategy to the idleToken and set unlent to 0 for easy calc
    vm.startPrank(idleToken.owner());
    idleToken.setAllAvailableTokensAndWrappers(protocolTokens, wrappers, _newGovTokens, _newGovTokensEqualLen);
    idleToken.setMaxUnlentPerc(0);
    idleToken.setFee(0);
    vm.stopPrank();

    // put funds in the strategy
    vm.startPrank(idleToken.rebalancer());
    // set allocations
    uint256[] memory alloc = new uint256[](len + 1);
    alloc[len] = 100000; // all in current strategy
    idleToken.setAllocations(alloc);

    // rebalance
    idleToken.rebalance();
    vm.stopPrank();
  }
}
