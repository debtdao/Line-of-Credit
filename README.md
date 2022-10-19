## Documentation Site
We have comprehensive docs on our site 
https://docs.debtdao.finance/developers/architecture

## Installing
We track remote remotes like Foundry and Chainlink via submodules so you will need to install those in addition to our repo itself
If cloning you can run `git clone --recurse-submodules`
Or if you already have repo installed you can run `git pull --recurse-submodules`

We are still in the process of migrating from hardhat to forge so there are some library dependencies to install via npm. 
Run `yarn install` to download the Chainlink and OpenZeppelin libraries.


## Testing
We use foundry for testing. Follow [installation guide](https://github.com/foundry-rs/foundry) on their repo.

Then run `forge test`
