## State Extraction and Creation

Each section supports extraction of state from existing AO processes, and creation of raw lua representing that state.

To run all the scripts:

```bash
npm run extract:all
npm run lua:all
```

---

### Balances

This tool creates a CSV file with the liquid balances from the $ARIO airdrop process. Wallets that selected 'wallet' when registering receive no additional mARIO.

Wallets that selected 'stake' receive 25% more mARIO and are assigned to a gateway. The assignment is based on the hash of the wallet address modulo the number of gateways.

To run:

```bash
node balances/extract.mjs --processId <processId> --output <outputFile>
```

#### Output files

Liquid wallets: [./balances/outputs/liquid_balances.csv](./balances/outputs/liquid_balances.csv)

```csv
address,mARIOQty
```

To create the lua file from the csv file:

```bash
node balances/lua.mjs --input <inputFile> --output <outputFile>
```

Resulting lua file: [./balances/outputs/balances.lua](./balances/outputs/balances.lua)

```lua
Balances["<address>"] = <mARIOQty>
```

### Gateways

This tool creates a CSV file with the gateways for the airdrop. It also creates a lua file with the gateways and their assigned delegates.

To run:

```bash
node gateways/extract.mjs --processId <processId> --output <outputFile>
```

Resulting CSV file: [./gateways/outputs/gateways.csv](./gateways/outputs/gateways.csv)

```csv
gatewayAddress,observerAddress,operatorStake,fqdn,port,protocol,allowDelegatedStaking,delegateRewardShareRatio,allowedDelegates,minDelegatedStake,autoStake,label,note,properties,status,failedConsecutiveEpochsCount
```

To create the lua file from the csv file:

```bash
node gateways/lua.mjs --input <inputFile> --output <outputFile>
```

Resulting lua file: [./gateways/outputs/gateways.lua](./gateways/outputs/gateways.lua)

```lua
-- for every gateway in the input file
GatewayRegistry["<gatewayAddress>"] = {
    observerAddress = "<observerAddress>",
    operatorStake = <operatorStake>,
    startTimestamp = <startTimestamp>,
    totalDelegatedStake = 0,
    settings = {
        fqdn = "<fqdn>",
        port = <port>,
        note = "<note>",
        label = "<label>",
        protocol = "<protocol>",
        properties = "<properties>",
        minDelegatedStake = <minDelegatedStake>,
        allowDelegatedStaking = <allowDelegatedStaking>,
        delegateRewardShareRatio = <delegateRewardShareRatio>,
        autoStake = <autoStake>,
        allowedDelegates = {},
    },
    delegates = {},
    vaults = {},
    services = {},
    status = "<status>",
    weights = {
        compositeWeight = <compositeWeight>,
        normalizedCompositeWeight = <normalizedCompositeWeight>,
        stakeWeight = <stakeWeight>,
        tenureWeight = <tenureWeight>,
        gatewayPerformanceRatio = <gatewayPerformanceRatio>,
        observerPerformanceRatio = <observerPerformanceRatio>,
    },
    stats = {
        prescribedEpochCount = <prescribedEpochCount>,
        observedEpochCount = <observedEpochCount>,
        totalEpochCount = <totalEpochCount>,
        passedEpochCount = <passedEpochCount>,
        failedEpochCount = <failedEpochCount>,
        failedConsecutiveEpochs = <failedConsecutiveEpochs>,
        passedConsecutiveEpochs = <passedConsecutiveEpochs>,
    },
}
```

---

### Delegates

This tool creates a CSV file with the delegates for the airdrop. It also creates a lua file with the delegates and their assigned gateways.

To run:

```bash
node delegates/extract.mjs --output <outputFile> --gateways-file <gatewaysFile>
```

Resulting CSV file: [./delegates/outputs/delegates.csv](./delegates/outputs/delegates.csv)

```csv
gatewayAddress,delegateAddress,delegateStake
```

To create the lua file from the csv file:

```bash
node delegates/lua.mjs --input <inputFile> --output <outputFile>
```

Resulting lua file: [./delegates/outputs/delegates.lua](./delegates/outputs/delegates.lua)

Lua file content:

```lua
GatewayRegistry["<gatewayAddress>"].delegates["<delegateAddress>"] = { delegatedStake = <delegatedStake>, startTimestamp = <startTimestamp>, vaults = {} },
-- ...
-- Update the total delegated stake on the gateway after all delegates have been added
GatewayRegistry["<gatewayAddress>"].totalDelegatedStake = <totalDelegatedStake>,
```

---

### Primary Names

This tool creates a CSV file with the primary names for the airdrop.

To run:

```bash
node records/extract.mjs --processId <processId> --output <outputFile>
```

Resulting CSV file: [./records/outputs/primary_names.csv](./records/outputs/primary_names.csv)

```csv
name,address,processId
```

To create the lua file from the csv file:

```bash
node records/lua.mjs --input <inputFile> --output <outputFile>
```

Resulting lua file: [./records/outputs/primary_names.lua](./records/outputs/primary_names.lua)

```lua
PrimaryNames.owners["<address>"] = {
    name = "<name>",
    startTimestamp = <startTimestamp>,
}
PrimaryNames.names["<name>"] = "<address>"
```

---

### ARNS Records

This tool creates a CSV file with the ARNS records for the airdrop.

To run:

```bash
node records/extract.mjs --processId <processId> --output <outputFile>
```

Resulting CSV file: [./records/outputs/arns_records.csv](./records/outputs/arns_records.csv)

```csv
name,processId,type,startTimestamp,endTimestamp,purchasePrice
```

Generate the lua file from the csv file:

```bash
node records/lua.mjs --input <inputFile> --output <outputFile>
```

Resulting lua file: [./records/outputs/arns_records.lua](./records/outputs/arns_records.lua)

```lua
NameRegistry.records["<name>"] = {
    processId = "<processId>",
    type = "<type>",
    startTimestamp = <startTimestamp>,
    endTimestamp = <endTimestamp>,
    purchasePrice = <purchasePrice>,
}
```

// TODO: vaults
// Create a boot.lua that takes all the generated lua and requires it
