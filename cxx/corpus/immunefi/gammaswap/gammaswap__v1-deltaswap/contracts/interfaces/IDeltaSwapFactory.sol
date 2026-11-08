// SPDX-License-Identifier: GPL-v3
pragma solidity >=0.5.0;

interface IDeltaSwapFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);
    event GammaPoolSet(address indexed pair, address gammaPool);

    function feeTo() external view returns (address);
    function feeNum() external view returns (uint16);
    function feeToSetter() external view returns (address);
    function gammaPoolSetter() external view returns (address);
    function gsFactory() external view returns(address);
    function gsProtocolId() external view returns(uint16);
    function gsFee() external view returns(uint8);
    function dsFee() external view returns(uint8);
    function dsFeeThreshold() external view returns(uint8);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint256) external view returns (address pair);
    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeNum(uint16) external;
    function setFeeTo(address) external;
    function setFeeToSetter(address) external;

    function setGSFactory(address factory) external;
    function setGSProtocolId(uint16 protocolId) external;
    function setGSFee(uint8 fee) external;
    function setDSFee(uint8 fee) external;
    function setDSFeeThreshold(uint8 feeThreshold) external;

    function feeInfo() external view returns (address,uint16);
    function dsFeeInfo() external view returns (uint8,uint8);

    function setGammaPoolSetter(address) external;
    function updateGammaPool(address tokenA, address tokenB) external;
}