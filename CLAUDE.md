# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the AR.IO network contract implementation written in Lua, deployed as an AO process on Arweave. The contract manages the ar.io network state including gateway registry, ArNS name registration, token balances, epochs, and staking/delegation.

## Build and Test Commands

```bash
# Build the bundled Lua code
yarn build

# Run all tests (formats, unit, integration)
yarn test

# Unit tests only (uses Busted framework)
yarn test:unit
busted .                    # Alternative direct command

# Unit tests with debug output (enables print statements)
DEBUG=true busted .
yarn test:unit:debug

# Integration tests (requires build first)
yarn test:integration

# Run a single unit test file
busted spec/arns_spec.lua

# Run a single integration test file
node --test --experimental-wasm-memory64 tests/arns.test.mjs

# Lint Lua code
yarn lint

# Format code
yarn format:fix
stylua contract             # Lua formatting only

# Run coverage report
yarn test:coverage

# Monitor tests against live networks
yarn monitor:devnet
yarn monitor:testnet
yarn monitor:mainnet
```

## Architecture

### Entry Points
- `process.lua` - Main entry point that loads `src/init.lua` and `state/init.lua`
- `src/init.lua` - Initializes globals and main handlers
- `src/main.lua` - Defines all AO message handlers (ActionMap) and request processing

### Core Modules (src/)
- `globals.lua` - Global state variables (Balances, GatewayRegistry, NameRegistry, Epochs, Vaults, PrimaryNames, DemandFactor)
- `constants.lua` - Network constants and default settings
- `gar.lua` - Gateway Registry operations (join/leave network, staking, delegation)
- `arns.lua` - ArNS name registration (buy, extend, release, reassign)
- `balances.lua` - Token balance operations
- `epochs.lua` - Epoch management and observer prescriptions
- `vaults.lua` - Token vault/locking operations
- `primary_names.lua` - Primary name registration and requests
- `demand.lua` - Demand factor calculations for dynamic pricing
- `tick.lua` - Epoch progression and reward distribution
- `prune.lua` - State cleanup for expired records/vaults
- `token.lua` - Token metadata and supply calculations
- `hb.lua` - Hyperbeam sync for state patches

### State Management
Global state is stored in Lua globals defined in `src/globals.lua`:
- `Balances` - Token balances by address
- `GatewayRegistry` - Registered gateways and their configurations
- `NameRegistry` - ArNS records, reserved names, returned names
- `Epochs` - Epoch data including observers and distributions
- `Vaults` - Locked token vaults
- `PrimaryNames` - Primary name assignments and requests
- `DemandFactor` - Dynamic pricing state

### Testing Structure
- `spec/` - Unit tests (Lua, Busted framework)
  - `spec/setup.lua` - Test setup with ao mocks
  - Tests follow `*_spec.lua` naming convention
- `tests/` - Integration tests (JavaScript, Node test runner)
  - `tests/helpers.mjs` - Common test utilities and helper functions
  - `tests/utils.mjs` - AO loader initialization
  - Tests follow `*.test.mjs` naming convention
- `tools/constants.mjs` - Test constants and fixtures

### Build System
- `tools/bundle-aos.mjs` - Bundles Lua source into single file
- `tools/lua-bundler.mjs` - Lua bundling utilities
- Output: `dist/aos-bundled.lua`

### Deployment
- Testnet/Devnet: Automated via GitHub Actions using `tools/evolve.mjs`
- Mainnet: Manual via ar-io/aos fork, requires multi-sig approval

## Key Conventions

- All tag values in AO messages must be strings (not integers)
- Token amounts are in mARIO (1 ARIO = 1,000,000 mARIO)
- Timestamps are Unix milliseconds
- Addresses are 43-character Arweave transaction IDs
- Critical handlers (Tick, Prune, Sanitize) discard memory on error

## Dependencies

Lua dependencies managed via LuaRocks (`ar-io-ao-0.1-1.rockspec`):
- busted (testing)
- luacov (coverage)
- luacheck (linting)

Node dependencies in `package.json` for integration tests and tooling.
