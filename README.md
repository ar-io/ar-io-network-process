# AO/IO Contract

[![codecov](https://codecov.io/github/ar-io/ao-pilot/graph/badge.svg?token=0VUJ3RH9X1)](https://codecov.io/github/ar-io/ao-pilot)

The implementation of the ar.io network contract is written in lua and deployed as an AO process on Arweave. The contract is responsible for managing the network state, handling transactions, and enforcing the network rules. Refer to the [contract whitepaper] for more details on the network rules and the contract design.

## Contract Spec

### Arweave Name Service (ArNS)

- `BuyRecord` - buy a record
- `ExtendLease` - extend the lease of a record
- `IncreaseUndernameLimit` - increase the undername limit of a record

### Gateway Registry

- `JoinNetwork` - join a network
- `LeaveNetwork` - leave a network
- `UpdateGatewaySettings` - update a gateway settings
- `IncreaseOperatorStake`- increase operator stake
- `DecreaseOperatorStake` - decrease operator stake
- `DelegateStake` - delegate stake to an existing gateway
- `DecreaseDelegatedStake` - decrease delegated stake to an existing gateway

### Observer Incentive Protocol (OIP)

- `SaveObservations` - save observations for a given epoch
- `Observations` - get observations for a given Epoch
- `PrescribedObservers` - get prescribed observers for a given Epoch
- `PrescribedNames` - get prescribed names for a given Epoch

### Epoch

- `Epoch` - get epoch details
- `Epochs` - get all epochs

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
