Deceision outcome

Testing 4 different patterns:
ybP3X8DIU7KjVaMOlJL8ogIIRJEaAM4hLy24HbfKHdY- message 10k balances using msg.Data

Module ID: Do_Uc2Sju_ffp6Ev0AnLVdPtot15rvMjP-a9VVaA5fM
Initial code loaded: 927.8310546875 KiB (<1Mb)
WASM allocated memory before balances loaded: 143523840 bytes (143.52MB)
WASM allocated memory after balances loaded: 143523840 bytes (143.52MB)
Internal memory before balances loaded: 927.8310546875 KiB (<1Mb)
Internal memory after balances loaded: 6195.5556640625 KiB (6.2MB)
Message ID: https://www.ao.link/#/message/hg-M36ZKjf_XaKi9H2-4sjFDtqkJfh5ojuseDFTAGJA

2fLRznGR5ZnhEUhBZjXmcDiKHlZYaQOEOnTJuIw6ujA - batch message 10K balances

Module ID: Do_Uc2Sju_ffp6Ev0AnLVdPtot15rvMjP-a9VVaA5fM
Initial code loaded: 928.9208984375 KiB (<1Mb)
WASM allocated memory after load: TBD
Internal memory after load: TBD

nTyHNeqlW7aIWxh8TXT7xHgcjBWk3Z9MJ4WT5QxD948 - load 10k balances using eval
Module ID: Do_Uc2Sju_ffp6Ev0AnLVdPtot15rvMjP-a9VVaA5fM
Initial code loaded: 928.9208984375 KiB (<1Mb)
WASM allocated memory before balances loaded: 143523840 bytes (<143.52MB)
WASM allocated memory after balances loaded: 143523840 bytes (143.52MB)
Internal memory before balances loaded: 928.9208984375 KiB (<1Mb)
Internal memory after balances loaded: 3604.8671875 KiB (3.52MB)

Message ID: https://www.ao.link/#/message/gvSOosZ4S2-Lc9b3tc4TnawP7DtCZlJ05fO-Vj2MNTo

TBD - custom module with balances prebaked

Initial code loaded: TBD

TINY MODULE

initial wasm: 1572864 bytes
internal memory: 644.9833984375 KiB
internal memory after code loaded: 651.9609375

TINY MODULE 2
id oIBhps9lS1YcPudcGRoxfMKWPsfiMXjSRo1dsecp4HI
module id \_wSmbjfSlX3dZNcqE8JqKmj-DKum9uQ_jB08LwOKCyw
initial wasm memory: 1572864
initial process size: 642.0849609375
internal memory after code loaded: 649.044921875

TLDR - we dont have enough initial allocated stack/heap for these small modules

msg.Data load
process id: KLSXAJmRRwliR7z3O39dob7o1jq556ETYYzl2xHvkjw
module id: QaFZv0WNt0eLhwJz65-y3_f4L6jaHftyelZipvcJkyc
initial wasm memory: 10485760 (10MB)
internal memory before code: 501.2314453125
internal memory after code: 508.703125
internal memory after balances loaded: 4210.8134765625 (4.2MB)
wasm memory after balances loaded: 26279936 (26MB) --> post Balances call --> 26279936

Custom module
module id: 0fcMQ9l30Z3TVHnpb0rb6BF3lHKNG-3e9d7pJE5A6fs
id: WOgEQEf1ZgFbtgdlXYNT8fJU3FJqXdwAK_2yIiqDFfg
initial process memory: 1225.1806640625
initial wasm memory: 10485760~

Custom module
module id: kr4OjBJoW1csoo3Ifd6wmDDfntuby5WLv5c3niOqoUA
initial process memory: 1226.267578125
initial wasm memory: 10485760 (10MB)
internal memory after bootstrap occurred: 3538.4560546875 (3.5MB)
wasm memory after bootstrap occurred: 12582912 (12MB) --> post balances --> 26279936 (26MB)

FINDING; the balances handler sends back data, and memory is not cleaned up until the next write message

Takeaways:
the approach of building the lua from CSVs
transpile the csv into prebaked lua
add custom handlers to instantiated the state

We added 'main.lua' to the module, build it and then executed the handler to add those variables to state

```lua

--- process.lua file in ao
Handlers.once("_boot",
    function (msg)
        return msg.Tags.Type == "Process" and Owner == msg.From
    end,
    function()
        require('.boot')(ao)
        -- DROP IN MAIN FILE WITH ALL BOOTSTRAPPED SOURCE CODE AND LUA STATE FILES
        require('.main')
    end
)

--- THESE TWO APPROACHES RESULT IN SAME MEMORY USAGE (both wasm and internal memory)

--- custom main.lua file
Balances  = Balances or initializeBalances()
local function initializeBalances()
    Balances = {}
    require(".bootstrap") -- includes all the airdropped balances
    return Balances
end

-- if we wanted to put it behind a handler, if we wanted to wait to do this post process creation
Balances = Balances or {}
Handlers.add("bootstrap", "Bootstrap", function(msg)
    assert(Balances == nil or next(Balances) == nil, "Balances already initialized")
    Balances = {}
    require(".bootstrap")
    msg.reply({
        Target = msg.From,
        ["Status"] = "OK",
    })
end)
```

module id:
initial internal memory: 2322.44921875
initial wasm memory: 12582912 --> post balances --> 26279936
