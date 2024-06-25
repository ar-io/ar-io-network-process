# AO/IO Contract

[![codecov](https://codecov.io/github/ar-io/ao-pilot/graph/badge.svg?token=0VUJ3RH9X1)](https://codecov.io/github/ar-io/ao-pilot)

The implementation of the ar.io network contract is written in lua and deployed as an AO process on Arweave. The contract is responsible for managing the network state, handling transactions, and enforcing the network rules. Refer to the [contract whitepaper] for more details on the network rules and the contract design.

## Contract Spec

### Action Map Handlers Specification

#### General Structure

Each handler is identified by an action name and it has required and optional tags for its input. The handlers can be categorized into "read" and "write" operations.

#### Action Map

```lua
local ActionMap = {
    -- reads
    Info = "Info",
    State = "State",
    Transfer = "Transfer",
    Balance = "Balance",
    Balances = "Balances",
    DemandFactor = "Demand-Factor",
    DemandFactorSettings = "Demand-Factor-Settings",
    -- EPOCH READ APIS
    Epochs = "Epochs",
    Epoch = "Epoch",
    EpochSettings = "Epoch-Settings",
    PrescribedObservers = "Epoch-Prescribed-Observers",
    PrescribedNames = "Epoch-Prescribed-Names",
    Observations = "Epoch-Observations",
    Distributions = "Epoch-Distributions",
    -- NAME REGISTRY READ APIS
    Record = "Record",
    Records = "Records",
    ReservedNames = "Reserved-Names",
    ReservedName = "Reserved-Name",
    TokenCost = "Token-Cost",
    -- GATEWAY REGISTRY READ APIS
    Gateway = "Gateway",
    Gateways = "Gateways",
    GatewayRegistrySettings = "Gateway-Registry-Settings",
    -- writes
    CreateVault = "Create-Vault",
    VaultedTransfer = "Vaulted-Transfer",
    ExtendVault = "Extend-Vault",
    IncreaseVault = "Increase-Vault",
    BuyRecord = "Buy-Record",
    ExtendLease = "Extend-Lease",
    IncreaseUndernameLimit = "Increase-Undername-Limit",
    JoinNetwork = "Join-Network",
    LeaveNetwork = "Leave-Network",
    IncreaseOperatorStake = "Increase-Operator-Stake",
    DecreaseOperatorStake = "Decrease-Operator-Stake",
    UpdateGatewaySettings = "Update-Gateway-Settings",
    SaveObservations = "Save-Observations",
    DelegateStake = "Delegate-Stake",
    DecreaseDelegateStake = "Decrease-Delegate-Stake",
}
```

### Handlers and Their Tags

#### 1. Transfer

- **Required Tags**:
  - `Recipient`: Valid Arweave address
  - `Quantity`: Integer greater than 0
- **Optional Tags**:
  - `X-*`: Tags beginning with "X-" are forwarded.

#### 2. CreateVault

- **Required Tags**:
  - `Lock-Length`: Integer greater than 0
  - `Quantity`: Integer greater than 0

#### 3. VaultedTransfer

- **Required Tags**:
  - `Recipient`: Valid Arweave address
  - `Lock-Length`: Integer greater than 0
  - `Quantity`: Integer greater than 0

#### 4. ExtendVault

- **Required Tags**:
  - `VaultId`: Valid Arweave address
  - `ExtendLength`: Integer greater than 0

#### 5. IncreaseVault

- **Required Tags**:
  - `Vault-Id`: Valid Arweave address
  - `Quantity`: Integer greater than 0

#### 6. BuyRecord

- **Required Tags**:
  - `Name`: String
  - `Purchase-Type`: String
  - `Process-Id`: Valid Arweave address
  - `Years`: Integer between 1 and 5

#### 7. ExtendLease

- **Required Tags**:
  - `Name`: String
  - `Years`: Integer between 1 and 5

#### 8. IncreaseUndernameLimit

- **Required Tags**:
  - `Name`: String
  - `Quantity`: Integer between 1 and 9990

#### 9. TokenCost

- **Required Tags**:
  - `Intent`: Must be valid registry interaction (e.g., BuyRecord, ExtendLease, IncreaseUndernameLimit)
- **Optional Tags**:
  - `Years`: Integer between 1 and 5
  - `Quantity`: Integer greater than 0

#### 10. JoinNetwork

- **Required Tags**:
  - `Operator-Stake`: Quantity
- **Optional Tags**:
  - `Label`, `Note`, `FQDN`, `Port`, `Protocol`, `Allow-Delegated-Staking`, `Min-Delegated-Stake`, `Delegate-Reward-Share-Ratio`, `Properties`, `Auto-Stake`, `Observer-Address`

#### 11. LeaveNetwork

- **No specific tags required**

#### 12. IncreaseOperatorStake

- **Required Tags**:
  - `Quantity`: Integer greater than 0

#### 13. DecreaseOperatorStake

- **Required Tags**:
  - `Quantity`: Integer greater than 0

#### 14. DelegateStake

- **Required Tags**:
  - `Target`: Valid Arweave address
  - `Quantity`: Integer greater than 0

#### 15. DecreaseDelegateStake

- **Required Tags**:
  - `Target`: Valid Arweave address
  - `Quantity`: Integer greater than 0

#### 16. UpdateGatewaySettings

- **Optional Tags**:
  - `Label`, `Note`, `FQDN`, `Port`, `Protocol`, `Allow-Delegated-Staking`, `Min-Delegated-Stake`, `Delegate-Reward-Share-Ratio`, `Properties`, `Auto-Stake`, `Observer-Address`

#### 17. SaveObservations

- **Required Tags**:
  - `Report-Tx-Id`: Valid Arweave address
  - `Failed-Gateways`: Comma-separated string of valid Arweave addresses

#### 18. EpochSettings, DemandFactorSettings, GatewayRegistrySettings

- **No specific tags required**

#### 19. Info, State, Gateways, Gateway, Balances, Balance, DemandFactor, Record, Records, Epoch, Epochs, PrescribedObservers, Observations, PrescribedNames, Distributions, ReservedNames, ReservedName

- **No specific tags required**

## Developers

### Requirements

- Lua 5.3 - [Download](https://www.lua.org/download.html)
- Luarocks - [Download](https://luarocks.org/)

### Lua Setup (MacOS)

1. Clone the repository and navigate to the project directory.
1. Install `lua`
   - `brew install lua@5.3`
1. Add the following to your `.zshrc` or `.bashrc` file:

   ```bash
   echo 'export LDFLAGS="-L/usr/local/opt/lua@5.3/lib"' >> ~/.zshrc
   echo 'export CPPFLAGS="-I/usr/local/opt/lua@5.3/include"' >> ~/.zshrc
   echo 'export PKG_CONFIG_PATH="/usr/local/opt/lua@5.3/lib/pkgconfig"' >> ~/.zshrc
   echo 'export PATH="/usr/local/opt/lua@5.3/bin:$PATH"' >> ~/.zshrc
   ```

1. Run `source ~/.zshrc` or `source ~/.bashrc` to apply the changes.
1. Run `lua -v` to verify the installation.

### LuaRocks Setup

1. Install `luarocks`

   ```bash
   curl -R -O http://luarocks.github.io/luarocks/releases/luarocks-3.9.1.tar.gz
   tar zxpf luarocks-3.9.1.tar.gz
   cd luarocks-3.9.1
   ./configure --with-lua=/usr/local/opt/lua@5.3 --with-lua-include=/usr/local/opt/lua@5.3/include
   make build
   sudo make install
   ```

1. Check the installation by running `luarocks --version`.
1. Check the LuaRocks configuration by running `luarocks config | grep LUA`

If you ever need to refresh .luarocks, run the following command:

```sh
luarocks purge && luarocks install ar-io-ao-0.1-1.rockspec
```

### aos

To load the module into the `aos` REPL, run the following command:

```sh
aos --load src/main.lua
```

### Code Formatting

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

To see the test coverage, run the following command:

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
