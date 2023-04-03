#!/bin/bash

# make sure the libraries array in the toml file looks like this 'libraries = []' with no spaces inside the brackets

# use jq to parse API responses
# brew install jq
# apt-get jq

### DEPLOY LIBS ###

source .env

echo "Deploying Debt DAO Libraries and adding addresses to foundry.toml file...."

echo "Deploying LineLib to $GNOSIS_RPC_URL...."
LineLib=$(forge create --chain gnosis --rpc-url $GNOSIS_RPC_URL --verifier-url https://api.gnosisscan.io/api --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $GNOSIS_ETHERSCAN_API_KEY --verifier etherscan contracts/utils/LineLib.sol:LineLib --json --verify)
echo "LineLib deployed $LineLib"
LineLibAddress=$(echo "$LineLib" | jq -r '.deployedTo')
LineLibAddress="0x00A3699F677C252CA32B887F9f66621920D392f8"
LineLibEntry="contracts\/utils\/LineLib.sol:LineLib:$LineLibAddress"
echo "Updating foundry.toml with LineLib address: {$LineLibAddress}...."
sed -i '' '/\[profile\.gnosis\]/,/^\[/s/^libraries = \[.*\]/libraries = \["'$LineLibEntry'"\]/' foundry.toml


echo "Deploying CreditLib...."
CreditLib=$(forge create --chain gnosis --rpc-url $GNOSIS_RPC_URL  --verifier-url https://api.gnosisscan.io/api --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $GNOSIS_ETHERSCAN_API_KEY contracts/utils/CreditLib.sol:CreditLib --verify --json)
echo "CreditLib deployed {$CreditLib}"
CreditLibAddress=$(echo "$CreditLib" | jq -r '.deployedTo')
CreditLibEntry="contracts\/utils\/CreditLib.sol:CreditLib:$CreditLibAddress"
echo "Updating foundry.toml with CreditLib address: {$CreditLibAddress}...."
sed -i '' '/\[profile\.gnosis\]/,/^\[/s/^libraries = \["'$LineLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'"\]/' foundry.toml


echo "Deploying CreditListLib...."
CreditListLib=$(forge create --rpc-url $GNOSIS_RPC_URL  --verifier-url https://api.gnosisscan.io/api --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $GNOSIS_ETHERSCAN_API_KEY contracts/utils/CreditListLib.sol:CreditListLib --verify --json)
echo "CreditListLib deployed {$CreditListLib}"
CreditListLibAddress=$(echo "$CreditListLib" | jq -r '.deployedTo')
CreditListLibEntry="contracts\/utils\/CreditListLib.sol:CreditListLib:$CreditListLibAddress"
echo "Updating foundry.toml with CreditListLib address: {$CreditListLibAddress}...."
sed -i '' '/\[profile\.gnosis\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'"\]/' foundry.toml


echo "Deploying SpigotLib...."
SpigotLib=$(forge create --chain gnosis --rpc-url $GNOSIS_RPC_URL  --verifier-url https://api.gnosisscan.io/api --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $GNOSIS_ETHERSCAN_API_KEY contracts/utils/SpigotLib.sol:SpigotLib --verify --json)
echo "SpigotLib deployed {$SpigotLib}"
SpigotLibAddress=$(echo "$SpigotLib" | jq -r '.deployedTo')
SpigotLibEntry="contracts\/utils\/SpigotLib.sol:SpigotLib:$SpigotLibAddress"
echo "Updating foundry.toml with SpigotLib address: {$SpigotLibAddress}...."
sed -i '' '/\[profile\.gnosis\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'"\]/' foundry.toml


echo "Deploying EscrowLib...."
EscrowLib=$(forge create --chain gnosis --rpc-url $GNOSIS_RPC_URL  --verifier-url https://api.gnosisscan.io/api --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $GNOSIS_ETHERSCAN_API_KEY contracts/utils/EscrowLib.sol:EscrowLib --verify --json)
echo "EscrowLib deployed {$EscrowListLib}"
EscrowLibAddress=$(echo "$EscrowLib" | jq -r '.deployedTo')
EscrowLibEntry="contracts\/utils\/EscrowLib.sol:EscrowLib:$EscrowLibAddress"
echo "Updating foundry.toml with EscrowLib address: {$EscrowListLibAddress}...."
sed -i '' '/\[profile\.gnosis\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'"\]/' foundry.toml


echo "Deploying SpigotedLineLib...."
SpigotedLineLib=$(forge create --chain gnosis --rpc-url $GNOSIS_RPC_URL  --verifier-url https://api.gnosisscan.io/api --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $GNOSIS_ETHERSCAN_API_KEY contracts/utils/SpigotedLineLib.sol:SpigotedLineLib --verify --json)
echo "SpigotedLineLib deployed {$SpigotedLineListLib}"
SpigotedLineLibAddress=$(echo "$SpigotedLineLib" | jq -r '.deployedTo')
SpigotedLineLibEntry="contracts\/utils\/SpigotedLineLib.sol:SpigotedLineLib:$SpigotedLineLibAddress"
echo "Updating foundry.toml with SpigotedLineLib address: {$SpigotedLineListLibAddress}...."
sed -i '' '/\[profile\.gnosis\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'","'$SpigotedLineLibEntry'"\]/' foundry.toml


echo "Deploying LineFactoryLib...."
LineFactoryLib=$(forge create --chain gnosis --rpc-url $GNOSIS_RPC_URL  --verifier-url https://api.gnosisscan.io/api --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $GNOSIS_ETHERSCAN_API_KEY contracts/utils/LineFactoryLib.sol:LineFactoryLib --verify --json)
echo "LineFactoryLib deployed {$LineFactoryLib}"
LineFactoryLibAddress=$(echo "$LineFactoryLib" | jq -r '.deployedTo')
echo "Updating foundry.toml with LineFactoryLib address: {$LineFactoryLibAddress}...."
LineFactoryLibEntry="contracts\/utils\/LineFactoryLib.sol:LineFactoryLib:$LineFactoryLibAddress"
sed -i '' '/\[profile\.gnosis\]/,/^\[/s/^libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'","'$SpigotedLineLibEntry'"\]/libraries = \["'$LineLibEntry'","'$CreditLibEntry'","'$CreditListLibEntry'","'$SpigotLibEntry'","'$EscrowLibEntry'","'$SpigotedLineLibEntry'","'$LineFactoryLibEntry'"\]/' foundry.toml


### DEPLOY Mock Tokens & Oracle for testing ###

# echo "Deploying DummyToken1...."
# DummyToken1=$(forge create --chain gnosis --rpc-url $GNOSIS_RPC_URL  --verifier-url https://api.gnosisscan.io/api --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $GNOSIS_ETHERSCAN_API_KEY contracts/mock/RevenueToken.sol:RevenueToken --verify --json)
# echo "DummyToken1 deployed {$DummyToken1}"
# DummyToken1Address=$(echo "$DummyToken1" | jq -r '.deployedTo')
# echo "Updating foundry.toml with DummyToken1 address: {$DummyToken1Address}...."

# echo "Deploying DummyToken2...."
# DummyToken2=$(forge create --chain gnosis --rpc-url $GNOSIS_RPC_URL  --verifier-url https://api.gnosisscan.io/api --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $GNOSIS_ETHERSCAN_API_KEY contracts/mock/RevenueToken.sol:RevenueToken --verify --json)
# echo "DummyToken2 deployed {$DummyToken2}"
# DummyToken2Address=$(echo "$DummyToken2" | jq -r '.deployedTo')
# echo "Updating foundry.toml with DummyToken2 address: {$DummyToken2Address}...."

# DummyToken1Address=0x010E663F9510a032E1F403f2c9de28f40d3949B8
# DummyToken2Address=0x9E3e3FB5597006AfD7C1EB8D29986211b1D8D172

# echo "Deploying Oracle...."
# Oracle=$(forge create --constructor-args $DummyToken1Address $DummyToken2Address --chain gnosis --rpc-url $GNOSIS_RPC_URL  --verifier-url https://api.gnosisscan.io/api --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $GNOSIS_ETHERSCAN_API_KEY contracts/mock/SimpleOracle.sol:SimpleOracle --verify --json)
# echo "Oracle deployed {$Oracle}"
# OracleAddress=$(echo "$Oracle" | jq -r '.deployedTo')
# echo "Updating foundry.toml with Oracle address: {$OracleAddress}...."


### DEPLOY FACTORY CONTRACTS ###

# use multicall as swap target on chains without 0x support
echo "Deploying Multicall...."
Multicall=$(forge create --chain gnosis --rpc-url $GNOSIS_RPC_URL --verifier-url https://api.gnosisscan.io/api --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $GNOSIS_ETHERSCAN_API_KEY contracts/utils/Multicall.sol:Multicall3 --verify --json)
MulticallAddress=$(echo "$Multicall" | jq -r '.deployedTo')
echo "Multicall contract deployed to address: {$MulticallAddress}...."

echo "Deploying ModuleFactory...."
ModuleFactory=$(forge create --chain gnosis --rpc-url $GNOSIS_RPC_URL --verifier-url https://api.gnosisscan.io/api --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $GNOSIS_ETHERSCAN_API_KEY contracts/modules/factories/ModuleFactory.sol:ModuleFactory --verify --json)
ModuleFactoryAddress=$(echo "$ModuleFactory" | jq -r '.deployedTo')
echo "ModuleFactory contract deployed to address: {$ModuleFactoryAddress}...."

echo "Deploying LineFactory...."
SwapTargetAddress=$MulticallAddress # alias to semantic name
ArbiterAddress=0x2e1b9B77692D662AF998e98666908BA80Fb8018E # our multisig
LineFactory=$(forge create --chain gnosis --rpc-url $GNOSIS_RPC_URL --verifier-url https://api.gnosisscan.io/api \
    --constructor-args $ModuleFactoryAddress $ArbiterAddress $OracleAddress $SwapTargetAddress \
    --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $GNOSIS_ETHERSCAN_API_KEY \
    contracts/modules/factories/LineFactory.sol:LineFactory --verify --json)
echo "LineFactory deployed {$LineFactory}"


### DEPLOY ORACLE ###

# SEERO TOKEN ADDRESS: 0x3730954eC1b5c59246C1fA6a20dD6dE6Ef23aEa6
# COL TOKEN ADDRESS: 0x589a0b00a0dD78Fc2C94b8eac676dec4C3Dcd562

# forge create --chain gnosis --rpc-url $GNOSIS_RPC_URL --constructor-args 0x3730954eC1b5c59246C1fA6a20dD6dE6Ef23aEa6 0x589a0b00a0dD78Fc2C94b8eac676dec4C3Dcd562 \
# --private-key $DEPLOYER_PRIVATE_KEY --etherscan-api-key $GNOSIS_ETHERSCAN_API_KEY  contracts/mock/SimpleOracle.sol:SimpleOracle  --verify


### DEPLOY REV CONTRACT ###

# forge create --chain gnosis --rpc-url $GNOSIS_RPC_URL --constructor-args 0xf44B95991CaDD73ed769454A03b3820997f00873 0x589a0b00a0dD78Fc2C94b8eac676dec4C3Dcd562 \
#  --private-key $GOERLI_PRIVATE_KEY --etherscan-api-key $GNOSIS_ETHERSCAN_API_KEY contracts/mock/SimpleRevenueContract.sol:SimpleRevenueContract --verify

