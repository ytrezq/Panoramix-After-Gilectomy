pragma solidity 0.4.24;

import "../upgradeable_contracts/erc20_to_native/XDaiForeignBridge.sol";

contract XDaiForeignBridgeMock is XDaiForeignBridge {
    /**
     * @dev Tells the address of the DAI token in the Ganache Testchain.
     */
    function daiToken() public pure returns (ERC20) {
        return ERC20(0x0a4dBaF9656Fd88A32D087101Ee8bf399f4bd55f);
    }

    /**
     * @dev Tells the address of the sDAI token in the Ganache Testchain.
     */
    function sDaiToken() public pure returns (ISavingsDai) {
        return ISavingsDai(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
    }
}
