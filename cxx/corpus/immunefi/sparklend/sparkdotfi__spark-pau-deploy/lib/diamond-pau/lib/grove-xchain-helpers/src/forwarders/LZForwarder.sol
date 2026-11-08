// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { IERC20 }    from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig }      from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import { ExecutorConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";

struct MessagingParams {
    uint32  dstEid;
    bytes32 receiver;
    bytes   message;
    bytes   options;
    bool    payInLzToken;
}

struct MessagingReceipt {
    bytes32      guid;
    uint64       nonce;
    MessagingFee fee;
}

struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

interface ILayerZeroEndpointV2 {
    function lzToken() external view returns (address);
    function send(
        MessagingParams calldata _params,
        address                  _refundAddress
    ) external payable returns (MessagingReceipt memory);
    function setLzToken(address _lzToken) external;
    function quote(
        MessagingParams calldata _params,
        address                  _sender
    ) external view returns (MessagingFee memory);
    function getSendLibrary(
        address sender,
        uint32  dstEid
    ) external view returns (address lib);
    function setConfig(
        address _oapp,
        address _lib,
        SetConfigParam[] calldata _params
    ) external;
    function getConfig(
        address _oapp,
        address _lib,
        uint32  _eid,
        uint32  _configType
    ) external view returns (bytes memory config);
}

library LZForwarder {

    error LzTokenUnavailable();

    uint32 public constant ENDPOINT_ID_ETHEREUM  = 30101;
    uint32 public constant ENDPOINT_ID_AVALANCHE = 30106;
    uint32 public constant ENDPOINT_ID_BASE      = 30184;
    uint32 public constant ENDPOINT_ID_BNB       = 30102;
    uint32 public constant ENDPOINT_ID_MONAD     = 30390;
    uint32 public constant ENDPOINT_ID_PLASMA    = 30383;

    address public constant ENDPOINT_ETHEREUM  = 0x1a44076050125825900e736c501f859c50fE728c;
    address public constant ENDPOINT_AVALANCHE = 0x1a44076050125825900e736c501f859c50fE728c;
    address public constant ENDPOINT_BASE      = 0x1a44076050125825900e736c501f859c50fE728c;
    address public constant ENDPOINT_BNB       = 0x1a44076050125825900e736c501f859c50fE728c;
    address public constant ENDPOINT_MONAD     = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;
    address public constant ENDPOINT_PLASMA    = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;

    address public constant RECEIVE_LIBRARY_ETHEREUM  = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;
    address public constant RECEIVE_LIBRARY_AVALANCHE = 0xbf3521d309642FA9B1c91A08609505BA09752c61;
    address public constant RECEIVE_LIBRARY_BASE      = 0xc70AB6f32772f59fBfc23889Caf4Ba3376C84bAf;
    address public constant RECEIVE_LIBRARY_BNB       = 0xB217266c3A98C8B2709Ee26836C98cf12f6cCEC1;
    address public constant RECEIVE_LIBRARY_MONAD     = 0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043;
    address public constant RECEIVE_LIBRARY_PLASMA    = 0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043;

    address public constant EXECUTOR_ETHEREUM  = 0x173272739Bd7Aa6e4e214714048a9fE699453059;
    address public constant EXECUTOR_AVALANCHE = 0x90E595783E43eb89fF07f63d27B8430e6B44bD9c;
    address public constant EXECUTOR_BASE      = 0x2CCA08ae69E0C44b18a57Ab2A87644234dAebaE4;
    address public constant EXECUTOR_BNB       = 0x3ebD570ed38B1b3b4BC886999fcF507e9D584859;
    address public constant EXECUTOR_MONAD     = 0x4208D6E27538189bB48E603D6123A94b8Abe0A0b;
    address public constant EXECUTOR_PLASMA    = 0x4208D6E27538189bB48E603D6123A94b8Abe0A0b;

    // When passed to the config, the DVN addresses should be sorted in ascending order
    address public constant LAYER_ZERO_DVN_ETHEREUM  = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;
    address public constant NETHERMIND_DVN_ETHEREUM  = 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5;

    address public constant LAYER_ZERO_DVN_AVALANCHE = 0x962F502A63F5FBeB44DC9ab932122648E8352959;
    address public constant NETHERMIND_DVN_AVALANCHE = 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5;

    address public constant LAYER_ZERO_DVN_BASE      = 0x9e059a54699a285714207b43B055483E78FAac25;
    address public constant NETHERMIND_DVN_BASE      = 0xcd37CA043f8479064e10635020c65FfC005d36f6;

    address public constant LAYER_ZERO_DVN_BNB       = 0xfD6865c841c2d64565562fCc7e05e619A30615f0;
    address public constant NETHERMIND_DVN_BNB       = 0x31F748a368a893Bdb5aBB67ec95F232507601A73;

    address public constant LAYER_ZERO_DVN_MONAD     = 0x282b3386571f7f794450d5789911a9804FA346b4;
    address public constant NETHERMIND_DVN_MONAD     = 0xaCDe1f22EEAb249d3ca6Ba8805C8fEe9f52a16e7;

    address public constant LAYER_ZERO_DVN_PLASMA    = 0x282b3386571f7f794450d5789911a9804FA346b4;
    address public constant NETHERMIND_DVN_PLASMA    = 0xa51cE237FaFA3052D5d3308Df38A024724Bb1274;


    function sendMessage(
        uint32               _dstEid,
        bytes32              _receiver,
        ILayerZeroEndpointV2 endpoint,
        bytes         memory _message,
        bytes         memory _options,
        address              _refundAddress,
        bool                 _payInLzToken
    ) internal {
        MessagingParams memory params = MessagingParams({
            dstEid       : _dstEid,
            receiver     : _receiver,
            message      : _message,
            options      : _options,
            payInLzToken : _payInLzToken
        });

        MessagingFee memory fee = endpoint.quote(params, address(this));
        if (fee.lzTokenFee > 0) _payLzToken(endpoint, fee.lzTokenFee);

        endpoint.send{ value: fee.nativeFee }(params, _refundAddress);
    }

    function _payLzToken(ILayerZeroEndpointV2 endpoint, uint256 _lzTokenFee) internal {
        // @dev Cannot cache the token because it is not immutable in the endpoint.
        address lzToken = endpoint.lzToken();
        if (lzToken == address(0)) revert LzTokenUnavailable();

        // Pay LZ token fee by sending tokens to the endpoint.
        SafeERC20.safeTransfer(IERC20(lzToken), address(endpoint), _lzTokenFee);
    }

    /**
     * @notice Configures this contract (via address(this)) as a LayerZero sender for cross-chain messaging to a specific remote endpoint.
     * @dev Allows this contract to configure itself as a LayerZero sender for a specified remote endpoint.
     *      Registers the appropriate send library and ULN configuration needed for cross-chain messaging to the target remote endpoint.
     *      Treat with caution. Test thoroughly all the params when using in production.
     *
     * @param endpoint             The LayerZero endpoint to configure
     * @param remoteEid            The remote (destination) endpoint ID to enable messaging to
     * @param requiredDvns         The DVN addresses required for message verification
     * @param optionalDvns         The DVN addresses optional for message verification
     * @param optionalDVNThreshold The threshold for optional DVNs
     * @param confirmations        The number of confirmations to wait before emitting the message
     * @param maxMessageSize       The maximum message size
     * @param executor             The executor address
     */
    function configureSender(
        address   endpoint,
        uint32    remoteEid,
        address[] memory requiredDvns,
        address[] memory optionalDvns,
        uint8     optionalDVNThreshold,
        uint32    confirmations,
        uint32    maxMessageSize,
        address   executor
    ) internal {
        address sendLib = ILayerZeroEndpointV2(endpoint).getSendLibrary(address(0), remoteEid);

        ExecutorConfig memory executorConfig = ExecutorConfig({
            maxMessageSize : maxMessageSize,
            executor       : executor
        });

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations        : confirmations,
            requiredDVNCount     : uint8(requiredDvns.length),
            optionalDVNCount     : uint8(optionalDvns.length),
            optionalDVNThreshold : optionalDVNThreshold,
            requiredDVNs         : requiredDvns,
            optionalDVNs         : optionalDvns
        });

        SetConfigParam[] memory setConfigParam = new SetConfigParam[](2);

        setConfigParam[0] = SetConfigParam({
            eid        : remoteEid,
            configType : 1,
            config     : abi.encode(executorConfig)
        });

        setConfigParam[1] = SetConfigParam({
            eid        : remoteEid,
            configType : 2,
            config     : abi.encode(ulnConfig)
        });

        ILayerZeroEndpointV2(endpoint).setConfig(address(this), sendLib, setConfigParam);
    }

    /**
     * @notice Configures this contract (via address(this)) as a LayerZero sender for cross-chain messaging to a specific remote endpoint.
     * @dev Allows this contract to configure itself as a LayerZero sender for a specified remote endpoint.
     *      Registers the appropriate send library and ULN configuration needed for cross-chain messaging to the target remote endpoint.
     *      Uses default values for optionalDVNThreshold, confirmations, and maxMessageSize.
     *
     * @param endpoint   The LayerZero endpoint to configure
     * @param remoteEid  The remote (destination) endpoint ID to enable messaging to
     * @param dvns       The DVN addresses required for message verification
     */
    function configureSender(
        address   endpoint,
        uint32    remoteEid,
        address[] memory dvns,
        address   executor
    ) internal {
        configureSender({
            endpoint             : endpoint,
            remoteEid            : remoteEid,
            requiredDvns         : dvns,
            optionalDvns         : new address[](0),
            optionalDVNThreshold : 0,
            confirmations        : 15,
            maxMessageSize       : 10_000,
            executor             : executor
        });
    }

}
