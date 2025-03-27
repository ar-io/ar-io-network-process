# MADR-002: Testnet Faucet

- Status: proposed
- Deciders: [Ariel], [Dylan], [Atticus], [Phil], [John]
- Date: 2025-03-27
- Authors: [Dylan]

<!-- toc -->

- [Table of Contents](#table-of-contents)
- [Requirements](#requirements)
- [Separate faucet process for getting $ARIO](#separate-faucet-process-for-getting-ario)
- [Integrated feature flag and minting support in existing $ARIO process](#integrated-feature-flag-and-minting-support-in-existing-ario-process)
- [Launch your own $ARIO process and gateway](#launch-your-own-ario-process-and-gateway)
- [Decision Outcome](#decision-outcome)

<!-- tocstop -->

## Requirements

- Easy onboarding to users/projects looking to interact with ArNS
- Tight integration and support with ar-io-gateways and ar-io-sdk
- Extensible to support other interactions/use cases
- Ability to mint $ARIO for internal testing purposes
- Decent enough protection against abuse

## Separate faucet process for getting $ARIO

Create a separate process (or service/api) for interacting/managing $ARIO balances and pruning on a timed bases. It would be "allocated" $ARIO on an interval and transfer limited amounts to users. Ideally, it protects against abuse by limiting the amount of $ARIO that can be minted at any given time and sends alerts when the wallet balance is low.

This could be a process, or a service and API that supported in the CLI.

**Pros:**

- Logic separated from main repo
- Allows for more robust and flexible implementation if needed
- Rate limits token distribution to prevent abuse
- Minimal impact on the $ARIO process
- If using a service - it can be deployed anywhere and doesn't need to be deployed to AO, allowing for more flexibility and alerting mechanisms

**Cons:**

- More overhead - repo/code to manage
- If using a process - it would need to be deployed to AO and would need to be able to call the $ARIO process (i.e. depends on cranking)
- If using a service - separate piece of infrastructure to manage

## Integrated feature flag and minting support in existing $ARIO process

Integrate a feature flag mechanism into the existing $ARIO process. All ArNS related actions are free if the global flag is enabled and an LRU cache to limit the number of ArNS records stored in state. Additionally, add a `mint` function to mint new balances for other interactions/use cases - but throttle the amount of tokens distributed at any given time.

**Pros:**

- Tight integration with main repo
- Integration with ArNS does not require any minting/extra work
- Easy to maintain and flexible to extend beyond ArNS interactions (e.g. internal for team to mint $ARIO for testing)
- Lowest onboarding barrier for ArNS interactions (you don't need balance!)
- A feature flag is easier to manage than a separate process

**Cons:**

- Intertwined logic with main repo
- Match expectations of users?
- Ensuring right controls with integration of new code to mainnet $ARIO process

## Launch your own $ARIO process and gateway

Users can spawn their own $ARIO process and manage it as they see fit, via a workflow. We provide the module, source code and APIs, and documents for the user to deploy their own $ARIO process and supporting gateway. Once the user has deployed their own $ARIO process, they can use it to interact with ArNS and mint $ARIO as they see fit.

Wrap the ar-io gateway and process creation in a parameterized docker container that can be deployed with a single command and reused across projects.

We could allow the process to be spawned locally or directly to AO. If spawned against AO - they would be able to use ao.link and other AO related services.

**Pros:**

- Users get total control over their own $ARIO process, no "minting" required
- Minimal reliance on managed/centralized infrastructure (from $ARIO team's perspective)

**Cons:**

- Users would need to run their own gateway to leverage the $ARIO process
- Token sprawl - creating multiple "lookalike" $ARIO processes (if not done locally)
- Non-unified testnet experience - each user/team would have their own "testnet"
- Is it a real AO process?

## Decision Outcome

We will implement a faucet API for getting $ARIO (Option #1), deployed to our existing infrastructure and managed by the $ARIO team. It will be allocated it’s own balance of $ARIO and responsible for distributing $ARIO to users when requested. It will have necessary protections (i.e. rate-limiting) to prevent abuse, and proper alerting/observability around it’s use (i.e. the balance is low). Additional tools will be created to prune balances of users that haven’t interacted with the testnet for a period of time, and remove records via standard protected evals. This results in the least amount of changes to the $ARIO process code, and relies more on existing infrastructure expertise and tooling to administer tokens.

Next steps:

- create an API spec for requesting tokens
- create a wallet, and transfer sufficient balance (50M $tARIO) to that wallet
- add rate limiting and alerting and observability to the API
- create separate testnet monitor tooling that can be used to trigger pruning of balances back to the faucet wallet address, and remove records from the testnet process

[Ariel]: https://github.com/arielmelendez
[Dylan]: https://github.com/dtfiedler
[Atticus]: https://github.com/atticusofsparta
[Phil]: https://github.com/vilenarios
[John]: https://github.com/johnniesparkes
