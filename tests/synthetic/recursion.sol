// SPDX-License-Identifier: MIT
// Recursive internal functions (src/vmrec.s, python's vm.VM.internal):
// the runtime bytecode (evm.deployedBytecode) solc 0.8.19 (solc-js) makes
// of each contract without the optimizer (recursion_0.hex,
// recursion2_0.hex) and with it, 200 runs (recursion_1.hex,
// recursion2_1.hex).
pragma solidity ^0.8.0;

contract Recursion {
    mapping(uint256 => uint256) public memo;

    function fact(uint256 n) public pure returns (uint256) {
        return _fact(n);
    }

    function _fact(uint256 n) internal pure returns (uint256) {
        if (n <= 1) return 1;
        return n * _fact(n - 1);
    }

    // a public function calling itself
    function fib(uint256 n) public pure returns (uint256) {
        if (n < 2) return n;
        return fib(n - 1) + fib(n - 2);
    }

    // the storage written on the way back
    function sumTo(uint256 n) public returns (uint256) {
        if (n == 0) return 0;
        uint256 s = n + sumTo(n - 1);
        memo[n] = s;
        return s;
    }
}

contract Recursion2 {
    struct Node { uint256 next; uint256 value; }
    mapping(uint256 => Node) public nodes;
    uint256 public total;

    // mutual recursion
    function isEven(uint256 n) public pure returns (bool) {
        return n == 0 ? true : isOdd(n - 1);
    }
    function isOdd(uint256 n) public pure returns (bool) {
        return n == 0 ? false : isEven(n - 1);
    }

    // a memory array, sorted in place
    function sort(uint256[] memory a) public pure returns (uint256[] memory) {
        if (a.length > 1) quick(a, 0, a.length - 1);
        return a;
    }
    function quick(uint256[] memory a, uint256 lo, uint256 hi) internal pure {
        if (lo >= hi) return;
        uint256 p = a[(lo + hi) / 2];
        uint256 i = lo;
        uint256 j = hi;
        while (i <= j) {
            while (a[i] < p) i++;
            while (a[j] > p) j--;
            if (i <= j) {
                (a[i], a[j]) = (a[j], a[i]);
                i++;
                if (j == 0) break;
                j--;
            }
        }
        if (lo < j) quick(a, lo, j);
        if (i < hi) quick(a, i, hi);
    }

    // a void function writing the storage
    function clear(uint256 id) public {
        _clear(id);
    }
    function _clear(uint256 id) internal {
        if (id == 0) return;
        uint256 next = nodes[id].next;
        total -= nodes[id].value;
        delete nodes[id];
        _clear(next);
    }

    // two results
    function divmodRec(uint256 a, uint256 b) public pure returns (uint256, uint256) {
        return _divmod(a, b);
    }
    function _divmod(uint256 a, uint256 b) internal pure returns (uint256 q, uint256 r) {
        if (a < b) return (0, a);
        (q, r) = _divmod(a - b, b);
        q += 1;
    }

    // called twice
    function twice(uint256 a, uint256 b) public pure returns (uint256) {
        return pow2(a) + pow2(b);
    }
    function pow2(uint256 n) internal pure returns (uint256) {
        return n == 0 ? 1 : 2 * pow2(n - 1);
    }
}
