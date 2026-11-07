# yYB

Yearn Finance Liquid locker for Yield Basis (YB).

## Architecture

- **Locker** - Holds veYB position and executes arbitrary calls
- **Operator** - Manages and authenticates all Locker actions
- **YToken** - Liquid ERC20 (1:1 backed by max-locked YB)

## Testing

```bash
MAINNET_RPC_URL=<your-rpc> forge test
```
