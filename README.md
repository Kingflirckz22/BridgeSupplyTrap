# BridgeSupplyTrap
BridgeSupplyTrap

This repository contains a Drosera-powered trap designed to detect anomalous supply increases in bridged tokens. A sudden, large increase in the totalSupply() of a bridged asset (e.g., USDC.e, WETH.e) is a critical red flag for a bridge exploit or an infinite mint bug. This trap monitors the totalSupply over a window of blocks to catch such anomalies.

How It Works

The system uses two contracts and the AVS-style statistical analysis pattern, where data is collected over time and analyzed with a pure function.

BridgeSupplyTrap.sol: This is the ITrap implementation.

collect(): This view function is called by Drosera operators. It reads the targetBridgedToken address, its current totalSupply(), and the maxSupplyIncrease threshold from its own state. It ABI-encodes all three values into a SupplyData struct and returns the raw bytes.

shouldRespond(bytes[] calldata data): This pure function receives an array of bytes from the collect() calls. It decodes the latest packet (data[0]) and the oldest packet (data[data.length - 1]). If the supply increase between them exceeds the threshold, it returns true and the response payload.

BridgeSupplyResponse.sol: This is the response contract.

respondWithSupplyAlert(address,uint256,uint256): When the trap triggers, the Drosera network calls this function. It emits a BridgeSupplyAlert event, which can be monitored by other protocols, dashboards, or alerting systems.

drosera.toml Configuration

Here is an example drosera.toml file to run an operator for this trap. You must deploy your contracts first and fill in the addresses.

ethereum_rpc = "[https://ethereum-hoodi-rpc.publicnode.com](https://ethereum-hoodi-rpc.publicnode.com)"
drosera_rpc = "[https://relay.hoodi.drosera.io](https://relay.hoodi.drosera.io)"
eth_chain_id = 560048
drosera_address = "0x91cB447BaFc6e0EA0F4Fe056F5a9b1F14bb06e5D"

[traps]

[traps.bridge_supply_anomaly]
# 1. This path must match your compiled JSON output
path = "out/BridgeSupplyTrap.sol/BridgeSupplyTrap.json"

# 2. Deploy BridgeSupplyResponse.sol and paste its address here
response_contract = "YOUR_DEPLOYED_BridgeSupplyResponse_ADDRESS"

# 3. This function signature must exactly match BridgeSupplyResponse.sol
response_function = "respondWithSupplyAlert(address,uint256,uint256)"

# ~5 minutes, assuming 15s blocks.
cooldown_period_blocks = 20

min_number_of_operators = 1
max_number_of_operators = 3

# This is the 'data.length' in shouldRespond.
block_sample_size = 10

private_trap = true
# 4. Paste your wallet address here (the 'owner' of BridgeSupplyTrap)
# This allows you to call setTargetToken() and setMaxSupplyIncrease()
whitelist = ["YOUR_WALLET_ADDRESS"]


Testing with Foundry

Here are the cast commands to verify the trap's logic.

1. Prerequisites

You will need:

The deployed BridgeSupplyTrap address ($TRAP_ADDRESS).

A target ERC20 token to monitor (e.g., a Mock ERC20, $TOKEN_ADDRESS).

Your wallet's private key ($PK).

Your RPC URL ($RPC_URL).

2. Configure the Trap (Owner)

You must set the target token and the anomaly threshold.

# Set the token to monitor
cast send $TRAP_ADDRESS "setTargetToken(address)" $TOKEN_ADDRESS \
    --private-key $PK --rpc-url $RPC_URL

# Set the max supply increase to 1000 tokens (1000e18)
cast send $TRAP_ADDRESS "setMaxSupplyIncrease(uint256)" 1000000000000000000000 \
    --private-key $PK --rpc-url $RPC_URL


3. Testing collect()

Call collect() to get the raw encoded data packet.

# Call the collect function
cast call $TRAP_ADDRESS "collect()" --rpc-url $RPC_URL

# Output will be a single hex string, e.g.:
# 0x000000000000000000000000[tokenAddr]000000000000000000000000[totalSupply]000000000000000000000000[maxIncrease]


4. Testing shouldRespond()

This is the most important test. We will get two data packets and pass them to shouldRespond.

# 1. Get "old" data (e.g., initial state)
OLD_DATA=$(cast call $TRAP_ADDRESS "collect()" --rpc-url $RPC_URL)

# 2. (Simulate a supply change on your mock token, e.g., mint 2000 tokens)
# cast send $TOKEN_ADDRESS "mint(address,uint256)" $YOUR_ADDRESS 2000e18 --private-key $PK --rpc-url $RPC_URL

# 3. Get "new" data (after the mint)
NEW_DATA=$(cast call $TRAP_ADDRESS "collect()" --rpc-url $RPC_URL)

# 4. Call shouldRespond() by passing the array [NEW_DATA, OLD_DATA]
# This simulates a sample size of 2, with NEW_DATA being data[0]
cast call $TRAP_ADDRESS "shouldRespond(bytes[])" "[$NEW_DATA, $OLD_DATA]" \
    --rpc-url $RPC_URL

# This will return (bool, bytes). If the supply increase was > 1000, it will be:
# (true, 0x...[response_data]...)
#
# If the increase was < 1000, it will be:
# (false, 0x)


5. Foundry Test Script (Recommended)

For automated and repeatable testing, using a Foundry test script is the best method.

Run the test:

forge test
