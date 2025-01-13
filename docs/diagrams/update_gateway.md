# UpdateGateway

```
graph TD
    classDef redBorder stroke:#ff0000,stroke-width:2px;
    Init[Initialize updateGatewaySettings] --> ValidateInput{Validate Input}
    ValidateInput -- Invalid input --> Error[Throw ContractError]
    ValidateInput -- Valid input --> CheckGateway{Check Gateway Exists}
    CheckGateway -- Exists --> CheckDelegatedStakingDisabled{Check If Delegate Staking is disabled and active delegates}
    CheckGateway -- Doesn't Exist --> Error
    CheckDelegatedStakingDisabled -- Disabled delegated staking and active delegates --> FullDelegatedStakeWithdraw[Fully withdraw each delegated staker]
    CheckDelegatedStakingDisabled -- No change --> UpdateSettings[Update gateway settings]
    UpdateSettings --> End
    FullDelegatedStakeWithdraw -- Create vaults for each delegate --> DeductGatewayDelegatedStake[Deduct gateway's total delegated state]
    DeductGatewayDelegatedStake -- Gateway delegated stake decremented --> UpdateSettings
    End
    class Error redBorder
```
