# AO/IO Contract

[![codecov](https://codecov.io/gh/ar-io/ar-io-network-process/graph/badge.svg?token=DMM8LQO8KL)](https://codecov.io/gh/ar-io/ar-io-network-process)

[![IO Process Status](https://github.com/ar-io/ar-io-network-process/actions/workflows/monitor.yaml/badge.svg)](https://github.com/ar-io/ar-io-network-process/actions/workflows/monitor.yaml)

The implementation of the ar.io network contract is written in lua and deployed as an AO process on Arweave. The contract is responsible for managing the network state, handling transactions, and enforcing the network rules. Refer to the [contract whitepaper] for more details on the network rules and the contract design.

## Contract Spec

### General Structure

Each handler is identified by an action name and it has required and optional tags for its input. The handlers can be categorized into "read" and "write" operations.

| **Category**              | **Action**                                                   | **Description**                                                                                                       | **Inputs (Required/Optional)**                                                                                                     |
| ------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **General**               | `Info`                                                       | Provides metadata about the process, including name, ticker, logo, denomination, owner, and handlers.                 | None                                                                                                                               |
| **Token Supply**          | `Total-Supply`                                               | Retrieves the total token supply (circulating, locked, staked, delegated, withdrawn).                                 | None                                                                                                                               |
|                           | `Total-Token-Supply`                                         | Provides a detailed breakdown of token supply components.                                                             | None                                                                                                                               |
| **Balance and Transfers** | `Balance`                                                    | Returns the balance for a specified address.                                                                          | **Optional:** `Address` (defaults to `From`)                                                                                       |
|                           | `Balances`                                                   | Retrieves balances for all addresses. Recommended to use `Paginated-Balances` instead.                                | None                                                                                                                               |
|                           | `Paginated-Balances`                                         | Lists balances with support for pagination.                                                                           | **Optional:** `Cursor`, `Limit`, `SortBy`, `SortOrder`                                                                             |
|                           | `Transfer`                                                   | Processes token transfers between two addresses.                                                                      | **Required:** `Recipient`, `Quantity` <br> **Optional:** `Allow-Unsafe-Addresses`                                                  |
| **Vaults**                | `Vault`                                                      | Fetches details of a specific vault by its ID.                                                                        | **Required:** `Address`, `Vault-Id`                                                                                                |
|                           | `Vaults` or `Paginated-Vaults`                               | Lists all vaults, with pagination support.                                                                            | **Optional:** `Cursor`, `Limit`, `SortBy`, `SortOrder`                                                                             |
|                           | `Create-Vault`                                               | Creates a new vault with a specified lock length and amount.                                                          | **Required:** `Quantity`, `Lock-Length`                                                                                            |
|                           | `Vaulted-Transfer`                                           | Creates a vault while transferring tokens to a recipient.                                                             | **Required:** `Recipient`, `Quantity`, `Lock-Length` <br> **Optional:** `Allow-Unsafe-Addresses`                                   |
|                           | `Extend-Vault`                                               | Extends the lock period of an existing vault.                                                                         | **Required:** `Vault-Id`, `Extend-Length`                                                                                          |
|                           | `Increase-Vault`                                             | Adds more tokens to an existing vault.                                                                                | **Required:** `Vault-Id`, `Quantity`                                                                                               |
| **Epochs**                | `Epoch`                                                      | Fetches details of a specific epoch by its index.                                                                     | **Optional:** `Epoch-Index`or uses current timestamp.                                                                              |
|                           | `Epochs`                                                     | Lists all epochs, with pagination support.                                                                            | **Optional:** `Cursor`, `Limit`, `SortBy`, `SortOrder`                                                                             |
|                           | `Epoch-Settings`                                             | Retrieves configuration settings for epochs.                                                                          | None                                                                                                                               |
|                           | `Epoch-Observations`                                         | Retrieves observations recorded during a specific epoch.                                                              | **Optional:** `Epoch-Index`or uses current timestamp.                                                                              |
|                           | `Epoch-Distribution`                                         | Retrieves the distribution of rewards for a specific epoch.                                                           | **Optional:** `Epoch-Index`or uses current timestamp.                                                                              |
|                           | `Save-Observations`                                          | Saves observations for a specific epoch.                                                                              | **Required:** `Report-Tx-Id`, `Failed-Gateways`                                                                                    |
|                           | `Prescribed-Observers`                                       | Retrieves prescribed observers for a specific epoch.                                                                  | **Optional:** `Epoch-Index`or uses current timestamp.                                                                              |
|                           | `Prescribed-Names`                                           | Retrieves prescribed names for a specific epoch.                                                                      | **Optional:** `Epoch-Index`or uses current timestamp.                                                                              |
| **Gateway Registry**      | `Gateway`                                                    | Fetches details of a specific gateway by its address.                                                                 | **Required:** `Address`or defaults to `From`                                                                                       |
|                           | `Gateways` or `Paginated-Gateways`                           | Lists all gateways, with pagination support.                                                                          | **Optional:** `Cursor`, `Limit`, `SortBy`, `SortOrder`                                                                             |
|                           | `Gateway-Registry-Settings`                                  | Retrieves the settings for the gateway registry.                                                                      | None                                                                                                                               |
|                           | `Join-Network`                                               | Adds a gateway to the network with specified configurations.                                                          | **Required:** `Operator-Stake` <br> **Optional:** `Label`, `Note`, `Services`, `FQDN`, `Protocol`, `Allow-Delegated-Staking`, etc. |
|                           | `Leave-Network`                                              | Removes a gateway from the network.                                                                                   | None                                                                                                                               |
|                           | `Update-Gateway-Settings`                                    | Updates the settings of a gateway.                                                                                    | **Optional:** `Label`, `Note`, `FQDN`, `Port`, `Protocol`, `Allow-Delegated-Staking`, etc.                                         |
|                           | `Delegates` or `Paginated-Delegates`                         | Lists delegates with support for pagination.                                                                          | **Optional:** `Cursor`, `Limit`, `SortBy`, `SortOrder`                                                                             |
|                           | `Allowed-Delegates` or `Paginated-Allowed-Delegates`         | Lists allowed delegates with pagination support for a specific gateway.                                               | **Optional:** `Cursor`, `Limit`, `SortOrder`                                                                                       |
|                           | `Gateway-Vaults` or `Paginated-Gateway-Vaults`               | Lists vaults for a specific gateway, with pagination support.                                                         | **Optional:** `Cursor`, `Limit`, `SortBy`, `SortOrder`                                                                             |
|                           | `Redelegate-Stake`                                           | Redelegates stake from one gateway to another.                                                                        | **Required:** `Source`, `Target`, `Quantity` <br> **Optional:** `Vault-Id`                                                         |
|                           | `Delegate-Stake`                                             | Delegates stake to a gateway.                                                                                         | **Required:** `Gateway`, `Quantity` <br> **Optional:** `Vault-Id`                                                                  |
|                           | `Decrease-Delegate-Stake`                                    | Decreases delegated stake from a gateway.                                                                             | **Required:** `Gateway`, `Quantity` <br> **Optional:** `Vault-Id`                                                                  |
|                           | `Increase-Operator-Stake`                                    | Increases operator stake for a gateway.                                                                               | **Required:** `Gateway`, `Quantity` <br> **Optional:** `Vault-Id`                                                                  |
|                           | `Decrease-Operator-Stake`                                    | Decreases operator stake from a gateway.                                                                              | **Required:** `Gateway`, `Quantity` <br> **Optional:** `Vault-Id`                                                                  |
|                           | `Cancel-Withdrawal`                                          | Cancels a withdrawal request.                                                                                         | **Required:** `Withdrawal-Id`                                                                                                      |
|                           | `Instant-Withdrawal`                                         | Instantly withdraws stake from a specific gateway.                                                                    | **Required:** `Gateway`, `Quantity` <br> **Optional:** `Vault-Id`                                                                  |
|                           | `Allow-Delegates`                                            | Allows delegates for a gateway.                                                                                       | None                                                                                                                               |
|                           | `Disallow-Delegates`                                         | Disallows delegates for a gateway.                                                                                    | None                                                                                                                               |
|                           | `Delegations`                                                | Paginated delegations for a gateway.                                                                                  | **Optional:** `Address` (defaults to msg.From), `Cursor`, `Limit`, `SortBy`, `SortOrder`                                           |
| **Name Registry (ArNS)**  | `Record`                                                     | Fetches details of a specific record by its name.                                                                     | **Required:** `Name`                                                                                                               |
|                           | `Records` or `Paginated-Records`                             | Lists all records, with pagination support.                                                                           | **Optional:** `Cursor`, `Limit`, `SortBy`, `SortOrder`                                                                             |
|                           | `Buy-Name`                                                   | Purchases a name record for a specified duration.                                                                     | **Required:** `Name` <br> **Optional:** `Years`, `Fund-From`                                                                       |
|                           | `Upgrade-Name`                                               | Upgrades a name record to a permanent record.                                                                         | **Required:** `Name` <br> **Optional:** `Fund-From`                                                                                |
|                           | `Extend-Lease`                                               | Extends the lease of a name record.                                                                                   | **Required:** `Name`, `Years` <br> **Optional:** `Fund-From`                                                                       |
|                           | `Increase-Undername-Limit`                                   | Increases the undername limit for a specific record.                                                                  | **Required:** `Name`, `Quantity` <br> **Optional:** `Fund-From`                                                                    |
|                           | `Release-Name`                                               | Releases a name record, making it available for others to claim.                                                      | **Required:** `Name`                                                                                                               |
|                           | `Reserved-Names` or `Paginated-Reserved-Names`               | Lists reserved names with pagination support.                                                                         | **Optional:** `Cursor`, `Limit`, `SortBy`, `SortOrder`                                                                             |
|                           | `Returned-Names` or `Paginated-Returned-Names`               | Lists returned names with pagination support.                                                                         | **Optional:** `Cursor`, `Limit`, `SortBy`, `SortOrder`                                                                             |
|                           | `Reassign-Name`                                              | Reassigns a name to a new process id.                                                                                 | **Required:** `Name`, `Process-Id` <br> **Optional:** `Allow-Unsafe-Addresses`, `Initiator`                                        |
| **Token Cost**            | `Token-Cost`                                                 | Retrieves the total mARIO required for a specific action. Recommended to use `Cost-Details` instead for more details. | **Required:** `Intent`, `Name`<br> **Optional:** `Years`, `Quantity`, `Purchase-Type`                                              |
|                           | `Cost-Details`                                               | Retrieves the total mARIO required for a specific action with fundingPlan and discount details.                       | **Required:** `Intent`, `Name`<br> **Optional:** `Years`, `Quantity`, `Purchase-Type`                                              |
|                           | `Get-Registration-Fees`                                      | Gets the registration fees for a name.                                                                                | **Required:** `Name`                                                                                                               |
|                           | `Redelegation-Fee`                                           | Retrieves the fee in mARIO for redelegating stake.                                                                    | **Optional:** `Address` (defaults to `From`)                                                                                       |
| **Primary Names**         | `Primary-Name`                                               | Resolves a name or address to its primary name details.                                                               | **Required:** `Name`or `Address`                                                                                                   |
|                           | `Primary-Names` or `Paginated-Primary-Names`                 | Lists all primary names, with pagination support.                                                                     | **Optional:** `Cursor`, `Limit`, `SortBy`, `SortOrder`                                                                             |
|                           | `Primary-Name-Request`                                       | Requests a primary name for an address.                                                                               | **Required:** `Name` <br> **Optional:** `Fund-From`                                                                                |
|                           | `Approve-Primary-Name-Request`                               | Approves a primary name request for an address.                                                                       | **Required:** `Name`, `Recipient`                                                                                                  |
|                           | `Remove-Primary-Names`                                       | Removes primary names associated with an address.                                                                     | **Required:** `Names`                                                                                                              |
|                           | `Primary-Name-Requests` or `Paginated-Primary-Name-Requests` | Lists primary name requests with pagination support.                                                                  | **Optional:** `Cursor`, `Limit`, `SortBy`, `SortOrder`                                                                             |
| **Demand Factor**         | `Demand-Factor`                                              | Retrieves the current demand factor.                                                                                  | None                                                                                                                               |
|                           | `Demand-Factor-Info`                                         | Provides detailed information about the demand factor.                                                                | None                                                                                                                               |
|                           | `Demand-Factor-Settings`                                     | Returns the demand factor configuration settings.                                                                     | None                                                                                                                               |
| **Critical Handlers**     | `Tick`                                                       | Ticks and distributes rewards for epochs; discards memory on error.                                                   | **Required:** `Block-Height`, `Hash-Chain`                                                                                         |
|                           | `Prune`                                                      | Prunes outdated or invalid data from the system; discards memory on error.                                            | None                                                                                                                               |
|                           | `Sanitize`                                                   | Validates inputs and updates the last known message timestamp; discards memory on error.                              | None                                                                                                                               |
| **Utilities**             | `Pruning-Timestamps`                                         | Retrieves the next pruning timestamps for various data types.                                                         | None                                                                                                                               |
|                           |

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

To load the module into the `aos`REPL, run the following command:

```sh
aos --load src/main.lua
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

And add the package to the `dependencies`table in the `ar-io-ao-0.1-1.rockspec`file.

```lua
-- rest of the file
dependencies = {
    "lua >= 5.3",
    "luaunit >= 3.3.0",
    "<package>"
}
```

### Deployment

Merging to develop or main will evolve the devnet or testnet contract to the next version. The script managing the logic is located at `tools/evolve.mjs`, which uses aoconnect to perform an `Eval` action. The deployment process is automated using Github Actions.

[contract whitepaper]: https://ar.io/whitepaper
