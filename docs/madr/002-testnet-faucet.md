# MADR-002: Testnet Faucet

- Status: proposed
- Deciders: [Ariel], [Dylan], [Atticus], [Phil], [John]
- Date: 2025-03-27
- Authors: [Dylan]

## Requirements

- Easy onboarding to users/projects looking to interact with ArNS
- Tight integration and support with ar-io-gateways and ar-io-sdk
- Extensible to support other interactions/use cases
- Ability to mint $ARIO for internal testing purposes
- Decent enough protection against abuse

## Separate process for interacting/managing $ARIO balances

Create a separate process for interacting/managing $ARIO balances and pruning on a timed bases. It would be "allocated" $ARIO on an interval and store balances of testnet users locally. It would then be able to prune balances of users that haven't interacted with the testnet for a period of time.

Pros:

- Can be shared with community and used by other projects
- Logic separated from main repo
- Allows for more robust and flexible implementation if needed

Cons:

- More overhead - repo/code to manage
- Separate repo/ci pipeline for reviewing
- Not useful for our own reusability
- Dependency between faucet process and $ARIO process and ar-io-sdk
- Dependency on $ARIO process to give balance to faucet process

## Integrated feature flag and minting support

Integrate a feature flag mechanism into the existing $ARIO process. All ArNS related actions are free if the global flag is enabled and an LRU cache to limit the number of ArNS records stored in state. Additionally, add a `mint` function to mint new balances for other interactions/use cases - but throttle the amount of tokens distributed at any given time.

Pros:

- Tight integration with main repo
- Integration with ArNS does not require any minting/extra work
- Easy to maintain and flexible to extend beyond ArNS interactions (e.g. internal for team to mint $ARIO for testing)
- Lowest onboarding barrier for ArNS interactions (you don't need balance!)
- A feature flag is easier to manage than a separate process

Cons:

- Intertwined logic with main repo
- Match expectations of users?
- Ensuring right controls with integration of new code to mainnet $ARIO process

## Decision Outcome

- Add a global flag that can be used to enable/disable a global variable `ALLOW_FREE_ARNS_INTERACTIONS` or similar
  - all ArNS related interactions are free if the flag is enabled
  - pruning will remove records > 30 days old when the flag is enabled
  - can be toggled on/off by VAOT/contract owner without need for additional handler
- Add a limit on the number of ArNS records at any given time (this could be like an LRU cache where we prune out the oldest records)
  - prevents abuse of the free ArNS interactions (via bloated state/unnecessary name resolution on ar-io.dev)
  - ensures fair distribution of testnet resources
  - can be adjusted based on usage patterns and community feedback
- Add a global flag `ALLOW_MINTING` to the $ARIO process and a `mint` function to mint new balances for other interactions/use cases
  - calling `mint` transfers balance from the `Owner` address to the recipient address
  - `mint` is throttled by distribution limit over a period of time (e.g. 1M $ARIO per day)
  - `mint` is restricted by amount of tokens given to a single address (e.g. 10k $ARIO per address)
  - once the `Owner` address balance is below threshold, prune balances back to the `Owner` address (criteria here less certain, but similar to LRU cache eviction)
  - expose `mint` API in SDK and CLI for projects to use

[Ariel]: https://github.com/arielmelendez
[Dylan]: https://github.com/dtfiedler
[Atticus]: https://github.com/atticusofsparta
[Phil]: https://github.com/vilenarios
[John]: https://github.com/johnniesparkes
