## State Extraction

### create_liquid_balances_csv

This tool creates a CSV file with the liquid balances from the $ARIO airdrop process. Wallets that selected 'wallet' when registering receive no additional mARIO.

Wallets that selected 'stake' receive 25% more mARIO and are assigned to a gateway. The assignment is based on the hash of the wallet address modulo the number of gateways.

To run:

```bash
node create_liquid_balances_csv.mjs --processId <processId> --output <outputFile> --gatewaysFile <gatewaysFile> --stakedMultiplier <stakedMultiplier>
```

#### Output files

Liquid wallets: (./files/liquid_balances.csv)

```csv
address,mARIOQty
```

Staked wallets (./files/assigned_delegates.csv)

```csv
gatewayAddress,delegateAddress,delegateStake
```

### create_gateways_csv

This tool creates a CSV file with the gateways for the airdrop.

To run:

```bash
node create_gateways_csv.mjs --processId <processId> --output <outputFile>
```

#### Output file

(./files/gateways.csv)

```csv
gatewayAddress,observerAddress,operatorStake,fqdn,port,protocol,allowDelegatedStaking,delegateRewardShareRatio,allowedDelegates,minDelegatedStake,autoStake,label,note,properties,status,failedConsecutiveEpochsCount
```

### create_primary_names_csv

This tool creates a CSV file with the primary names for the airdrop.

To run:

```bash
node create_primary_names_csv.mjs --processId <processId> --output <outputFile>
```

#### Output file

(./files/primary_names.csv)

```csv
name,address,processId
```

### create_arns_records_csv

This tool creates a CSV file with the ARNS records for the airdrop.

To run:

```bash
node create_arns_records_csv.mjs --processId <processId> --output <outputFile>
```

#### Output file

(./files/arns_records.csv)

```csv
name,processId,type,startTimestamp,endTimestamp,purchasePrice
```

## State Creation (as raw Lua)

## TODO: Scripts to create the state in raw lua format
