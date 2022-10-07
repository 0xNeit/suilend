# Suilend
Lending protocol on the Sui Blockchain

THIS IS NOT PRODUCTION READY

# Overview of terminology

A LendingMarket object holds many Reserves and Obligations.

An Obligation is a representations of a user's deposits and borrows. An obligation has exactly one lending market. 

There is 1 Reserve per token type (e.g a SUI Reserve, a SOL Reserve, a USDC Reserve). 
A user can supply assets to the reserve to earn interest, and/or borrow assets from a reserve and pay interest.
When a user deposits assets into a reserve, they will receive CTokens. 
The CToken represents the user's ownership of their deposit, and entitles the user to earn interest on their deposit.

# Known issues
- I left some rounding bugs in a couple places. I haven't implemented floor/ceil correctly in my Decimal module yet.
- Compounding debt in an obligation can sometimes be inaccurate because it has to be done in a separate tx.
- The reserve prover spec is currently broken bc I overhauled my Decimal module. 
