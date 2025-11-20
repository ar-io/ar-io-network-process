# Type Errors Report

Generated: 2025-11-20 (Updated after type annotations)

## Summary

After adding comprehensive type annotations to the codebase via `src/types.lua` and configuring the Lua Language Server with strict type checking, we now have clear visibility into type issues.

**Total Linter Issues:** 633 across 16 files
- **Errors:** 1 (Missing Target field)
- **Warnings:** 632 (mostly duplicate definitions and type mismatches)

---

## Critical Issues

### 1. Missing Target Field (ERROR)

**File:** `src/main.lua:1735`
**Severity:** Error
**Issue:** Missing required fields in type `SendResponse`: `Target`

**Current Code:**
```lua
Send(msg, {
    Action = "Total-Supply",
    Data = tostring(totalSupplyDetails.totalSupply),
    Ticker = Ticker,
})
```

**Fix Needed:**
```lua
Send(msg, {
    Target = msg.From,  -- ADD THIS
    Action = "Total-Supply",
    Data = tostring(totalSupplyDetails.totalSupply),
    Ticker = Ticker,
})
```

---

## Type Safety Issues

### 2. RawMessage vs ParsedMessage Type Mismatch (WARNING)

**File:** `src/main.lua:536`
**Severity:** Warning
**Issue:** Cannot assign `ParsedMessage` to parameter `RawMessage`

**Current Code:**
```lua
addEventingHandler("sanitize", function()
    return "continue"
end, function(msg)
    assertAndSanitizeInputs(msg)  -- expects RawMessage, gets ParsedMessage
    updateLastKnownMessage(msg)
end, CRITICAL, false)
```

**Analysis:**
The `sanitize` handler receives a `ParsedMessage` from the handler system, but `assertAndSanitizeInputs` expects a `RawMessage`. This is actually correct behavior - the handler mutates the message in place, converting it from raw to parsed. We need to either:
- Option A: Use type casting `---@type RawMessage` 
- Option B: Make the function accept both types
- Option C: Adjust the type definitions to reflect the mutation pattern

### 3. Function Type Mismatch in utils.lua (WARNING)

**File:** `src/utils.lua:498`
**Severity:** Warning
**Issue:** Cannot assign `function` to parameter `Stream`

Needs investigation of the specific function and Stream type definition.

### 4. Return Value Count Mismatch (WARNING)

**File:** `src/utils.lua:770`
**Severity:** Warning
**Issue:** Annotations specify at least 2 return values required, found 1

Function annotations don't match actual implementation.

---

## Documentation Issues (Duplicate Definitions)

### Duplicate Type Definitions (629 warnings)

These warnings occur because types are defined in both:
1. **Centralized:** `src/types.lua` (single source of truth)
2. **Local:** Individual files (contextual documentation)

**Affected Files:**
- `src/types.lua` - 245 duplicates (expected, as this is where duplicates originate)
- `src/gar.lua` - 137 duplicates
- `src/epochs.lua` - 63 duplicates
- `src/arns.lua` - 56 duplicates
- `src/primary_names.lua` - 28 duplicates
- `src/main.lua` - 16 duplicates
- `src/demand.lua` - 17 duplicates
- `src/token.lua` - 19 duplicates
- Others: 48 duplicates

**Options to Resolve:**
1. **Keep Both** (Recommended for documentation)
   - Pros: Better local context, easier to understand code
   - Cons: Duplicate definition warnings
   - Action: Add `---@diagnostic disable: duplicate-doc-field` to suppress warnings

2. **Remove Local Definitions**
   - Pros: No warnings, single source of truth
   - Cons: Loss of local context, harder to read
   - Action: Remove all type definitions from individual files

3. **Hybrid Approach**
   - Keep essential local docs, remove redundant ones
   - Use `@see` comments to reference types.lua

### Duplicate Parameter Names (2 warnings)

**File:** `src/utils.lua:690, 697`
**Issue:** Duplicate params `table` in validateAndSanitizeInputs

The parameter is named `table` (which shadows the global), and annotations mention it twice.

---

## Message Type System (NEW)

### Type Flow

We now have a clear type hierarchy for messages:

```
RawMessage (as received from ao)
    ↓ assertAndSanitizeInputs()
MessageTags (typed, sanitized tags)
    ↓
ParsedMessage (with typed tags, handlers receive this)
```

### MessageTags Type

Comprehensive type definition for tags after sanitization:

**Address Tags** (formatted as WalletAddress):
- `Recipient`, `Initiator`, `Target`, `Source`, `Address`
- `Vault-Id`, `Process-Id`, `Observer-Address`

**Number Tags** (converted to number):
- `Quantity`, `Lock-Length`, `Operator-Stake`, `Delegated-Stake`
- `Withdraw-Stake`, `Years`, `Port`, `Extend-Length`
- `Min-Delegated-Stake`, `Delegate-Reward-Share-Ratio`
- `Epoch-Index`, `Price-Interval-Ms`, `Block-Height`

**Boolean Tags** (converted to boolean):
- `Allow-Unsafe-Addresses`, `Force-Prune`, `Revokable`

**String Tags** (remain as string):
- `Name`, `Label`, `Note`, `FQDN`, `Purchase-Type`, `Fund-From`, `Intent`
- All other unknown tags

### Benefits

✅ **Type Safety:** Handlers know exact types of tag values
✅ **Autocomplete:** IDE suggests available tags and their types
✅ **Error Detection:** Type mismatches caught at development time
✅ **Documentation:** Self-documenting code with inline types

---

## Configuration Files

### Updated
- ✅ `.luarc.json` - Type checking with `assign-type-mismatch: Error!`
- ✅ `.vscode/settings.json` - Strict error reporting
- ✅ `src/types.lua` - 477 lines of comprehensive type definitions
- ✅ All `src/*.lua` files - `require(".src.types")` added

### Type Definitions Added
- 10 primitive type aliases
- 3 message type classes (RawMessage, MessageTags, ParsedMessage)
- 2 Send response types
- 8 vault-related types
- 14 gateway-related types
- 15 epoch-related types
- 11 ArNS types
- 7 primary names types
- 2 demand factor types
- 8 funding/token cost types
- 2 prune result types

---

## Recommendations

### Immediate Action Items

1. **Fix Missing Target** (line 1735)
   - Add `Target = msg.From` to the Send call
   
2. **Review Type Mismatch** (line 536)
   - Decide on proper typing for message mutation pattern
   
3. **Decide on Duplicates Strategy**
   - Option A: Suppress warnings with diagnostic disable
   - Option B: Remove local type definitions
   - Option C: Hybrid approach

### Optional Improvements

4. **Fix utils.lua Issues**
   - Investigate Stream type mismatch (line 498)
   - Fix return value count annotation (line 770)
   - Rename `table` parameter to avoid shadowing global

5. **Clean Up Send Function Annotations** (lines 99-108)
   - Fix undefined param warnings
   - Consolidate duplicate field definitions

---

## Questions for Review

1. **Missing Target Field:** Should we add `Target = msg.From` to line 1735?

2. **Duplicate Definitions:** What's your preference?
   - Keep both for documentation?
   - Remove local definitions?
   - Suppress warnings?

3. **Type Mutation Pattern:** How should we handle the RawMessage → ParsedMessage mutation?
   - Accept the warning?
   - Add type casting?
   - Change the type definitions?

4. **Priority:** Are there any other type-related issues you want addressed?

---

## What's Working ✅

- All type definitions are in place
- Message flow is properly typed
- Handlers receive ParsedMessage with typed MessageTags
- IDE autocomplete and type checking is functional
- No critical runtime-breaking type errors (except the 1 missing Target field)
