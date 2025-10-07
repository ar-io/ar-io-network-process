# Handlers That Modify Balances

## Direct Balance Modification Handlers

### 1. Transfer

**Handler**: `ActionMap.Transfer`  
**Action**: Transfers tokens from sender to recipient  
**Balance Changes**: Sender balance ↓, Recipient balance ↑

### 2. CreateVault

**Handler**: `ActionMap.CreateVault`  
**Action**: Locks tokens in a time-locked vault for the sender  
**Balance Changes**: Sender balance ↓

### 3. VaultedTransfer

**Handler**: `ActionMap.VaultedTransfer`  
**Action**: Creates a time-locked vault for a recipient  
**Balance Changes**: Sender balance ↓

### 4. RevokeVault

**Handler**: `ActionMap.RevokeVault`  
**Action**: Controller revokes a vaultedTransfer before it matures  
**Balance Changes**: Controller balance ↑

### 5. IncreaseVault

**Handler**: `ActionMap.IncreaseVault`  
**Action**: Adds more tokens to an existing vault  
**Balance Changes**: Sender balance ↓

## Gateway/Staking Handlers

### 6. JoinNetwork

**Handler**: `ActionMap.JoinNetwork`  
**Action**: Gateway joins the network with operator stake  
**Balance Changes**: Operator balance ↓

### 7. IncreaseOperatorStake

**Handler**: `ActionMap.IncreaseOperatorStake`  
**Action**: Increases gateway operator stake  
**Balance Changes**: Operator balance ↓

### 8. DecreaseOperatorStake

**Handler**: `ActionMap.DecreaseOperatorStake`  
**Action**: Decreases operator stake (with optional instant withdrawal)  
**Balance Changes**: Operator balance ↑ (if instant withdrawal with penalty)

### 9. DelegateStake

**Handler**: `ActionMap.DelegateStake`  
**Action**: Delegates stake to a gateway  
**Balance Changes**: Delegator balance ↓

### 10. DecreaseDelegateStake

**Handler**: `ActionMap.DecreaseDelegateStake`  
**Action**: Decreases delegated stake (with optional instant withdrawal)  
**Balance Changes**: Delegator balance ↑ (if instant withdrawal with penalty)

### 11. InstantWithdrawal

**Handler**: `ActionMap.InstantWithdrawal`  
**Action**: Instantly withdraws from a pending withdrawal vault with penalty  
**Balance Changes**: Withdrawer balance ↑, Protocol balance ↑ (penalty fee)

### 12. CancelWithdrawal

**Handler**: `ActionMap.CancelWithdrawal`  
**Action**: Cancels a withdrawal and returns to staked status  
**Balance Changes**: No direct balance change (stake → vault → stake)

## ArNS Name Handlers

### 13. BuyName

**Handler**: `ActionMap.BuyName`  
**Action**: Purchases an ArNS name (lease or permabuy)  
**Balance Changes**: Buyer balance ↓ (via funding plan), Protocol balance ↑, Returned name initiator balance ↑ (if applicable)

### 14. ExtendLease

**Handler**: `ActionMap.ExtendLease`  
**Action**: Extends an ArNS name lease  
**Balance Changes**: Owner balance ↓ (via funding plan), Protocol balance ↑

### 15. IncreaseUndernameLimit

**Handler**: `ActionMap.IncreaseUndernameLimit`  
**Action**: Increases undername limit for an ArNS name  
**Balance Changes**: Owner balance ↓ (via funding plan), Protocol balance ↑

### 16. UpgradeName

**Handler**: `ActionMap.UpgradeName`  
**Action**: Upgrades a leased name to permabuy  
**Balance Changes**: Owner balance ↓ (via funding plan), Protocol balance ↑

## Primary Name Handlers

### 17. RequestPrimaryName

**Handler**: `ActionMap.RequestPrimaryName`  
**Action**: Creates a primary name request  
**Balance Changes**: Requester balance ↓ (via funding plan), Protocol balance ↑

## System/Automatic Operations

### 18. Epoch Distribution

**Handler**: Automatic via `distributeEpoch`  
**Action**: Distributes rewards to gateways and delegates  
**Balance Changes**: Protocol balance ↓, Gateway operator balances ↑ (or stakes ↑ if auto-stake), Delegate stakes ↑

### 19. Vault Pruning

**Handler**: Automatic via `vaults.pruneVaults`  
**Action**: Releases matured balance vaults  
**Balance Changes**: Vault owner balance ↑

### 20. Gateway Vault Pruning

**Handler**: Automatic via gateway pruning  
**Action**: Releases matured gateway exit/withdrawal vaults  
**Balance Changes**: Gateway operator balance ↑, Delegate balances ↑

### 21. Slashing

**Handler**: Via `gar.slashOperatorStake`  
**Action**: Slashes operator stake for repeated failures  
**Balance Changes**: Gateway operator stake ↓, Protocol balance ↑

---

**Note**: Handlers with "funding plan" support can draw from multiple sources (balance, delegated stakes, vaults) using `gar.applyFundingPlan()`, which orchestrates the necessary balance reductions across different sources.
