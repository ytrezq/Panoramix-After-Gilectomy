# Eventemitter

This contract is copied here from the [balancer subgraph repo](https://github.com/balancer/balancer-subgraph-v2/blob/master/curation-contracts/EventEmitter.sol)

The goal of this contract is to send events that can be picked up by subgraphs in order to faciliate operational tasks.

Deployed [here](https://sonicscan.org/address/0xe0F1dfAe777bB7D44d3cb7D8FCDce6731165211E#writeContract)

## Event identifiers and signatures

| Name                 | Identifier                                                         | Message                                                           | Value                                                                    | Description                                                                                  |
| -------------------- | ------------------------------------------------------------------ | ----------------------------------------------------------------- | ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------- |
| setPreferentialGauge | 0x88aea7780a038b8536bb116545f59b8a089101d5e526639d3c54885508ce50e2 | The gauge address (eg. 0x12345abce... - all lowercase)            | 0 if prefentialGauge is to be set false; any other value sets it to true | Will set or unset preferential gauges                                                        |
| setGaugeRewardsData  | 0x94e5a0dff823a8fce9322f522279854e2370a9ef309a74a7a86367e2a2872b2d | The gauge address (eg. 0x12345abce... - all lowercase)            | 0x0                                                                      | Will reload the rewards data for a gauge as the gauge doesnt emit events on reward token add |
| setGaugeInjector     | 0x109783b117ecbf8caf4e937abaf494b965e5d90c4d1b010b27eb2a3be80eaf21 | The GaugeInjector address (eg. 0x12345abce... - all lowercase)the | 0x0                                                                      | Need to add injectors so new injections are picked up properly                               |

Owned by the Gauge and LM Msig: 0x97079F7E04B535FE7cD3f972Ce558412dFb33946
