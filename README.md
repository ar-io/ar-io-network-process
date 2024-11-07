# AO/IO Contract

[![codecov](https://codecov.io/gh/ar-io/ar-io-network-process/graph/badge.svg?token=DMM8LQO8KL)](https://codecov.io/gh/ar-io/ar-io-network-process)

[![IO Process Status](https://github.com/ar-io/ar-io-network-process/actions/workflows/monitor.yaml/badge.svg)](https://github.com/ar-io/ar-io-network-process/actions/workflows/monitor.yaml)

The implementation of the ar.io network contract is written in lua and deployed as an AO process on Arweave. The contract is responsible for managing the network state, handling transactions, and enforcing the network rules. Refer to the [contract whitepaper] for more details on the network rules and the contract design.

## Contract Spec

### General Structure

Each handler is identified by an action name and it has required and optional tags for its input. The handlers can be categorized into "read" and "write" operations.

### Handlers

#### Balances

| Action             | Required Tags                                                                                                     | Optional Tags                   | Result (the -Notice)                    |
| ------------------ | ----------------------------------------------------------------------------------------------------------------- | ------------------------------- | --------------------------------------- |
| `Transfer`         | `Recipient`: Valid Arweave address<br>`Quantity`: Integer greater than 0                                          | `X-*`: Tags beginning with "X-" | `Debit-Notice`, `Credit-Notice`         |
| `Create-Vault'`    | `Lock-Length`: Integer greater than 0<br>`Quantity`: Integer greater than 0                                       |                                 | `Vault-Created-Notice`                  |
| `Vaulted-Transfer` | `Recipient`: Valid Arweave address<br>`Lock-Length`: Integer greater than 0<br>`Quantity`: Integer greater than 0 |                                 | `Debit-Notice`, `Vaulted-Credit-Notice` |
| `Extend-Vault`     | `Vault-Id`: Valid Arweave address<br>`Extend-Length`: Integer greater than 0                                      |                                 | `Vault-Extended-Notice`                 |
| `Increase-Vault`   | `Vault-Id`: Valid Arweave address<br>`Quantity`: Integer greater than 0                                           |                                 | `Vault-Increased-Notice`                |
| `Balances`         |                                                                                                                   |                                 | `Balances-Notice`                       |
| `Balance`          |                                                                                                                   |                                 | `Balance-Notice`                        |

### ArNS Registry

| Action                     | Required Tags                                                                                                        | Optional Tags                                                          | Result                            |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | --------------------------------- |
| `Buy-Record`               | `Name`: String<br>`Purchase-Type`: String<br>`Process-Id`: Valid Arweave address<br>`Years`: Integer between 1 and 5 |                                                                        | `Buy-Record-Notice`               |
| `Extend-Lease`             | `Name`: String<br>`Years`: Integer between 1 and 5                                                                   |                                                                        | `Extend-Lease-Notice`             |
| `Increase-Undername-Limit` | `Name`: String<br>`Quantity`: Integer between 1 and 9990                                                             |                                                                        | `Increase-Undername-Limit-Notice` |
| `Token-Cost`               | `Intent`: Must be valid registry interaction (e.g., BuyRecord, ExtendLease, IncreaseUndernameLimit)                  | `Years`: Integer between 1 and 5<br>`Quantity`: Integer greater than 0 | `Token-Cost-Notice`               |
| `Demand-Factor-Settings`   |                                                                                                                      |                                                                        | `Demand-Factor-Settings-Notice`   |
| `Demand-Factor`            |                                                                                                                      |                                                                        | `Demand-Factor-Notice`            |
| `Record`                   |                                                                                                                      |                                                                        | `Record-Notice`                   |
| `Records`                  |                                                                                                                      |                                                                        | `Records-Notice`                  |
| `Reserved-Names`           |                                                                                                                      |                                                                        | `Reserved-Names-Notice`           |
| `Reserved-Name`            |                                                                                                                      |                                                                        | `Reserved-Name-Notice`            |

### Gateway Registry

| Action                      | Required Tags                                                                                                 | Optional Tags                                                                                                                                                                | Result (the -Notice)               |
| --------------------------- | ------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| `Join-Network`              | `Operator-Stake`: Quantity                                                                                    | `Label`, `Note`, `FQDN`, `Port`, `Protocol`, `Allow-Delegated-Staking`, `Min-Delegated-Stake`, `Delegate-Reward-Share-Ratio`, `Properties`, `Auto-Stake`, `Observer-Address` | `Join-Network-Notice`              |
| `Leave-Network`             |                                                                                                               |                                                                                                                                                                              | `Leave-Network-Notice`             |
| `Increase-Operator-Stake`   | `Quantity`: Integer greater than 0                                                                            |                                                                                                                                                                              | `Increase-Operator-Stake-Notice`   |
| `Decrease-Operator-Stake`   | `Quantity`: Integer greater than 0                                                                            |                                                                                                                                                                              | `Decrease-Operator-Stake-Notice`   |
| `Delegate-Stake`            | `Target`: Valid Arweave address<br>`Quantity`: Integer greater than 0                                         |                                                                                                                                                                              | `Delegate-Stake-Notice`            |
| `Decrease-Delegate-Stake`   | `Target`: Valid Arweave address<br>`Quantity`: Integer greater than 0                                         |                                                                                                                                                                              | `Decrease-Delegate-Stake-Notice`   |
| `Update-Gateway-Settings`   |                                                                                                               | `Label`, `Note`, `FQDN`, `Port`, `Protocol`, `Allow-Delegated-Staking`, `Min-Delegated-Stake`, `Delegate-Reward-Share-Ratio`, `Properties`, `Auto-Stake`, `Observer-Address` | `Update-Gateway-Settings-Notice`   |
| `Save-Observations`         | `Report-Tx-Id`: Valid Arweave address<br>`Failed-Gateways`: Comma-separated string of valid Arweave addresses |                                                                                                                                                                              | `Save-Observations-Notice`         |
| `Gateway-Registry-Settings` |                                                                                                               |                                                                                                                                                                              | `Gateway-Registry-Settings-Notice` |
| `Gateways`                  |                                                                                                               |                                                                                                                                                                              | `Gateways-Notice`                  |
| `Gateway`                   |                                                                                                               | `Address`: Valid Arweave address, `Target`: Valid Arweave address                                                                                                            | `Gateway-Notice`                   |

### Epochs

| Action                       | Required Tags                | Optional Tags | Result (the -Notice)          |
| ---------------------------- | ---------------------------- | ------------- | ----------------------------- |
| `Epoch-Settings`             |                              |               | `Epoch-Settings-Notice`       |
| `Epoch`                      | `Epoch-Index` or `Timestamp` |               | `Epoch-Notice`                |
| `Epochs`                     |                              |               | `Epochs-Notice`               |
| `Epoch-Prescribe-dObservers` | `Epoch-Index` or `Timestamp` |               | `Prescribed-Observers-Notice` |
| `Epoch-Observations`         | `Epoch-Index` or `Timestamp` |               | `Observations-Notice`         |
| `Epoch-Prescribed-Names`     | `Epoch-Index` or `Timestamp` |               | `Prescribed-Names-Notice`     |
| `Epoch-Distributions`        | `Epoch-Index` or `Timestamp` |               | `Distributions-Notice`        |

#### State

| Action  | Required Tags                             | Optional Tags | Result (the -Notice)                 |
| ------- | ----------------------------------------- | ------------- | ------------------------------------ |
| `Info`  |                                           |               | `Info-Notice`                        |
| `State` |                                           |               | `State-Notice`                       |
| `Tick`  | `Hash-Chain`, `Timestamp`, `Block-Height` |               | `Tick-Notice`, `Invalid-Tick_Notice` |

## Developers

### Requirements

- Lua 5.3 - [Download](https://www.lua.org/download.html)
- Luarocks - [Download](https://luarocks.org/)

### Lua Setup (MacOS)

1. Clone the repository and navigate to the project directory.
2. Install `lua`

- `brew install lua@5.3`

3. Add the following to your `.zshrc` or `.bashrc` file:

```bash
echo 'export LDFLAGS="-L/usr/local/opt/lua@5.3/lib"' >> ~/.zshrc
echo 'export CPPFLAGS="-I/usr/local/opt/lua@5.3/include/lua5.3"' >> ~/.zshrc
echo 'export PKG_CONFIG_PATH="/usr/local/opt/lua@5.3/lib/pkgconfig"' >> ~/.zshrc
echo 'export PATH="/usr/local/opt/lua@5.3/bin:$PATH"' >> ~/.zshrc
```

1. Run `source ~/.zshrc` or `source ~/.bashrc` to apply the changes.
2. Run `lua -v` to verify the installation.

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

2. Ensure that the `luarocks` binary is in your path by running `echo $PATH`. Otherwise, add it to your path and reload your shell:

```bash
echo 'export PATH=$HOME/.luarocks/bin:$PATH' >> ~/.zshrc
```

3. Check the installation by running `luarocks --version`.
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
aos --load src/main.lua
```

### Code Formatting

To get the code formatter, we'll need to install rust to access `cargo`. To install rust on MacOS, run the following command:

```sh
brew install rust
```

If not already added, include `cargo` binary in your path so that packages installed using `cargo` can be accessed globally:

```
echo 'export PATH=$HOME/.cargo/bin:$PATH' >> ~/.zshrc
```

The code is formatted using `stylua`. To install `stylua`, run the following command:

```sh
cargo install stylua
stylua contract
```

### Testing

To run the tests, execute the following command:

```sh
busted .
```

To see the test coverage, get luacov:

```sh
luarocks install luacov
```

With luacov installed, run the following command:

```sh
luacov --reporter html && open luacov-html/index.html
```

### Dependencies

To add new dependencies, install using luarocks to the local directory

```sh
luarocks install <package>
```

And add the package to the `dependencies` table in the `ar-io-ao-0.1-1.rockspec` file.

```lua
-- rest of the file
dependencies = {
    "lua >= 5.3",
    "luaunit >= 3.3.0",
    "<package>"
}
```

### Deployment

TODO:

[contract whitepaper]: https://ar.io/whitepaper
