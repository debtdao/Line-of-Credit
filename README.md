## Documentation Site

We have comprehensive docs on our site
https://docs.debtdao.finance/developers/architecture

## Installing

We track remote remotes like Foundry and Chainlink via submodules so you will need to install those in addition to our repo itself

If you have forge installed already you can run `forge install`

Alternatively using just git
When cloning you can run `git clone --recurse-submodules`
Or if you already have repo installed you can run `git pull --recurse-submodules`

## Deploying

### Testnet Deployments

We have deployed contracts to Gõrli testnet.
[All deployed contract addresses including libraries and mock contracts](https://near-diploma-a92.notion.site/Deployed-Verified-Contracts-4717a0e2b231459e891e7e4565ec4e81)

[List of tokens that are priced by our dummy oracle](https://near-diploma-a92.notion.site/Test-Tokens-10-17-2afd16dde17c45eeba14b780d58ba28b) that you can use for interacting with Line Of Credit and Escrow contracts (you can use any token for Spigot revenue as long as it can be traded to a whitelisted token)

### Mainnet Deploymetns

N/A. We have not deployed to mainnet yet

### Deploy Your Own

To deploy a LineFactory you must deploy ModuleFactory, Arbiter, and Oracle contracts as well as know what the [0x protocol ExchangeProxy](https://docs.0x.org/introduction/0x-cheat-sheet#exchange-proxy-addresses) address is for the network you are deploying on.

To deploy a SecuredLine you should call our [LineFactory](https://github.com/debtdao/Line-of-Credit/blob/master/contracts/interfaces/ILineFactory.sol) contract so your Line will automatically be indexed by subgraphs and display on interfaces for lenders to send you offers. There are multiple functions to deploy lines depending on the granularaity and control you want for your terms and conditions.

## Testing

We use foundry for testing. Follow [installation guide](https://github.com/foundry-rs/foundry) on their repo.

Then run `forge test`

## Failing Tests

Test `test_can_trade` and `test_can_trade_and_reapy` fail occasionally, with inconsequential parameter inputs.

```
Failing tests:
Encountered 1 failing test in contracts/tests/SpigotedLine.t.sol:SpigotedLineTest
[FAIL. Reason: TradeFailed() Counterexample: calldata=0xd9be461e0000000000000000000000000000000000000000000000000000000000000001004189374bc6a7ef9db22d0e5604189374bc6a7ef9db22d0e5604189374bc6a8, args=[1, 115792089237316195423570985008687907853269984665640564039457584007913129640]] test_can_trade(uint256,uint256) (runs: 205, μ: 243309, ~: 283578)
```

## Deployment

### Local

```
source .env && forge script contracts/scripts/DeployLocal.s.sol -vvvv --rpc-url http://127.0.0.1:8545 --broadcast
```

### Goerli

```
source .env && forge script contracts/scripts/DeployGoerli.s.sol -vvvv --rpc-url $GOERLI_RPC_URL --verify --etherscan-api-key $GOERLI_ETHERSCAN_API_KEY --broadcast
```

If verification fails:

```
source .env && forge script contracts/scripts/DeployGoerli.s.sol -vvv --rpc-url $GOERLI_RPC_URL --verify --etherscan-api-key $GOERLI_ETHERSCAN_API_KEY --resume
```
