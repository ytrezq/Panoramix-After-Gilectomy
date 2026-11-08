// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// import { IERC20 } from "forge-std/interfaces/IERC20.sol";

// import { Honey } from "src/honey/Honey.sol";
// import { HoneyFactory } from "src/honey/HoneyFactory.sol";
// import "../gov/GovernanceBase.t.sol";

// /// @title ProtocolTest
// /// @notice Base contract to test the protocol functions after certain governance actions on a fork of live network
// abstract contract ProtocolTest is GovernanceBaseTest {
//     Honey internal honey;
//     HoneyFactory internal honeyFactory;

//     function setUp() public virtual override {
//         vm.createSelectFork("bartio");
//         bgt = BGT(0xbDa130737BDd9618301681329bF2e46A016ff9Ad);
//         wbera = WBERA(payable(0x7507c1dc16935B82698e4C63f2746A2fCf994dF8));
//         honey = Honey(0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03);
//         honeyFactory = HoneyFactory(0xAd1782b2a7020631249031618fB1Bd09CD926b31);
//         polDeployer = POLDeployer(0xdD2A365ac1BF20548317086b11B385fCB3085c48);
//         beraChef = polDeployer.beraChef();
//         blockRewardController = polDeployer.blockRewardController();
//         distributor = polDeployer.distributor();
//         factory = polDeployer.rewardVaultFactory();
//         feeDeployer = BGTFeeDeployer(0xA3FEE4aE585b3EE8FEBA94865e8BD608f454D44B);
//         bgtStaker = feeDeployer.bgtStaker();
//         feeCollector = feeDeployer.feeCollector();
//         governance = 0xE3EDa03401Cf32010a9A9967DaBAEe47ed0E1a0b;
//         gov = BerachainGovernance(payable(governance));
//         timelock = TimeLock(payable(0xcB364028856f2328148Bb32f9D6E7a1F86451b1c));
//     }

//     /// @dev Override with specific governance actions to test the protocol functions afterwards
//     function governanceActions() internal virtual;

//     function test_Fork() public {
//         vm.rollFork(186_420);
//         assertEq(block.chainid, 80_084);
//         assertEq(block.number, 186_420);
//         assertEq(block.timestamp, 1_718_244_027);
//     }

//     /// @dev Test the governance works
//     function test_Governance() public virtual {
//         governanceActions();

//         // Delegate tokens to self to allow for governance actions
//         deal(address(bgt), address(this), 100_000_000_000 ether);
//         bgt.delegate(address(this));

//         // can only propose with past votes
//         vm.roll(block.number + 1);

//         // Create and execute governance proposals
//         address[] memory targets = new address[](2);
//         targets[0] = address(distributor);
//         targets[1] = address(honeyFactory);

//         bytes[] memory calldatas = new bytes[](2);
//         calldatas[0] = abi.encodeCall(Distributor.setProver, (address(this)));
//         address asset = honeyFactory.registeredAssets(0);
//         calldatas[1] = abi.encodeCall(HoneyFactory.setMintRate, (asset, 1 ether));

//         governanceHelper(targets, calldatas);
//     }

//     /// @dev Test the distribution of rewards
//     function test_Distribute() public virtual {
//         test_Governance();

//         distributor.distributeFor(valData.pubkey, distributor.getNextActionableBlock());
//     }

//     /// @dev Test the minting of Honey
//     function test_MintHoney() public virtual {
//         test_Governance();

//         address asset = honeyFactory.registeredAssets(0);
//         uint256 amount = 100 ether;
//         deal(asset, address(this), amount);
//         IERC20(asset).approve(address(honeyFactory), amount);
//         uint256 honeyMinted = honeyFactory.mint(asset, amount, address(this));
//         assertEq(honey.balanceOf(address(this)), honeyMinted);
//     }
// }
