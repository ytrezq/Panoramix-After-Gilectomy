# Certora Guide

This README describes how to run the specification defined in this repository via Certora.

## Setup

For installation locally please follow the instructions in the official certora documentation [here](https://docs.certora.com/en/latest/docs/user-guide/getting-started/install.html).

Steps include:
- Installing the prerequisites python, java and the solidity compiler
- Installing the Certora Prover python package
- Setting the premium key environment variable (optional)
- Adding the solc binary to your PATH (optional)
- Installing the certora VS code extensions (optional)

Note a key is obtained via signing up with Certora directly but you can also run without a premium key, however, the compute resources are limited.

## Run the spec

cd into the root directory of the project and run the following command:

```sh
make verify
```

## Final Report

The final report for the post audited code can be found [here](https://prover.certora.com/output/9724/485613c8ff4e48af94d4b995a07d1684?anonymousKey=609b8235ddffb93f8f82f59d16cbf3e177530fa9).
