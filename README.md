# SPECTER Contracts

On-chain announcement registry for [SpecterPQ](https://github.com/pranshurastogi/SPECTER) stealth payments on Monad. Uses ML-KEM-768 (NIST FIPS 203) for post-quantum key encapsulation, inspired by the ERC-5564 announcement pattern.

---

## Deployments

### Monad Testnet — chain ID 10143

| Contract | Address |
|---|---|
| `SPECTERAnnouncer` | [`0x7a687B5a7c98c880f23F00003A820e7E2fF7fDaC`](https://testnet.monadexplorer.com/address/0x7a687B5a7c98c880f23F00003A820e7E2fF7fDaC) |

```
Salt:         keccak256("specterpq.announcer.v1")
Factory:      0x4e59b44847b379578588920cA78FbF26c0B4956C  (CREATE2)
Deploy tx:    0xa66a1afe651c26c22b2e361b41ce6803824c87a1a7fbd2793c96e19731a8f354
Deploy block: 37,571,591
Verified:     Sourcify — perfect match (full bytecode + metadata)
```

[![Verified on Sourcify](https://img.shields.io/badge/Sourcify-verified%20%E2%9C%94-brightgreen)](https://testnet.monadexplorer.com/address/0x7a687B5a7c98c880f23F00003A820e7E2fF7fDaC)

> The same salt + factory produces the same address on every EVM chain where the factory is deployed.

---

## How It Works

SPECTERAnnouncer is a stateless event emitter — no storage, no owner, no admin keys, not upgradeable. Every call is a single `LOG3` opcode plus input validation.

**Ephemeral key design.** An ML-KEM-768 ciphertext is 1,088 bytes. Rather than bloating every log entry, only `keccak256(ciphertext)` is emitted. The full ciphertext lives in calldata — permanently archived on-chain and retrievable via `eth_getTransactionByHash`. Scanners fetch the ciphertext only for the ~1/256 events that pass the view-tag filter.

**Scanning protocol:**
```
1. eth_getLogs(address=SPECTERAnnouncer, fromBlock=deployBlock)
2. For each event: check metadata[0] (view_tag) — skip ~255/256
3. On match: eth_getTransactionByHash → ABI-decode calldata → ephemeralPubKey
4. Assert keccak256(ephemeralPubKey) == ephemeralKeyHash
5. ML-KEM.Decaps(sk, ephemeralPubKey) → sharedSecret → derive stealth key
```

---

## Interface

```solidity
event Announcement(
    uint256         schemeId,           // SCHEME_ID = 1000, not indexed
    address indexed stealthAddress,
    address indexed caller,
    bytes32         ephemeralKeyHash,   // keccak256(ML-KEM-768 ciphertext)
    bytes           metadata
);
```

**Metadata layout** — raw-packed, big-endian, no ABI encoding:

| Offset | Field | Type | |
|---|---|---|---|
| `[0]` | `view_tag` | `uint8` | Required |
| `[1..32]` | `tx_hash` | `bytes32` | Optional — `0x00` = absent |
| `[33..64]` | `amount` | `uint256` | Optional — 0 = absent |
| `[65..76]` | `channel_id` | `bytes12` | Optional — `0x00` = absent |

Minimum valid metadata: 1 byte. Maximum: 77 bytes.

**Functions:**

```solidity
// Announce a single stealth payment
function announce(address stealthAddress, bytes calldata ephemeralPubKey, bytes calldata metadata) external;

// Overload that accepts an explicit schemeId (must equal SCHEME_ID = 1000)
function announce(uint256 schemeId, address stealthAddress, bytes calldata ephemeralPubKey, bytes calldata metadata) external;

// Batch — amortizes 21,000-gas base tx across up to 50 announcements
function announceMany(address[] calldata, bytes[] calldata, bytes[] calldata) external;
```

**Constants:**

```solidity
uint256 public constant SCHEME_ID            = 1000;
uint256 public constant EPHEMERAL_KEY_LENGTH = 1088;
uint256 public constant MAX_BATCH            = 50;
uint256 public immutable deployBlock;
```

**Errors:**

```solidity
error ZeroStealthAddress();
error EphemeralKeyLength(uint256 actual, uint256 expected);
error MetadataRequired();
error SchemeMismatch(uint256 given, uint256 expected);
error BatchEmpty();
error BatchTooLarge(uint256 length, uint256 max);
error BatchLengthMismatch();
```

The full interface is at [`src/interfaces/ISPECTERAnnouncer.sol`](./src/interfaces/ISPECTERAnnouncer.sol).

---

## Gas

| Scenario | Total tx | Per announcement |
|---|---|---|
| `announce()` — single | ~37,500 | — |
| `announceMany()` — N = 10 | ~80,000 | ~5,910 |
| `announceMany()` — N = 50 | ~308,000 | ~5,750 |

> Measured with Solc 0.8.26, 200 optimizer runs, Cancun EVM.  
> Monad charges gas on `gas_limit`, not `gas_used`. Use `--gas-estimate-multiplier 200` with Foundry scripts; set `gasLimit = 60,000` from a frontend for single announces.

---

## Development

**Requirements:** [Foundry](https://getfoundry.sh/) — Solidity 0.8.26 is installed automatically.

```bash
git clone https://github.com/pranshurastogi/specter-contracts
cd specter-contracts
forge install
cp .env.example .env   # fill in PRIVATE_KEY, MONAD_TESTNET_RPC, MONAD_MAINNET_RPC
```

```bash
forge build            # compile
forge test             # run all 34 tests
forge test -vv         # with gas logs
forge coverage         # coverage report
```

---

## Deployment

```bash
source .env

# Testnet
forge script script/deploySPECTERAnnouncer.s.sol \
  --rpc-url $MONAD_TESTNET_RPC --broadcast --gas-estimate-multiplier 200 -vv

# Mainnet
forge script script/deploySPECTERAnnouncer.s.sol \
  --rpc-url $MONAD_MAINNET_RPC --broadcast --gas-estimate-multiplier 200 -vv
```

The script skips deployment if the expected CREATE2 address already has code.

**Verify:**

```bash
forge verify-contract \
  --rpc-url $MONAD_TESTNET_RPC \
  --verifier sourcify \
  --verifier-url 'https://sourcify-api-monad.blockvision.org/' \
  <DEPLOYED_ADDRESS> \
  src/SPECTERAnnouncer.sol:SPECTERAnnouncer
```

**Smoke test:**

```bash
forge script script/testAnnounce.s.sol \
  --rpc-url $MONAD_TESTNET_RPC --broadcast --gas-estimate-multiplier 200 -vvv
```

---

## Security

- No `SSTORE` — no storage manipulation possible
- No external `CALL` — no reentrancy vectors
- No owner or admin — no privilege escalation
- No proxy — no implementation swap
- No ETH handling — no value extraction

Input validation is the only on-chain attack surface. Off-chain: a caller can emit an announcement with a malformed ciphertext; scanners MUST verify `keccak256(fetched) == ephemeralKeyHash` before proceeding.

**Status:** Unaudited. Deployed on testnet.

---

## License

[Apache-2.0](./LICENSE)
