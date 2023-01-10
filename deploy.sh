#!/bin/bash

# make sure the libraries array in the toml file looks like this 'libraries = []' with no spaces inside the brackets

# for mac, install jq with brew
brew install jq

# for linux, install jq with apt-get
# sudo apt-get install jq

# for windows, install jq with chocolatey
# chocolatey install jq

### DEPLOY LIBS ###

source .env

LineLib=$(forge create --rpc-url $GOERLI_RPC_URL --private-key $GOERLI_PRIVATE_KEY --etherscan-api-key $MAINNET_ETHERSCAN_API_KEY  contracts/utils/LineLib.sol:LineLib --json --verify)
LineLibAddress=$(echo "$LineLib" | jq -r '.deployedTo')
LineLibEntry="contracts\/utils\/LineLib.sol:LineLib:$LineLibAddress"

sed -i '' '/\[profile\.goerli\]/,/^\[/s/^libraries = \[.*\]/libraries = \["'$LineLibEntry'"\]/' foundry.toml

source .env

CreditLib=$(forge create --rpc-url $GOERLI_RPC_URL --private-key $GOERLI_PRIVATE_KEY --etherscan-api-key $MAINNET_ETHERSCAN_API_KEY contracts/utils/CreditLib.sol:CreditLib --verify --json)
CreditLibAddress=$(echo "$CreditLib" | jq -r '.deployedTo')
CreditLibEntry="contracts\/utils\/CreditLib.sol:CreditLib:$CreditLibAddress"
sed -i '' '/\[profile\.goerli\]/,/^\[/s/^libraries = \["'$LineLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'"\]/' foundry.toml

source .env

CreditListLib=$(forge create --rpc-url $GOERLI_RPC_URL --private-key $GOERLI_PRIVATE_KEY --etherscan-api-key $MAINNET_ETHERSCAN_API_KEY contracts/utils/CreditListLib.sol:CreditListLib --verify --json)
CreditListLibAddress=$(echo "$CreditListLib" | jq -r '.deployedTo')
CreditListLibEntry="contracts\/utils\/CreditListLib.sol:CreditListLib:$CreditListLibAddress"

sed -i '' '/\[profile\.goerli\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'"\]/' foundry.toml

source .env

SpigotLib=$(forge create --rpc-url $GOERLI_RPC_URL --private-key $GOERLI_PRIVATE_KEY --etherscan-api-key $MAINNET_ETHERSCAN_API_KEY contracts/utils/SpigotLib.sol:SpigotLib --verify --json)
SpigotLibAddress=$(echo "$SpigotLib" | jq -r '.deployedTo')
SpigotLibEntry="contracts\/utils\/SpigotLib.sol:SpigotLib:$SpigotLibAddress"

sed -i '' '/\[profile\.goerli\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'"\]/' foundry.toml

source .env

EscrowLib=$(forge create --rpc-url $GOERLI_RPC_URL --private-key $GOERLI_PRIVATE_KEY --etherscan-api-key $MAINNET_ETHERSCAN_API_KEY contracts/utils/EscrowLib.sol:EscrowLib --verify --json)
EscrowLibAddress=$(echo "$EscrowLib" | jq -r '.deployedTo')
EscrowLibEntry="contracts\/utils\/EscrowLib.sol:EscrowLib:$EscrowLibAddress"

sed -i '' '/\[profile\.goerli\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'"\]/' foundry.toml

source .env

SpigotedLineLib=$(forge create --rpc-url $GOERLI_RPC_URL --private-key $GOERLI_PRIVATE_KEY --etherscan-api-key $MAINNET_ETHERSCAN_API_KEY contracts/utils/SpigotedLineLib.sol:SpigotedLineLib --verify --json)
SpigotedLineLibAddress=$(echo "$SpigotedLineLib" | jq -r '.deployedTo')
SpigotedLineLibEntry="contracts\/utils\/SpigotedLineLib.sol:SpigotedLineLib:$SpigotedLineLibAddress"

sed -i '' '/\[profile\.goerli\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'","'$SpigotedLineLibEntry'"\]/' foundry.toml

# source .env

# LineFactoryLib=$(forge create --rpc-url $GOERLI_RPC_URL --private-key $GOERLI_PRIVATE_KEY --etherscan-api-key $MAINNET_ETHERSCAN_API_KEY contracts/utils/LineFactoryLib.sol:LineFactoryLib --verify --json)
# LineFactoryLibAddress=$(echo "$LineFactoryLib" | jq -r '.deployedTo')
# LineFactoryLibEntry="contracts\/utils\/LineFactoryLib.sol:LineFactoryLib:$LineFactoryLibAddress"

# sed -i '' '/\[profile\.goerli\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'","'$SpigotedLineLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'","'$SpigotedLineLibEntry'","'$LineFactoryLibEntry'"\]/' foundry.toml


### DEPLOY FACTORY MODULES ###

# source .env

# ModuleFactory=$(forge create --rpc-url $GOERLI_RPC_URL --private-key $GOERLI_PRIVATE_KEY --etherscan-api-key $MAINNET_ETHERSCAN_API_KEY contracts/modules/factories/ModuleFactory.sol:ModuleFactory --verify --json)
# ModuleFactoryAddress=$(echo "$ModuleFactory" | jq -r '.deployedTo')
# ModuleFactoryEntry="contracts\/factory\/ModuleFactory.sol:ModuleFactory:$ModuleFactoryAddress"

# sed -i '' '/\[profile\.goerli\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'","'$SpigotedLineLibEntry'","'$LineFactoryLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'","'$SpigotedLineLibEntry'","'$LineFactoryLibEntry'","'$ModuleFactoryEntry'"\]/' foundry.toml

LineFactory=$(forge create --rpc-url $GOERLI_RPC_URL \
--constructor-args 0x70a951E2D2Ee4Fc6D38325AB0e0ED1a789Eb2D8E 0x0325C59BA55F6705C2AC6213628222Cf193d423D 0x7EDe2714Ad78544cb3834a24215Fe5F871ea7B70 0xcb7b9188aDA88Cb0c991C807acc6b44097059DEc \
--private-key $GOERLI_PRIVATE_KEY --etherscan-api-key $MAINNET_ETHERSCAN_API_KEY \
contracts/modules/factories/LineFactory.sol:LineFactory --verify --json)


### DEPLOY ORACLE ###

# SEERO TOKEN ADDRESS: 0x3730954eC1b5c59246C1fA6a20dD6dE6Ef23aEa6
# COL TOKEN ADDRESS: 0x589a0b00a0dD78Fc2C94b8eac676dec4C3Dcd562

# forge create --rpc-url $GOERLI_RPC_URL --constructor-args 0x3730954eC1b5c59246C1fA6a20dD6dE6Ef23aEa6 0x589a0b00a0dD78Fc2C94b8eac676dec4C3Dcd562 \
# --private-key $GOERLI_PRIVATE_KEY --etherscan-api-key $MAINNET_ETHERSCAN_API_KEY  contracts/mock/SimpleOracle.sol:SimpleOracle  --verify

