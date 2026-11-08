// SPDX-License-Identifier: GPL-v3
pragma solidity =0.8.21;

import './libraries/DSMath.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IDeltaSwapPair.sol';
import './interfaces/IDeltaSwapFactory.sol';
import './interfaces/IDeltaSwapCallee.sol';
import './DeltaSwapERC20.sol';

contract DeltaSwapPair is DeltaSwapERC20, IDeltaSwapPair {
    using UQ112x112 for uint224;

    uint256 public constant override MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public override factory;
    address public override token0;
    address public override token1;

    address public override gammaPool;

    uint112 private liquidityEMA;
    uint32 private lastLiquidityBlockNumber;

    uint112 private tradeLiquidityEMA;     // uses single storage slot
    uint112 private lastTradeLiquiditySum; // uses single storage slot
    uint32 private lastTradeBlockNumber;   // uses single storage slot

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint256 public override price0CumulativeLast;
    uint256 public override price1CumulativeLast;
    uint256 public override kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'DeltaSwap: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves() public override view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'DeltaSwap: TRANSFER_FAILED');
    }

    constructor() {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external override {
        require(msg.sender == factory, 'DeltaSwap: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    // called by the factory after deployment
    function setGammaPool(address pool) external override {
        require(msg.sender == factory, 'DeltaSwap: FORBIDDEN'); // sufficient check
        gammaPool = pool;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, 'DeltaSwap: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed;
        unchecked {
            timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        }
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            unchecked{
                price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
                price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
            }
        }
        (uint112 _liquidityEMA, uint32 _lastLiquidityBlockNumber) = getLiquidityEMA(); // saves gas
        if(block.number != _lastLiquidityBlockNumber) {
            liquidityEMA = uint112(DSMath.calcEMA(DSMath.sqrt(balance0 * balance1), _liquidityEMA, DSMath.max(block.number - _lastLiquidityBlockNumber, 10)));
            lastLiquidityBlockNumber = uint32(block.number);
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function _updateLiquidityTradedEMA(uint256 tradeLiquidity) internal virtual returns(uint256 _tradeLiquidityEMA) {
        require(tradeLiquidity > 0, "DeltaSwap: ZERO_TRADE_LIQUIDITY");
        uint256 blockNum = block.number;
        uint256 tradeLiquiditySum;
        (_tradeLiquidityEMA,,tradeLiquiditySum) = _getTradeLiquidityEMA(tradeLiquidity, blockNum);
        lastTradeLiquiditySum = uint112(tradeLiquiditySum);
        tradeLiquidityEMA = uint112(_tradeLiquidityEMA);
        if(lastTradeBlockNumber != blockNum) {
            lastTradeBlockNumber = uint32(blockNum);
        }
    }

    function estimateTradingFee(uint256 tradeLiquidity) external virtual override view returns(uint256 fee) {
        (uint256 _tradeLiquidityEMA,,) = _getTradeLiquidityEMA(tradeLiquidity, block.number);
        fee = calcTradingFee(tradeLiquidity, _tradeLiquidityEMA, liquidityEMA);
    }

    function calcTradingFee(uint256 tradeLiquidity, uint256 lastLiquidityTradedEMA, uint256 lastLiquidityEMA) public virtual override view returns(uint256) {
        (uint8 dsFee, uint8 dsFeeThreshold) = IDeltaSwapFactory(factory).dsFeeInfo();
        if(DSMath.max(tradeLiquidity, lastLiquidityTradedEMA) >= lastLiquidityEMA * dsFeeThreshold / 1000) { // if trade >= threshold, charge fee
            return dsFee;
        }
        return 0;
    }

    function getLiquidityEMA() public virtual override view returns(uint112 _liquidityEMA, uint32 _lastLiquidityBlockNumber) {
        _liquidityEMA = liquidityEMA;
        _lastLiquidityBlockNumber = lastLiquidityBlockNumber;
    }

    function getTradeLiquidityEMAParams() external virtual override view returns(uint112 _tradeLiquidityEMA, uint112 _lastTradeLiquiditySum, uint32 _lastTradeBlockNumber) {
        _tradeLiquidityEMA = tradeLiquidityEMA;
        _lastTradeLiquiditySum = lastTradeLiquiditySum;
        _lastTradeBlockNumber = lastTradeBlockNumber;
    }

    function getTradeLiquidityEMA(uint256 tradeLiquidity) external virtual override view
        returns(uint256 _tradeLiquidityEMA, uint256 lastTradeLiquidityEMA, uint256 tradeLiquiditySum) {
        return _getTradeLiquidityEMA(tradeLiquidity, block.number);
    }

    function _getTradeLiquidityEMA(uint256 tradeLiquidity, uint256 blockNumber) internal virtual view
        returns(uint256 _tradeLiquidityEMA, uint256 lastTradeLiquidityEMA, uint256 tradeLiquiditySum) {
        uint256 blockDiff = blockNumber - lastTradeBlockNumber;
        tradeLiquiditySum = _getLastTradeLiquiditySum(tradeLiquidity, blockDiff);
        lastTradeLiquidityEMA = _getLastTradeLiquidityEMA(blockDiff);
        _tradeLiquidityEMA = tradeLiquidity > 0 ? DSMath.calcEMA(tradeLiquiditySum, lastTradeLiquidityEMA, 20) : lastTradeLiquidityEMA;
    }

    function getLastTradeLiquiditySum(uint256 tradeLiquidity) external virtual override view returns(uint112 _tradeLiquiditySum, uint32 _lastTradeBlockNumber) {
        _lastTradeBlockNumber = lastTradeBlockNumber;
        _tradeLiquiditySum = uint112(_getLastTradeLiquiditySum(tradeLiquidity, block.number - _lastTradeBlockNumber));
    }

    function getLastTradeLiquidityEMA() external virtual override view returns(uint256) {
        return _getLastTradeLiquidityEMA(block.number - lastLiquidityBlockNumber);
    }

    function _getLastTradeLiquiditySum(uint256 tradeLiquidity, uint256 blockDiff) internal virtual view returns(uint256) {
        if(blockDiff > 0) {
            return tradeLiquidity;
        } else {
            return lastTradeLiquiditySum + tradeLiquidity;
        }
    }

    function _getLastTradeLiquidityEMA(uint256 blockDiff) internal virtual view returns(uint256) {
        if(blockDiff > 50) {
            // if no trade in 50 blocks (~10 minutes), then reset
            return 0;
        }
        return tradeLiquidityEMA;
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        (address feeTo, uint256 feeNum) = IDeltaSwapFactory(factory).feeInfo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = DSMath.sqrt(uint256(_reserve0) * _reserve1);
                uint256 rootKLast = DSMath.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply * (rootK - rootKLast);
                    uint256 denominator = rootK * feeNum / 1000 + rootKLast;
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external override lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = DSMath.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = DSMath.min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1);
        }
        require(liquidity > 0, 'DeltaSwap: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external override lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity * balance0 / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity * balance1 / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'DeltaSwap: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external override lock {
        require(amount0Out > 0 || amount1Out > 0, 'DeltaSwap: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'DeltaSwap: INSUFFICIENT_LIQUIDITY');

        uint256 balance0;
        uint256 balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, 'DeltaSwap: INVALID_TO');
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
            if (data.length > 0) IDeltaSwapCallee(to).deltaSwapCall(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'DeltaSwap: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint256 fee;
            if(msg.sender != gammaPool) {
                uint256 tradeLiquidity = DSMath.calcTradeLiquidity(amount0In, amount1In, _reserve0, _reserve1);
                fee = calcTradingFee(tradeLiquidity, _updateLiquidityTradedEMA(tradeLiquidity), liquidityEMA);
            } else {
                fee = IDeltaSwapFactory(factory).gsFee();
            }
            uint256 balance0Adjusted = balance0 * 1000 - amount0In * fee;
            uint256 balance1Adjusted = balance1 * 1000 - amount1In * fee;
            require(balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * _reserve1 * (1000**2), 'DeltaSwap: K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external override lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    // force reserves to match balances
    function sync() external override lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}