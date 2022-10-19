## Documentation Site

We have comprehensive docs on our site
https://docs.debtdao.finance/developers/architecture

## Installing

We track remote remotes like Foundry and Chainlink via submodules so you will need to install those in addition to our repo itself
If cloning you can run `git clone --recurse-submodules`
Or if you already have repo installed you can run `git pull --recurse-submodules`


## Testing

We use foundry for testing. Follow [installation guide](https://github.com/foundry-rs/foundry) on their repo.

Then run `forge test`

## Failing Tests

Test `TradeFailed` fails occasionally.

```
Failing tests:
Encountered 1 failing test in contracts/tests/SpigotedLine.t.sol:SpigotedLineTest
[FAIL. Reason: TradeFailed() Counterexample: calldata=0xd9be461e0000000000000000000000000000000000000000000000000000000000000001004189374bc6a7ef9db22d0e5604189374bc6a7ef9db22d0e5604189374bc6a8, args=[1, 115792089237316195423570985008687907853269984665640564039457584007913129640]] test_can_trade(uint256,uint256) (runs: 205, μ: 243309, ~: 283578)
```
