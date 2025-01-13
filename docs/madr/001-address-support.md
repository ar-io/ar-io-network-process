# Architecture Decision Record (ADR)

- Status: proposed
- Deciders: [Ariel], [Dylan], [Atticus], [Steven]
- Date: 2024-11-21
- Authors: [Dylan]

## General Summary

This ADR addresses the need for a flexible and efficient wallet address format support by the ARIO network process. The decision stems from the requirement to accommodate various address types while ensuring robust validation mechanisms to prevent user errors and potential loss of funds. The discussions highlighted the importance of balancing flexibility with security, particularly in the context of evolving address standards across different blockchain networks supported by AO.

## Decision Drivers

- **Flexibility**: The need to support various address formats without extensive modifications to the core system.
- **Security**: Ensuring that user inputs are validated to prevent loss of funds due to invalid addresses.
- **Future-Proofing**: The ability to adapt to new address types and standards as they emerge in the blockchain ecosystem.

## Considered Options

1. **Strict Address Validation**: Enforce rigid validation rules for all address types.
2. **Relaxed Address Enforcement**: Allow optional bypass of strict validation through a parameter.
3. **Regex Validation**: Implement regex patterns for flexible address validation.
4. **Client-Side Enforcement**: Enable client applications to define their own validation rules.

## Pros and Cons

1. **Strict Address Validation**:

   - **Pros**:
     - Ensures that only valid addresses are accepted.
     - Provides a clear error message for invalid addresses.
   - **Cons**:
     - Requires extensive validation logic for each address type.
     - Limits flexibility in supporting various address formats.

2. **Relaxed Address Enforcement**:

   - **Pros**:
     - Allows for more flexibility in supporting various address formats.
     - Reduces the need for extensive validation logic.
   - **Cons**:
     - May lead to invalid addresses being accepted.
     - Potential loss of funds if invalid addresses are used.

3. **Regex Validation**:

   - **Pros**:
     - Provides a flexible way to validate various address formats.
     - Allows for easy customization of validation rules.
   - **Cons**:
     - May not catch all invalid addresses.
     - Potential for user error if the regex is not correctly implemented.

4. **Client-Side Enforcement**:
   - **Pros**:
     - Allows clients to define their own validation rules.
     - Provides flexibility in supporting various address formats.
   - **Cons**:
     - Potential inconsistencies across clients if not properly implemented.
     - Increased complexity in the system if not properly managed.

## Decision Outcome

The decision is to implement an `Allow-Unsafe-Addresses` tag, which defaults to `false`. This allows clients to choose whether they want to potentially send tokens to invalid wallets, providing flexibility while maintaining a safety net for standard address types. It also leaves from for new signature types supported by AO in the future.

## Positive Consequences

- **Enhanced Flexibility**: The system can adapt to various address formats and standards.
- **Improved User Experience**: Users can interact with a wider range of address types without encountering errors.
- **Future-Proofing**: The architecture can evolve with emerging blockchain technologies and address types.

## Negative Consequences

- **Potential for User Error**: Relaxed validation may lead to increased risk of invalid addresses being accepted.
- **Complexity in Client Implementation**: Client applications may need to implement their own validation logic, which could lead to inconsistencies.

[Ariel]: https://github.com/arielmelendez
[Dylan]: https://github.com/dtfiedler
[Atticus]: https://github.com/atticusofsparta
[Steven]: https://github.com/kunstmusik
