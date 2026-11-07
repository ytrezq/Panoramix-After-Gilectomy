// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

library Utils {
    // https://docs.soliditylang.org/en/latest/assembly.html#example
    function getCodeAt(address _addr) internal view returns (bytes memory oCode) {
        assembly {
            // retrieve the size of the code, this needs assembly
            let size := extcodesize(_addr)
            // allocate output byte array - this could also be done without assembly
            // by using o_code = new bytes(size)
            oCode := mload(0x40)
            // new "memory end" including padding
            mstore(0x40, add(oCode, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            // store length in memory
            mstore(oCode, size)
            // actually retrieve the code, this needs assembly
            extcodecopy(_addr, add(oCode, 0x20), 0, size)
        }
    }

    // https://ethereum.stackexchange.com/questions/10932/how-to-convert-string-to-int
    function stringToUint(string memory s) internal pure returns (uint256) {
        bytes memory b = bytes(s);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            if (uint8(b[i]) >= 48 && uint8(b[i]) <= 57) {
                result = result * 10 + (uint256(uint8(b[i])) - 48);
            }
        }
        return result;
    }

    function encodeGetAddressCall(bytes4 _fnSig, uint256 _chainId, string memory _key)
        internal
        pure
        returns (bytes memory fnPayload)
    {
        assembly {
            function allocate(length) -> pos {
                pos := mload(0x40)
                mstore(0x40, add(pos, length))
            }

            let keyLength := mload(_key)

            fnPayload := mload(0x40)

            let p := allocate(0x20)

            let keySlots := mul(add(div(keyLength, 0x20), 0x01), 0x20)

            mstore(p, add(0x64, keySlots))

            p := allocate(0x04)
            mstore(p, _fnSig)

            p := allocate(0x20)
            mstore(p, _chainId)

            p := allocate(0x20)
            mstore(p, 0x40)

            p := allocate(0x20)
            mstore(p, keyLength)

            for { let i := 0 } lt(i, keyLength) { i := add(i, 0x20) } {
                p := allocate(0x20)
                mstore(p, mload(add(add(_key, 0x20), i)))
            }
        }
    }

    function encodeSingleSelectorCall(bytes4 _fnSig) internal pure returns (bytes memory fnPayload) {
        assembly {
            function allocate(length) -> pos {
                pos := mload(0x40)
                mstore(0x40, add(pos, length))
            }

            fnPayload := mload(0x40)

            let p := allocate(0x20)
            mstore(fnPayload, 0x04)

            p := allocate(0x04)
            mstore(p, _fnSig)
        }
    }

    // https://ethereum.stackexchange.com/questions/15350/how-to-convert-an-bytes-to-address-in-solidity
    function asciiBytesToAddress(bytes memory b) internal pure returns (address) {
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint256 c = uint256(uint8(b[i]));
            if (c >= 48 && c <= 57) {
                result = result * 16 + (c - 48);
            }
            if (c >= 65 && c <= 90) {
                result = result * 16 + (c - 55);
            }
            if (c >= 97 && c <= 122) {
                result = result * 16 + (c - 87);
            }
        }
        return address(uint160(result));
    }
}
