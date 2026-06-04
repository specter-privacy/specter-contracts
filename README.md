# SPECTER specific ERC-5564 contracts
Minimal contracts required by [SpecterPQ](https://github.com/pranshurastogi/SPECTER) for [ERC-5564](https://github.com/ethereum/ERCs/blob/master/ERCS/erc-5564.md) (Stealth Addresses)

The SPECTERAnnouncer is a modified ERC5564Announcer contract with minimal code intentionally:
- No state (no SSTOREs — just a LOG4 opcode per announcement)
- No owner, no admin keys, no upgradeability
- ERC-5564 event interface so existing indexers and explorers can parse it
- ML-KEM-specific schemeId to distinguish PQ announcements from secp256k1

## Why no state / no storage?
The contract has exactly one public read (deployBlock, immutable). There are no mappings,
no counters, no owner. This means:
- Zero SSTORE costs — the announce call is almost pure calldata + LOG4
- No attack surface for storage manipulation or reentrancy
- Fits the ERC-5564 design intent (singleton event emitter, not a registry)