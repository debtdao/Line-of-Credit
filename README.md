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
[Testnet Deployments Addresses](https://near-diploma-a92.notion.site/Deployed-Verified-Contracts-4717a0e2b231459e891e7e4565ec4e81)
Mainnet Deployments Addresses - N/A

To deploy a SecuredLine you should call our [LineFactory](https://github.com/debtdao/Line-of-Credit/blob/master/contracts/interfaces/ILineFactory.sol) contract so your Line will automatically be indexed by subgraphs and display on interfaces for lenders to send you offers. There are multiple functions to deploy lines depending on the granularaity and control you want for your terms and conditions.

To deploy a LineFactory you must deploy ModuleFactory, Arbiter, and Oracle contracts as well as know what the [0x protocol ExchangeProxy](https://docs.0x.org/introduction/0x-cheat-sheet#exchange-proxy-addresses) address is for the network you are deploying on.



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
