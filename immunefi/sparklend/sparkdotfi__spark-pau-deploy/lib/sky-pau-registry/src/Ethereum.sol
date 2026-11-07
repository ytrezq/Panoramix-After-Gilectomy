// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

library Ethereum {

    /*******************************************************************************************************************

    ███████╗██╗  ██╗██╗   ██╗     █████╗ ██╗   ██╗████████╗██╗  ██╗ ██████╗ ██████╗ ███████╗██████╗ 
    ██╔════╝██║ ██╔╝╚██╗ ██╔╝    ██╔══██╗██║   ██║╚══██╔══╝██║  ██║██╔═══██╗██╔══██╗██╔════╝██╔══██╗
    ███████╗█████╔╝  ╚████╔╝     ███████║██║   ██║   ██║   ███████║██║   ██║██████╔╝█████╗  ██║  ██║
    ╚════██║██╔═██╗   ╚██╔╝      ██╔══██║██║   ██║   ██║   ██╔══██║██║   ██║██╔══██╗██╔══╝  ██║  ██║
    ███████║██║  ██╗   ██║       ██║  ██║╚██████╔╝   ██║   ██║  ██║╚██████╔╝██║  ██║███████╗██████╔╝
    ╚══════╝╚═╝  ╚═╝   ╚═╝       ╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═════╝ 

    /******************************************************************************************************************/
    /*** SKY PAU Core                                                                                               ***/
    /******************************************************************************************************************/

    address internal constant BEACON                     = 0x829dC2b7E94B1954F0764E573f2E0d45Afa28199;
    address internal constant PAU_FACTORY                = 0x69A5d548830AC2A4Ba90A44a2C75BDA71f97fc66;
    address internal constant ADMINISTERED_AGENT_FACTORY = 0x2968c3b5478cF93B70aB1e24255d4EDBBd27a089;
    address internal constant DEFAULT_PAU_ASSEMBLER      = 0xc812aAD3FaE2D3511C664374B601a9BeBFeCCa2E;

    /******************************************************************************************************************/
    /*** SKY PAU Facets                                                                                             ***/
    /******************************************************************************************************************/

    address internal constant AAVE_FACET           = 0x8CE890A96a193ff2DD4B2eA3C682326F655f6b62;
    address internal constant BASIN_FACET          = 0xC84825BCD13AEddc372400239499380376a44A39;
    address internal constant CCTP_FACET           = 0xADf62692340e46EF90336f2e75ce3b37f1148873;
    address internal constant CENTRIFUGE_FACET     = 0xa0A10BA97be1412730D694B8dE1afe7eff20eC31;
    address internal constant CURVE_FACET          = 0x139D81d7d6040fAeF7cF0EF5A2636Ca8a97a30d8;
    address internal constant DAIUSDS_FACET        = 0x3817F734CAe6AD2BDb79F9ff23091F2AD478da5F;
    address internal constant ERC4626_FACET        = 0x1dCA18608c89174181153E786778705b4A0E1a06;
    address internal constant ERC7540_FACET        = 0x4f7e0E3612b0e1E156A2B6570a51d4BD709F1315;
    address internal constant ETHENA_FACET         = 0xEc48D773CEef1c6b07CdA1afA2716C478b55187B;
    address internal constant FARM_FACET           = 0xF24E91f5D8529436c9fB92dd94F80d4A6C25d0f0;
    address internal constant LAYER_ZERO_FACET     = 0xA0c323a0acb20F259eA4ff343319D450BE6472e5;
    address internal constant MAPLE_FACET          = 0x691b5c26aD2B74d2376f4eD87904E9D3E47bD630;
    address internal constant MERKL_FACET          = 0x321138Db5E056e9d0080D4c278e10A1EdC091Eb0;
    address internal constant OTC_FACET            = 0x46b24ba00B65CB4f603447590e539b08097fb7Ac;
    address internal constant PENDLE_FACET         = 0xcC9dD4c9B2a9c08f2692e7060F43d29A03E87348;
    address internal constant PSM_FACET            = 0xE4A5dAc768a310cc2316f258901b32E499653064;
    address internal constant SPARK_VAULT_FACET    = 0xff0d19920E207e3A17eb5A2E5bA3AFA44836362b;
    address internal constant SUPERSTATE_FACET     = 0xeE197475607E9a27cCAA4786e740d2F0d0E706A7;
    address internal constant TRANSFER_ASSET_FACET = 0x4DA7608C331b8f135df5b985018933780eCd089D;
    address internal constant UNISWAP_V3_FACET     = 0x445D9Dc752F269Be48250f1A180CAC4c61cE4bab;
    address internal constant UNISWAP_V4_FACET     = 0x75D35ffB8e6B871E12EB549CcF6afD324c46E47D;
    address internal constant USDS_FACET           = 0x1221CC4B85Ab260660aD21C2829e0EB516dffBc7;
    address internal constant WEETH_FACET          = 0x1d8D089EB7D558F5dc6aA0cf98DDe13B77b3F641;
    address internal constant WRAP_PROXY_ETH_FACET = 0x081506DE21C695Af5e61a81aD288C8A96B6b59B9;
    address internal constant WSTETH_FACET         = 0x3a82D11Cd37Fb0098363262Dc69425d07Fa05516;

}
