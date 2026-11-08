// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

contract MerkleBase {
    
    // First Merkle tree used in tests was generated from these 6 token allocations:
    // chad      = { id: 0,    address: 0x253553366Da8546fC250F225fe3d25d0C782303b, amount: 1000000000000000000  }
    // degen     = { id: 1337, address: 0x0ac850A303169bD762a06567cAad02a8e680E7B3, amount: 15000000000000000000 }
    // habibi    = { id: 2,    address: 0xA8cc612Ecb2E853d3A882b0F9cf5357C2D892aDb, amount: 4500000000000000000  }
    // chad2     = { id: 3,    address: 0x253553366Da8546fC250F225fe3d25d0C782303b, amount: 6000000000000000000  }
    // zero      = { id: 4,    address: 0x86726BE6c9a332f10C16f9431730AFc233Db8953, amount: 0                    }
    // duplicate = { id: 2,    address: 0xE87753eB91D6A61Ea342bB9044A97764366cc7b2, amount: 1000000000000000000  }

    // Second Merkle tree used in tests (2 allocations):
    // next  = { id: 6, address: 0x95222290DD7278Aa3Ddd389Cc1E1d165CC4BAfe5, amount: 1000000000000000000 }
    // other = { id: 7, address: 0x8DC1A1493F7A94e89599A2153c994Ae29F6aFf0f, amount: 1500000000000000000 }

    bytes32 root  = 0xec8d1cd4e8b553e782cc92c706d9b0b78017848ed8957571ec391985f59221a0;
    bytes32 root2 = 0xcbe80ed3b7bd00718abe861ae242390fa7e679b8d0c0eaac9de4066f9661b15d;

    uint256 deadline = block.timestamp + 30 days;
    uint256 maxId    = 1337;

    uint256   id_chad      = 0;
    address   address_chad = 0x253553366Da8546fC250F225fe3d25d0C782303b;
    uint256   amount_chad  = 1e18;
    bytes32[] proof_chad;

    uint256   id_degen      = 1337;
    address   address_degen = 0x0ac850A303169bD762a06567cAad02a8e680E7B3;
    uint256   amount_degen  = 15e18;
    bytes32[] proof_degen;

    uint256   id_habibi      = 2;
    address   address_habibi = 0xA8cc612Ecb2E853d3A882b0F9cf5357C2D892aDb;
    uint256   amount_habibi  = 4.5e18;
    bytes32[] proof_habibi;

    uint256   id_chad2      = 3;
    address   address_chad2 = 0x253553366Da8546fC250F225fe3d25d0C782303b;
    uint256   amount_chad2  = 6e18;
    bytes32[] proof_chad2;

    uint256   id_zero      = 4;
    address   address_zero = 0x86726BE6c9a332f10C16f9431730AFc233Db8953;
    uint256   amount_zero  = 0;
    bytes32[] proof_zero;

    uint256   id_duplicate      = 2;
    address   address_duplicate = 0xE87753eB91D6A61Ea342bB9044A97764366cc7b2;
    uint256   amount_duplicate  = 1e18;
    bytes32[] proof_duplicate;

    uint256   id_next      = 6;
    address   address_next = 0x95222290DD7278Aa3Ddd389Cc1E1d165CC4BAfe5;
    uint256   amount_next  = 1e18;
    bytes32[] proof_next;

    uint256   id_other      = 7;
    address   address_other = 0x8DC1A1493F7A94e89599A2153c994Ae29F6aFf0f;
    uint256   amount_other  = 1.5e18;
    bytes32[] proof_other;

    function setUpProofs() internal {
        // Merkle tree for this test case has 6 leafs, so proofs have a length of 2 or 3.
        proof_chad.push(0x9ad099f518832b5de933a522742a61226393c4f9e97ca7bd3d66a1d2113e504b);
        proof_chad.push(0xdcd601a027047bdfd645c19c9bc45c564af9171110f6a92798a837ec5a0e8ccb);

        proof_degen.push(0x9828f5c7cd91b0f3805b7ffd2419bdcdd6a90477ca0ea7b6a235c20f97a488b4);
        proof_degen.push(0xdcd601a027047bdfd645c19c9bc45c564af9171110f6a92798a837ec5a0e8ccb);

        proof_habibi.push(0x87b483be5800325b86b3ea001fdcd6f211e16cafabf21b073eaa9ddc3f667d3e);
        proof_habibi.push(0x17677931eb18b6c83af36cb94cd602cd39ad0b0242065f970ebc3771a576521d);
        proof_habibi.push(0x353ef930c6760544b8ef7eb9975e8ff35f02b2c3f193be48f583b1fcb7b8960d);

        proof_chad2.push(0x268e4a019904ec396a744c0869998a328f10d5882555bde42617ca43de7a9b02);
        proof_chad2.push(0x41e514c722940c8d945ceea6880e7081710abee3f504f98fba471c9862b4b6bd);
        proof_chad2.push(0x353ef930c6760544b8ef7eb9975e8ff35f02b2c3f193be48f583b1fcb7b8960d);

        proof_zero.push(0x62e51e715047d2ea902d88fa695f4ac295f613821843dbd3c4475d122215db3e);
        proof_zero.push(0x17677931eb18b6c83af36cb94cd602cd39ad0b0242065f970ebc3771a576521d);
        proof_zero.push(0x353ef930c6760544b8ef7eb9975e8ff35f02b2c3f193be48f583b1fcb7b8960d);

        proof_duplicate.push(0x5cba589f80b79632daa3abc01a5b91e6989c200590fbe5d88dc9f04de10e1ca8);
        proof_duplicate.push(0x41e514c722940c8d945ceea6880e7081710abee3f504f98fba471c9862b4b6bd);
        proof_duplicate.push(0x353ef930c6760544b8ef7eb9975e8ff35f02b2c3f193be48f583b1fcb7b8960d);

        proof_next.push(0x0462c77b29bf2193b1ed83100cd962fce8b99b4717470452c0d136cfc96e8d0c);

        proof_other.push(0xd37a9e054d47f9a7b9246c9e7fd2b60c45b47f7d1a786a144381dc50498c39f3);
    }

}
