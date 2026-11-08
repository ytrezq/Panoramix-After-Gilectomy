//// SPDX-License-Identifier: UNLICENSED
//pragma solidity ^0.8.24;
//
//import {Test} from "forge-std/Test.sol";
//import {
//   MessagingFee,
//   MessagingParams
//} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
//import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
//import {PredepostVaultOApp} from "../../../src/periphery/PredepostVaultOApp.sol";
//import {IPredepostVaultOApp} from "../../../src/periphery/interface/IPredepostVaultOApp.sol";
//import {ERC20Mock} from "../../mock/ERC20Mock.sol";
//import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
//import "forge-std/console.sol";
//
//interface ILayerZeroEndpointV2 {
//   function quote(MessagingParams calldata _params, address _sender) external view returns (MessagingFee memory);
//}
//
//contract BatchQuoteUnitTest is Test {
//   using OptionsBuilder for bytes;
//
//   // LayerZero Mainnet Endpoint V2
//   address constant LZ_ENDPOINT_MAINNET = 0x1a44076050125825900e736c501f859c50fE728c;
//
//   // Destination endpoint IDs
//   uint32 constant ARBITRUM_EID = 30110; // Arbitrum mainnet
//   uint32 constant OPTIMISM_EID = 30111; // Optimism mainnet
//   uint32 constant BASE_EID = 30184; // Base mainnet
//
//   uint16 constant MSG_TYPE_BATCH_CLAIM = 2;
//
//   ILayerZeroEndpointV2 public endpoint;
//   address[] public users;
//   bytes32 public mockPeer;
//
//   function setUp() public {
//       // Note: This test requires running with --fork-url <MAINNET_RPC_URL>
//       // Example: forge test --match-test test_quoteBatchClaimOnTargetChain_maxViableArray --fork-url https://eth.llamarpc.com
//
//       endpoint = ILayerZeroEndpointV2(LZ_ENDPOINT_MAINNET);
//
//       // Create mock peer address
//       mockPeer = bytes32(uint256(uint160(makeAddr("mockPeer"))));
//
//       // Create a large array of mock user addresses
//       uint256 numUsers = 100; // Maximum viable array size
//       users = new address[](numUsers);
//
//       for (uint256 i = 0; i < numUsers; i++) {
//           users[i] = makeAddr(string(abi.encodePacked("user", i)));
//       }
//   }
//
//   function test_quoteBatchClaimOnTargetChain_maxViableArray() public view {
//       console.log("\n=== LayerZero Batch Claim Quote Test (Mainnet Fork) ===");
//       console.log("Number of users:", users.length);
//       console.log("LayerZero Endpoint:", LZ_ENDPOINT_MAINNET);
//       console.log("");
//
//       // Test multiple destination chains
//       uint32[3] memory dstEids = [ARBITRUM_EID, OPTIMISM_EID, BASE_EID];
//       string[3] memory chainNames = ["Arbitrum", "Optimism", "Base"];
//
//       for (uint256 c = 0; c < dstEids.length; c++) {
//           uint32 dstEid = dstEids[c];
//
//           console.log("--- Destination Chain:", chainNames[c], "---");
//           console.log("EID:", dstEid);
//
//           // Build options with appropriate gas limit for batch operation
//           bytes memory optionsForChain = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500000, 0);
//
//           // Mock shares array (simulating 1000e18 shares per user)
//           uint256[] memory sharesArray = new uint256[](users.length);
//           for (uint256 i = 0; i < users.length; i++) {
//               sharesArray[i] = 1000e18;
//           }
//
//           // Construct the message payload exactly as quoteBatchClaimOnTargetChain does
//           bytes memory payload = abi.encode(MSG_TYPE_BATCH_CLAIM, users, sharesArray);
//
//           console.log("Payload size (bytes):", payload.length);
//
//           // Build MessagingParams struct
//           MessagingParams memory params = MessagingParams({
//               dstEid: dstEid,
//               receiver: mockPeer,
//               message: payload,
//               options: optionsForChain,
//               payInLzToken: false
//           });
//
//           // Call the LayerZero endpoint quote function directly
//           MessagingFee memory fee = endpoint.quote(params, address(this));
//
//           console.log("Native fee (wei):", fee.nativeFee);
//
//           // Calculate and display in ETH with 8 decimal places
//           uint256 feeInEth = fee.nativeFee / 1e10; // Get 8 decimal places
//           uint256 ethWhole = feeInEth / 100000000;
//           uint256 ethDecimals = feeInEth % 100000000;
//
//           // Format with leading zeros if needed
//           if (ethDecimals < 10000000 && ethDecimals > 0) {
//               console.log("Native fee (ETH): %s.0%s", ethWhole, ethDecimals);
//           } else {
//               console.log("Native fee (ETH): %s.%s", ethWhole, ethDecimals);
//           }
//
//           console.log("LZ token fee:", fee.lzTokenFee);
//
//           // Calculate average fee per user
//           uint256 avgFeePerUser = fee.nativeFee / users.length;
//           console.log("Average fee per user (wei):", avgFeePerUser);
//           console.log("Average fee per user (gwei):", avgFeePerUser / 1e9);
//           console.log("");
//
//           // Verify fee is non-zero
//           assertGt(fee.nativeFee, 0, "Native fee should be non-zero");
//       }
//
//       console.log("\n=== Scalability Analysis ===");
//       console.log("Testing different batch sizes to Arbitrum:\n");
//
//       uint256[] memory testSizes = new uint256[](5);
//       testSizes[0] = 10;
//       testSizes[1] = 25;
//       testSizes[2] = 50;
//       testSizes[3] = 75;
//       testSizes[4] = 100;
//
//       bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500000, 0);
//
//       for (uint256 i = 0; i < testSizes.length; i++) {
//           uint256 size = testSizes[i];
//
//           // Create subset of users
//           address[] memory subset = new address[](size);
//           uint256[] memory sharesSubset = new uint256[](size);
//           for (uint256 j = 0; j < size; j++) {
//               subset[j] = users[j];
//               sharesSubset[j] = 1000e18;
//           }
//
//           bytes memory payload = abi.encode(MSG_TYPE_BATCH_CLAIM, subset, sharesSubset);
//
//           MessagingParams memory params = MessagingParams({
//               dstEid: ARBITRUM_EID,
//               receiver: mockPeer,
//               message: payload,
//               options: options,
//               payInLzToken: false
//           });
//
//           MessagingFee memory fee = endpoint.quote(params, address(this));
//
//           // Calculate ETH values with 8 decimal places
//           uint256 feeInEth = fee.nativeFee / 1e10;
//           uint256 ethWhole = feeInEth / 100000000;
//           uint256 ethDecimals = feeInEth % 100000000;
//
//           console.log("Batch size:", size);
//           console.log("  Payload (bytes):", payload.length);
//           console.log("  Total fee (wei):", fee.nativeFee);
//
//           // Format with leading zeros if needed
//           if (ethDecimals < 10000000 && ethDecimals > 0) {
//               console.log("  Total fee (ETH): %s.0%s", ethWhole, ethDecimals);
//           } else {
//               console.log("  Total fee (ETH): %s.%s", ethWhole, ethDecimals);
//           }
//           //31430739387046
//           //45161703733280
//           console.log("  Per user (wei):", fee.nativeFee / size);
//           console.log("");
//       }
//   }
//
//   function test_quoteBatchClaimOnTargetChain_viaOApp() public {
//       console.log("\n=== Testing OApp quoteBatchClaimOnTargetChain Function ===");
//
//       // Deploy a mock vault (simulating the predeposit vault)
//       ERC20Mock mockVault = new ERC20Mock();
//
//       // Deploy OApp implementation and proxy
//       PredepostVaultOApp oappImpl = new PredepostVaultOApp(LZ_ENDPOINT_MAINNET);
//       PredepostVaultOApp oapp = PredepostVaultOApp(
//           address(
//               new ERC1967Proxy(
//                   address(oappImpl),
//                   abi.encodeCall(PredepostVaultOApp.initialize, (address(mockVault), address(this)))
//               )
//           )
//       );
//       oapp.setDstEid(ARBITRUM_EID);
//       oapp.setPeer(ARBITRUM_EID, mockPeer);
//
//       // Mint some shares to users to simulate realistic balances
//       for (uint256 i = 0; i < 100; i++) {
//           mockVault.mint(users[i], i);
//       }
//
//       // Create a batch of 10 users
//       address[] memory batchUsers = new address[](100);
//       for (uint256 i = 0; i < 100; i++) {
//           batchUsers[i] = users[i];
//       }
//       bytes memory addressesData = abi.encode(batchUsers);
//
//       // Build options
//       bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500000, 0);
//
//       console.log("Number of users in batch:", batchUsers.length);
//       console.log("Destination EID:", ARBITRUM_EID);
//
//       // Call the OApp's quoteBatchClaimOnTargetChain function
//       MessagingFee memory fee = oapp.quoteBatchClaimOnTargetChain(addressesData, options, false);
//
//       console.log("Native fee (wei):", fee.nativeFee);
//       console.log("LZ token fee:", fee.lzTokenFee);
//
//       // Calculate and display in ETH
//       uint256 feeInEth = fee.nativeFee / 1e10;
//       uint256 ethWhole = feeInEth / 100000000;
//       uint256 ethDecimals = feeInEth % 100000000;
//
//       if (ethDecimals < 10000000 && ethDecimals > 0) {
//           console.log("Native fee (ETH): %s.0%s", ethWhole, ethDecimals);
//       } else {
//           console.log("Native fee (ETH): %s.%s", ethWhole, ethDecimals);
//       }
//
//       // Verify fee is non-zero
//       assertGt(fee.nativeFee, 0, "Native fee should be non-zero");
//
//       console.log("\n=== Testing different batch sizes via OApp ===");
//
//       uint256[] memory sizes = new uint256[](5);
//       sizes[0] = 5;
//       sizes[1] = 10;
//       sizes[2] = 25;
//       sizes[3] = 50;
//       sizes[4] = 100;
//
//       for (uint256 i = 0; i < sizes.length; i++) {
//           uint256 size = sizes[i];
//
//           // Mint shares to additional users if needed
//           for (uint256 j = 0; j < size; j++) {
//               if (mockVault.balanceOf(users[j]) == 0) {
//                   mockVault.mint(users[j], 1000e18);
//               }
//           }
//
//           address[] memory subset = new address[](size);
//           for (uint256 j = 0; j < size; j++) {
//               subset[j] = users[j];
//           }
//
//           bytes memory batchData = abi.encode(subset);
//           MessagingFee memory batchFee = oapp.quoteBatchClaimOnTargetChain(batchData, options, false);
//
//           console.log("Batch size:", size);
//           console.log("  Fee (wei):", batchFee.nativeFee);
//           console.log("  Per user (wei):", batchFee.nativeFee / size);
//           console.log("");
//
//           assertGt(batchFee.nativeFee, 0, "Batch fee should be non-zero");
//       }
//   }
//}
