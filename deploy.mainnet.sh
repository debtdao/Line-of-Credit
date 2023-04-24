#!/bin/bash

# make sure the libraries array in the toml file looks like this 'libraries = []' with no spaces inside the brackets

# use jq to parse API responses
# brew install jq
# apt-get jq

### DEPLOY LIBS ###

source .env

echo "Deploying Debt DAO Libraries and adding addresses to foundry.toml file...."

echo "Deploying LineLib to $MAINNET_RPC_URL...."
LineLib=$(forge create --rpc-url $MAINNET_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY \
    contracts/utils/LineLib.sol:LineLib --json --verify)
    # --optimzer-runs 20000 \
echo "LineLib deployed $LineLib"
LineLibAddress=$(echo "$LineLib" | jq -r '.deployedTo')
LineLibEntry="contracts\/utils\/LineLib.sol:LineLib:$LineLibAddress"
echo "Updating foundry.toml with LineLib address: {$LineLibAddress}...."
sed -i '' '/\[profile\.mainnet\]/,/^\[/s/^libraries = \[.*\]/libraries = \["'$LineLibEntry'"\]/' foundry.toml


echo "Deploying CreditLib...."
CreditLib=$(forge create --rpc-url $MAINNET_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY \
    contracts/utils/CreditLib.sol:CreditLib --verify --json)
    # --optimzer-runs 20000 \
echo "CreditLib deployed {$CreditLib}"
CreditLibAddress=$(echo "$CreditLib" | jq -r '.deployedTo')
CreditLibEntry="contracts\/utils\/CreditLib.sol:CreditLib:$CreditLibAddress"
echo "Updating foundry.toml with CreditLib address: {$CreditLibAddress}...."
sed -i '' '/\[profile\.mainnet\]/,/^\[/s/^libraries = \["'$LineLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'"\]/' foundry.toml


echo "Deploying CreditListLib...."
CreditListLib=$(forge create --rpc-url $MAINNET_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY \
    contracts/utils/CreditListLib.sol:CreditListLib --verify --json)
    # --optimzer-runs 20000 \
echo "CreditListLib deployed {$CreditListLib}"
CreditListLibAddress=$(echo "$CreditListLib" | jq -r '.deployedTo')
CreditListLibEntry="contracts\/utils\/CreditListLib.sol:CreditListLib:$CreditListLibAddress"
echo "Updating foundry.toml with CreditListLib address: {$CreditListLibAddress}...."
sed -i '' '/\[profile\.mainnet\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'"\]/' foundry.toml


echo "Deploying SpigotLib...."
SpigotLib=$(forge create --rpc-url $MAINNET_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY \
    contracts/utils/SpigotLib.sol:SpigotLib --verify --json)
    # --optimzer-runs 20000 \
echo "SpigotLib deployed {$SpigotLib}"
SpigotLibAddress=$(echo "$SpigotLib" | jq -r '.deployedTo')
SpigotLibEntry="contracts\/utils\/SpigotLib.sol:SpigotLib:$SpigotLibAddress"
echo "Updating foundry.toml with SpigotLib address: {$SpigotLibAddress}...."
sed -i '' '/\[profile\.mainnet\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'"\]/' foundry.toml


echo "Deploying EscrowLib...."
EscrowLib=$(forge create --rpc-url $MAINNET_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY \
    contracts/utils/EscrowLib.sol:EscrowLib --verify --json)
    # --optimzer-runs 20000 \
echo "EscrowLib deployed {$EscrowListLib}"
EscrowLibAddress=$(echo "$EscrowLib" | jq -r '.deployedTo')
EscrowLibEntry="contracts\/utils\/EscrowLib.sol:EscrowLib:$EscrowLibAddress"
echo "Updating foundry.toml with EscrowLib address: {$EscrowListLibAddress}...."
sed -i '' '/\[profile\.mainnet\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'"\]/' foundry.toml


echo "Deploying SpigotedLineLib...."
SpigotedLineLib=$(forge create --rpc-url $MAINNET_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY \
    contracts/utils/SpigotedLineLib.sol:SpigotedLineLib --verify --json)
    # --optimzer-runs 20000 \
echo "SpigotedLineLib deployed {$SpigotedLineListLib}"
SpigotedLineLibAddress=$(echo "$SpigotedLineLib" | jq -r '.deployedTo')
SpigotedLineLibEntry="contracts\/utils\/SpigotedLineLib.sol:SpigotedLineLib:$SpigotedLineLibAddress"
echo "Updating foundry.toml with SpigotedLineLib address: {$SpigotedLineListLibAddress}...."
sed -i '' '/\[profile\.mainnet\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'","'$SpigotedLineLibEntry'"\]/' foundry.toml

# NOTE:  change optimizer runs to like 200 here so that each new contract deployed is hella cheap
echo "Deploying LineFactoryLib...."
LineFactoryLib=$(forge create --rpc-url $MAINNET_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY \
    contracts/utils/LineFactoryLib.sol:LineFactoryLib --verify --json)
    # --optimzer-runs 200 \
echo "LineFactoryLib deployed {$LineFactoryLib}"
LineFactoryLibAddress=$(echo "$LineFactoryLib" | jq -r '.deployedTo')
echo "Updating foundry.toml with LineFactoryLib address: {$LineFactoryLibAddress}...."
LineFactoryLibEntry="contracts\/utils\/LineFactoryLib.sol:LineFactoryLib:$LineFactoryLibAddress"
sed -i '' '/\[profile\.mainnet\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'","'$SpigotedLineLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'","'$SpigotedLineLibEntry'","'$LineFactoryLibEntry'"\]/' foundry.toml


### DEPLOY FACTORY CONTRACTS ###

# TODO want to change optimizer runs to like 200 here so that each new contract deployed is hella cheap
echo "Deploying ModuleFactory...."
ModuleFactory=$(forge create --rpc-url $MAINNET_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY \
    contracts/modules/factories/ModuleFactory.sol:ModuleFactory --verify --json)
    # --optimzer-runs 10000 \
ModuleFactoryAddress=$(echo "$ModuleFactory" | jq -r '.deployedTo')
echo "ModuleFactory contract deployed to address: {$ModuleFactoryAddress}...."

# TODO want to change optimizer runs to like 20000 here so that each new contract deployed is hella cheap
echo "Deploying LineFactory...."
ModuleFactoryAddress=0x00A3699F677C252CA32B887F9f66621920D392f8 # copy from deployment above after changing optimizer runs
ArbiterAddress=0x1E73ADD2B1cd5152217B0A9B6eA58764a6d97FC1       # our multisig
OracleAddress=0x5a4AAF300473eaF8A9763318e7F30FA8a3f5Dd48        # OG wrapper oracle deployment 
SwapTargetAddress=0xDef1C0ded9bec7F1a1670819833240f027b25EfF    # 0x exchange
LineFactory=$(forge create --rpc-url $MAINNET_RPC_URL \
    --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY \
    --constructor-args $ModuleFactoryAddress $ArbiterAddress $OracleAddress $SwapTargetAddress \
    --verify --json contracts/modules/factories/LineFactory.sol:LineFactory)
    # --optimzer-runs 10000 \
echo "LineFactory deployed {$LineFactory}"


### DEPLOY ORACLE ###

# SEERO TOKEN ADDRESS: 0x3730954eC1b5c59246C1fA6a20dD6dE6Ef23aEa6
# COL TOKEN ADDRESS: 0x589a0b00a0dD78Fc2C94b8eac676dec4C3Dcd562

# forge create --rpc-url $MAINNET_RPC_URL --constructor-args 0x3730954eC1b5c59246C1fA6a20dD6dE6Ef23aEa6 0x589a0b00a0dD78Fc2C94b8eac676dec4C3Dcd562 \
# --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY  contracts/mock/SimpleOracle.sol:SimpleOracle  --verify


### DEPLOY REV CONTRACT ###

# forge create --rpc-url $MAINNET_RPC_URL --constructor-args 0xf44B95991CaDD73ed769454A03b3820997f00873 0x589a0b00a0dD78Fc2C94b8eac676dec4C3Dcd562 \
#  --private-key $GOERLI_PRIVATE_KEY --etherscan-api-key $ETHERSCAN_API_KEY contracts/mock/SimpleRevenueContract.sol:SimpleRevenueContract --verify

