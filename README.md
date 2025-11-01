# BridgeSupplyTrap
# README — BridgeSupplyTrap

## Overview

**BridgeSupplyTrap** is a Drosera-compatible proof-of-concept trap that monitors bridged ERC20 tokens and flags an anomaly when a rapid supply increase exceeds a configured threshold. It helps detect liquidity exploits or misconfigured bridge minting logic.

This repository contains the main trap contract `BridgeSupplyTrap.sol`, a simple response contract `BridgeSupplyResponse.sol`, and a working `drosera.toml` configuration for Hoodi testnet. ([GitHub][1])

---

## Files in this repo

* `src/BridgeSupplyTrap.sol` — main Drosera trap (implements `ITrap`)
* `src/BridgeSupplyResponse.sol` — simple response contract (emits alert event)
* `drosera.toml` — configuration for Hoodi Drosera relay setup
* `README.md` — this file — documentation and test instructions ([GitHub][1])

---

## Behaviour & data flow (brief)

1. **Operator** calls `setTargetToken(address)` to set the bridged token to monitor.
2. **Operator** configures `setMaxSupplyIncrease(uint256)` to define the maximum allowed increase over the monitored block window.
3. Drosera (or any observer) periodically calls `collect()` on the trap. `collect()` reads the token’s total supply and the configured threshold, returning an encoded packet:
   `abi.encode(address token, uint256 totalSupply, uint256 maxIncreaseThreshold)`
4. The relay accumulates these samples over its configured window, then calls `shouldRespond(bytes[] calldata data)` where `data[0]` is the latest `collect()` result and `data[data.length-1]` is the oldest.
5. If the difference between the latest and oldest total supply exceeds `maxSupplyIncrease`, the trap deterministically returns `(true, abi.encode(token, oldSupply, newSupply))`.
6. Drosera relay calls the response contract’s `respondWithSupplyAlert(address,uint256,uint256)` with the encoded payload.

---

## Deploying (quick)

1. `forge build` to compile.
2. Deploy `BridgeSupplyResponse.sol` to your target network (for example, Hoodi) and copy its address.
3. Deploy `BridgeSupplyTrap.sol` (no constructor args).
4. Call `setTargetToken(<BRIDGED_TOKEN_ADDRESS>)` and `setMaxSupplyIncrease(<THRESHOLD>)`.
5. Edit `drosera.toml` to reference the deployed response contract and update its parameters.

---

## Quick `cast` examples

> Replace `<RPC>`, `<TRAP_ADDRESS>`, and `<TOKEN>` with your actual values.

### 1) Call `collect()` and decode output

```bash
COLLECT_RAW=$(cast call --rpc-url <RPC> <TRAP_ADDRESS> "collect()")

# decode the output; trap encodes (address token, uint256 totalSupply, uint256 threshold)
cast abi-decode "(address,uint256,uint256)" "$COLLECT_RAW"
```

Example output:

```
(address) 0xBaa...
(uint256) 1000000000000000000000
(uint256) 50000000000000000000
```

Interpretation: token supply is 1000 units, threshold is 50 units.

### 2) Check anomaly with `shouldRespond(bytes[])`

Collect multiple samples, encode them as a `bytes[]`, then call:

```bash
cast call <TRAP_ADDRESS> "shouldRespond(bytes[]) returns (bool,bytes)" '[<encodedNew>,<encodedOld>]' --rpc-url <RPC>
```

If `true`, decode the payload:

```bash
cast abi-decode "(address,uint256,uint256)" <PAYLOAD>
```

This gives `(token, oldSupply, newSupply)`.

### 3) Emit response manually

Once the trap triggers, the relay (or tester) calls:

```bash
cast send <RESPONSE_CONTRACT> "respondWithSupplyAlert(address,uint256,uint256)" <TOKEN> <OLD_SUPPLY> <NEW_SUPPLY> --private-key <KEY>
```

---

## Foundry test — `test/BridgeSupplyTrap.t.sol`

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BridgeSupplyTrap.sol";
import "../src/BridgeSupplyResponse.sol";

contract BridgeSupplyTrapTest is Test {
    BridgeSupplyTrap trap;
    BridgeSupplyResponse response;

    contract MockERC20 {
        uint256 public totalSupply;
        function mint(uint256 a) external { totalSupply += a; }
        function burn(uint256 a) external { totalSupply -= a; }
    }

    MockERC20 token;

    function setUp() public {
        trap = new BridgeSupplyTrap();
        response = new BridgeSupplyResponse();
        token = new MockERC20();

        trap.setTargetToken(address(token));
        trap.setMaxSupplyIncrease(1000 ether);
    }

    function testCollectEncodesData() public {
        bytes memory data = trap.collect();
        BridgeSupplyTrap.SupplyData memory decoded = abi.decode(data, (BridgeSupplyTrap.SupplyData));
        assertEq(decoded.tokenAddress, address(token));
    }

    function testShouldRespondTriggersOnSpike() public {
        token.mint(10000 ether);
        bytes memory oldData = trap.collect();
        token.mint(12000 ether);
        bytes memory newData = trap.collect();

        bytes[] memory samples = new bytes[](2);
        samples[0] = newData;
        samples[1] = oldData;

        (bool trigger, bytes memory payload) = trap.shouldRespond(samples);
        assertTrue(trigger);

        (address tkn, uint256 oldSupply, uint256 newSupply) = abi.decode(payload, (address, uint256, uint256));
        response.respondWithSupplyAlert(tkn, oldSupply, newSupply);
    }
}
```

---

## drosera.toml (example)

```toml
ethereum_rpc = "https://ethereum-hoodi-rpc.publicnode.com"
drosera_rpc = "https://relay.hoodi.drosera.io"
eth_chain_id = 560048
drosera_address = "0x91cB447BaFc6e0EA0F4Fe056F5a9b1F14bb06e5D"

[traps]

[traps.bridge_supply_anomaly]
path = "out/BridgeSupplyTrap.sol/BridgeSupplyTrap.json"
response_contract = "0xRESPONSE_CONTRACT_ADDRESS"   # replace with deployed AVSResponder
response_function = "respondWithSupplyAlert(address,uint256,uint256)"
cooldown_period_blocks = 30
min_number_of_operators = 1
max_number_of_operators = 3
block_sample_size = 10
private_trap = true
whitelist = ["YOUR_OPERATOR_ADDRESS"]

```

---

## Attribution

Repository inspected: `Kingflirckz22/BridgeSupplyTrap`. ([GitHub][1])

---

[1]: https://github.com/Kingflirckz22/BridgeSupplyTrap


