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

We have deployed 2 test versions of our contracts to Mainnet. You can find those contract address here: TODO

### Deploy Your Own

To deploy a LineFactory you must deploy ModuleFactory, Arbiter, and Oracle contracts as well as know what the [0x protocol ExchangeProxy](https://docs.0x.org/introduction/0x-cheat-sheet#exchange-proxy-addresses) address is for the network you are deploying on.

To deploy a SecuredLine you should call our [LineFactory](https://github.com/debtdao/Line-of-Credit/blob/master/contracts/interfaces/ILineFactory.sol) contract so your Line will automatically be indexed by subgraphs and display on interfaces for lenders to send you offers. There are multiple functions to deploy lines depending on the granularaity and control you want for your terms and conditions.

## Testing

We use foundry for testing. Follow [installation guide](https://github.com/foundry-rs/foundry) on their repo.

Before running tests, make sure the foundry.toml file is correctly configured. Make sure it includes the following:

`[profile.default]
src = 'contracts'
test = 'test'
script = 'scripts'
out = 'out'
libs = [
    
]
remappings = [
    "forge-std/=lib/forge-std/src/",
    "ds-test/=lib/forge-std/lib/ds-test/src/",
    "chainlink/=lib/chainlink/contracts/src/v0.8/",
    "openzeppelin/=lib/openzeppelin-contracts/contracts/"
]
libraries = []`

Check the the .env file includes the following environment variables:

`FOUNDRY_PROFILE=""

MAINNET_ETHERSCAN_API_KEY= <YOUR_KEY_HERE>
DEPLOYER_MAINNET_PRIVATE_KEY= <YOUR_KEY_HERE>
MAINNET_RPC_URL= <YOUR_RPC_URL_HERE>

GOERLI_RPC_URL= <YOUR_GOERLI_RPC_URL_HERE>
GOERLI_PRIVATE_KEY= <YOUR_GOERLI_PRIVATE_KEY_HERE>

LOCAL_RPC_URL='http://localhost:8545'
LOCAL_PRIVATE_KEY= <LOCAL_PRIVATE_KEY_HERE>`

Then run `forge test`

Run all tests with maximum logging:
`forge test -vvv`

Test individual test files:
`forge test —match-path <filepath>`

Test individual tests:
`forge test —match-test <testname>`

Check test coverage:
`forge coverage`

## Deployment
For all deployments, the `deploy.sh` script can be modified to deploy all libraries and modules necessary to create Lines of Credit. To run the script, you will need the `jq` library which can be installed usng homebrew(mac) or apt-get(Windows). You can uncomment the command for your OS in the script to install automatically.

There are 4 variables that will need to be adjusted depening on if you are deploying to local, goerli or mainnet. RPC_URL, PRIVATE_KEY and the toml profile that the script will write the libraries to. These  variables are in `deploy.sh`. The 4th variable will be  in your `.env` file and is the FOUNDRY_PROFILE environment variable.  


### Local

### Goerli
