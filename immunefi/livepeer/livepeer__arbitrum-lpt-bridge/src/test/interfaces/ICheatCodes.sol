pragma solidity 0.8.9;

interface ICheatCodes {
    function roll(uint256) external;

    function prank(address) external;

    function deal(address who, uint256 newBalance) external;

    function startPrank(address) external;

    function stopPrank() external;

    function envString(string calldata key) external view returns (string memory);

    function envUint(string calldata key) external view returns (uint256);
    
    function createFork(string calldata urlOrAlias) external returns (uint256);

    function createFork(string calldata urlOrAlias, uint256 blockNumber) external returns (uint256);

    function selectFork(uint256 forkId) external;

    function expectRevert(bytes4 message) external;

    function expectRevert(bytes calldata) external;

    function makeAddr(string calldata) external returns (address);

    function etch(address target, bytes calldata newRuntimeBytecode) external;
}

