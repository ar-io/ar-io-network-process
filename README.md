# AO/IO Network Process

[![codecov](https://codecov.io/gh/ar-io/ar-io-network-process/graph/badge.svg?token=DMM8LQO8KL)](https://codecov.io/gh/ar-io/ar-io-network-process) [![$ARIO Network Status](https://github.com/ar-io/ar-io-network-process/actions/workflows/monitor.yaml/badge.svg)](https://github.com/ar-io/ar-io-network-process/actions/workflows/monitor.yaml)

The implementation of the ar.io network contract is written in lua and deployed as an AO process on Arweave. The contract is responsible for managing the network state, handling transactions, and enforcing the network rules. Refer to the [contract whitepaper] for more details on the network rules and the contract design.

<!-- toc -->

- [Networks](#networks)
- [Specs](#specs)
- [Deployments](#deployments)
  - [Testnet & Devnet](#testnet--devnet)
  - [Mainnet](#mainnet)
- [Monitoring](#monitoring)
- [Tests](#tests)
  - [Unit Tests](#unit-tests)
  - [Integration Tests](#integration-tests)
- [Developers](#developers)
  - [Requirements](#requirements)
  - [Lua Setup (MacOS)](#lua-setup-macos)
  - [LuaRocks Setup](#luarocks-setup)
  - [aos](#aos)
  - [Code Formatting](#code-formatting)
  - [Dependencies](#dependencies)

<!-- tocstop -->

## Networks

- [Mainnet - qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE](https://ao.link/qNvAoz0TgcH7DMg8BCVn8jF32QH5L6T29VjHxhHqqGE)
- [Testnet - agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA](https://ao.link/agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA)
- [Devnet - GaQrvEMKBpkjofgnBi_B3IgIDmY_XYelVLB6GcRGrHc](https://ao.link/GaQrvEMKBpkjofgnBi_B3IgIDmY_XYelVLB6GcRGrHc)

## Specs

Refer to the AR.IO Network [Spec](SPEC.md) document for more details on the contract actions and their inputs and outputs.

## Deployments

### Testnet & Devnet

Merging to develop or main will evolve the devnet or testnet contract to the latest source code. The script managing the logic is located at `tools/evolve.mjs`, which uses [aoconnect] to perform an `Eval` action. The deployment process is automated using Github Actions.

To manually apply updates to the devnet or testnet contract, run the following command:

```sh
aos <network-process-id> --cu-url https://cu.ardrive.io --wallet /path/to/wallet.json
```

From there, you can perform an `Eval` action to apply the updates:

```sh
Devnet ARIO@aos-2.0.1[Inbox:270]>  .load process.lua (or some other lua code)
```

### Mainnet

Mainnet deployment is managed manually by the AR.IO team via modules in [ar-io/aos](https://github.com/ar-io/aos) forked repository. The process is owned by a [multi-sig process](https://github.com/ar-io/vaot) available at [vaot.ar.io](https://vaot.ar.io) and requires majority of controllers to approve evals before the update is applied.

## Monitoring

Monitor tests leverage the [ar-io-sdk](https://github.com/ar-io/ar-io-sdk) to evaluate the state of the network and intended to detect invariant states on the network process. These tests spin up a local AO CU service via [testcontainers](https://www.testcontainers.org/) and evaluate the state of the network process.

To run the monitor tests, execute the following command:

```sh
yarn monitor:<devnet|testnet|mainnet>
```

You can also choose to run the monitor tests against a specific forked process by setting the `ARIO_PROCESS_ID` environment variable:

```sh
ARIO_PROCESS_ID=<process-id> yarn monitor
```

You can also use the ad-hoc workflow to evaluate a forked process by setting the `ARIO_PROCESS_ID` environment variable and running the workflow via [GitHub Actions](https://github.com/ar-io/ar-io-network-process/actions/workflows/monitor_ad_hoc.yaml).

## Tests

### Unit Tests

Unit tests are written using the [Busted](https://olivinelabs.github.io/busted/) framework. To run the tests, execute the following command:

```sh
busted . or yarn test:unit
```

To run the tests with debugging (includes print statements), set the `DEBUG` environment variable to `true`:

```sh
DEBUG=true busted . or yarn test:unit:debug
```

### Integration Tests

Integration tests are written using the [ao-loader](https://github.com/permaweb/ao/tree/main/loader). To run the tests, execute the following command:

```sh
yarn test:integration
```

## Developers

### Requirements

- Lua 5.3 - [Download](https://www.lua.org/download.html)
- Luarocks - [Download](https://luarocks.org/)

### Lua Setup (MacOS)

1. Clone the repository and navigate to the project directory.
2. Install `lua`

- `brew install lua@5.3`

3. Add the following to your `zshrc`or `bashrc`file:

```bash
echo 'export LDFLAGS="-L/usr/local/opt/lua@5.3/lib"' >> ~/.zshrc
echo 'export CPPFLAGS="-I/usr/local/opt/lua@5.3/include/lua5.3"' >> ~/.zshrc
echo 'export PKG_CONFIG_PATH="/usr/local/opt/lua@5.3/lib/pkgconfig"' >> ~/.zshrc
echo 'export PATH="/usr/local/opt/lua@5.3/bin:$PATH"' >> ~/.zshrc
```

1. Run `source ~/.zshrc`or `source ~/.bashrc`to apply the changes.
2. Run `lua -v`to verify the installation.

### LuaRocks Setup

1. Install `luarocks`

```bash
curl -R -O http://luarocks.github.io/luarocks/releases/luarocks-3.9.1.tar.gz
tar zxpf luarocks-3.9.1.tar.gz
cd luarocks-3.9.1
./configure --with-lua=/usr/local/opt/lua@5.3 --with-lua-include=/usr/local/opt/lua@5.3/include/lua5.3
make build
sudo make install
```

2. Ensure that the `luarocks`binary is in your path by running `echo $PATH` Otherwise, add it to your path and reload your shell:

```bash
echo 'export PATH=$HOME/.luarocks/bin:$PATH' >> ~/.zshrc
```

3. Check the installation by running `luarocks --version`
4. Check the LuaRocks configuration by running `luarocks config | grep LUA`

If you ever need to refresh .luarocks, run the following command:

```sh
luarocks purge && luarocks install ar-io-ao-0.1-1.rockspec
```

### aos

Get aos:

```sh
yarn global add https://get_ao.g8way.io
```

To load the module into the `aos` REPL, run the following command:

```sh
aos --load process.lua
```

### Code Formatting

To get the code formatter, we'll need to install rust to access `cargo` To install rust on MacOS, run the following command:

```sh
brew install rust
```

If not already added, include `cargo`binary in your path so that packages installed using `cargo`can be accessed globally:

```
echo 'export PATH=$HOME/.cargo/bin:$PATH' >> ~/.zshrc
```

The code is formatted using `stylua` To install `stylua`, run the following command:

```sh
cargo install stylua
stylua contract
```

### Dependencies

To add new dependencies, install using luarocks to the local directory

```sh
luarocks install <package>
```

And add the package to the `dependencies`table in the `ar-io-ao-0.1-1.rockspec`file.

```lua
-- rest of the file
dependencies = {
    "lua >= 5.3",
    "luaunit >= 3.3.0",
    "<package>"
}
```

[contract whitepaper]: https://whitepaper.ar.io
[aoconnect]: https://github.com/permaweb/ao/tree/main/connect
