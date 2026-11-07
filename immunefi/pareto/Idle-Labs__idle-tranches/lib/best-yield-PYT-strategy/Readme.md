# Idle Best yield strategy for Idle PYTs
This strategy allows [Idle Best yield](https://github.com/Idle-Labs/idle-contracts) to deploy capital in [Idle Perpetual Yield Tranches](https://github.com/Idle-Labs/idle-tranches).

Cloneable instance for both tranches deployed at 
- Cloneable `0xa575b3a6d88e9c1b5196cb7e2a14962a5c533559` instance for clearpool / ribbon
  - 0x7eC173d5bE66c83487f16f1ca304AC72639e80d4 ->  bb tranche of cpwinusdc
  - 0xfE92E0973ff0267447f8C711d16A849837C73264 ->  bb tranche of cpfolusdc
  - 0xD19f42Ce3b799a4D23176da193673b146968C934 ->  bb tranche of rfolusdc
  - 0x3225cb1d7bDFddEA35178FD1667D8BD62afb0DDe ->  bb tranche of rwinusdc
  - 0x46e30328920036d7BffCcc14348808bF65C6DaEE ->  bb tranche of cpporusdc
  - 0x9115469239A781e52A518158CBAf36FAfc8B2A77 ->  bb tranche of cpfasusdt
  - 0xC72e841B460Ec6D3e969e5C457A1961463e12e00 ->  bb tranche of cpfasusdc

  - 0xDd585E6e3AcB30594E7b70DCee34400E172cee31 -> aa tranche of cpfoldai
  - 0xFF12A5eaE3E60096c774AD7211AE5C0c5b5Cc0F5 -> aa tranche of cpwinusdc
  - 0x75DA360514532813B460b2Ba30F444A1fa28c9d7 -> aa tranche of rwindai
  - 0xF1fdd2FbB34969B4cD034331D37A7360B0b75c51 -> aa tranche of cpporusdc
  - 0xAC64A8b5Fae61b31F9eDc6e3d15673039D8122B1 -> aa tranche of cpfasusdt
  - 0x3E9A5c91eC8b5022E88d1C2599fE3CD98406D898 -> aa tranche of cpfasusdc

- Cloneable `0x6FA86028323Ba310FE4488F74085De99Ed0264d8` instance for Clearpool DAI pools with PSM
  - 0x6FA86028323Ba310FE4488F74085De99Ed0264d8 -> aa tranche of cppordai
  - 0xBC4c00f28b3023620db7ce398F6df0ac3Bdf952C -> bb tranche of cppordai

- Cloneable Euler Staking `0xcf93471a82241c2be469d83d960932721b098ffb` 
  -> used directly for bb tranche of eUSDCStaking PYT
  - 0x6C1a844E3077e6C39226C15b857436a6a92Be5C0 -> aa tranche of eUSDCStaking PYT
  - 0xAB3919896975F43A81325B0Ca98b72249E714e6C -> aa tranche of eUSDTStaking PYT
  - 0xC24e0dd3A0Bc6f19aEEc2d7985dd3940D59dB698 -> aa tranche of eWETHStaking PYT
  - 0xC9C83bEBd31aff93a2353920F2513D372847A517 -> aa tranche of eDAIStaking PYT

  - 0x13b9a2b6434C3b0955F2b164784CB39dFF373C7c -> bb tranche of eUSDTStaking PYT
  - 0x7188A402Ebd2638d6CccB855019727616a81bBd9 -> bb tranche of eDAIStaking PYT
  - 0xD57017632c1e6819370107d8Db4b1D372213a168 -> bb tranche of eWETHStaking PYT

- Cloneable Morpho Aave `0x9db5a6bd77572748e541a0cf42f787f5fe03049e` 
  -> used directly for bb tranche of maUSDC PYT
  - 0x5Ac8094308918C3566330EEAe7cf4becaDACEc3E -> bb tranche of maUSDT PYT
  - 0x37Dd9A73a84bb0EF562C17b3f7aD34001FEdAf38 -> bb tranche of maDAI PYT
  - 0x9750c398993862Ebc9C5A30a9F8Be78Daa440677 -> bb tranche of maWETH PYT

## Install

`forge install`

## Tests
run tests with the pinned block (although this should not be strictly required):

`forge test --fork-url https://eth-mainnet.alchemyapi.io/v2/$ALCHEMY_API_KEY --fork-block-number 15867256 -vvv`