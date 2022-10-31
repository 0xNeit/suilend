# Reserve

For a given lending market, a reserve holds all deposits of a coin type for a given lending market. 
For example, the Suilend Main Market will have exactly 1 SUI reserve and 1 USDC reserve.

If a user deposits/repays SUI, the SUI reserve will increase in supply.

If a user borrows/withdraws SUI, the SUI reserve will decrease in supply.

## Reserve Utilization

$$U_{r} = B_{r} / T_r = B_r / (B_{r} + A_{r})$$

Where:
- $U_{r}$ is reserve utilization. $0 < U_{reserve} < 1$
- $B_r$ is the amount of tokens lent to borrowers from reserve $r$.
- $A_r$ is the amount of tokens available in reserve $r$. These are tokens that are have been deposited into the reserve but not borrowed yet.
- $T_r$ is the total supply of tokens in reserve $r$.

Example: Say I (ripleys) deposit 100 USDC into Suilend, and Soju (our bd guy) deposit 100 SUI and borrows 50 USDC. 

The reserve utilization on the USDC reserve is $50 / (50 + 50)$ = 50%.

## Calculating interest Rates and compounding debt

In Suilend, debt is compounded every second. $B_r$ from prior formulas (total tokens borrowed in reserve $r$) provides us a convenient way to compound global debt on a per-reserve basis.

To compound debt, we need an APR. In Suilend, the APR is a function of reserve utilization and needs to be recalculated on every borrow/repay action.

The formula below describes how to compound debt on a reserve:

$$B(t=1)_r = B(t=0)_r * (1 + APR(U_r) / Y_{seconds})^1$$

Where:
- $B(t)_r$ is the total amount of tokens borrowed in reserve $r$ at time $t$.
- $APR(U_r)$ is the APR for a given utilization value. This function is intentionally not defined here, as it might be subject to change.
- $Y_{seconds}$ is the number of seconds in a year.

Note that even if no additional users borrow tokens after $t=0$, due to compound interest, the borrowed amount will increase over time. 

## CTokens

When a user deposits SUI into Suilend, they will mint (ie get back) CSUI. This CSUI entitles the user to obtain their deposit from Suilend + additional interest. The interest is obtained by lending out the tokens to borrowers.

The CToken ratio denotes the exchange rate between the CToken and its underlying asset. Formally, the ctoken ratio is calculated by:
$$C_r = (B_r + A_r) / T_{C_r}$$

Where:
- $C_r$ is the ctoken ratio for reserve $r$
- $B_r$ is the amount of tokens lent to borrowers for reserve $r$
- $A_r$ is the amount of available tokens (ie not lent out) for reserve $r$
- $T_{C_r}$ is the total supply of ctokens in reserve $r$.

$C_r$ starts at 1 when the reserve is initialized, and grows over time. The CToken ratio never decreases.

Note that a user cannot always exchange their CSUI back to SUI. In a worst case scenario, all deposited SUI could be lent out, so the protocol won't have any left for redemption. However, in this scenario, the interest rates will skyrocket, incentivizing new depositors and also incentivizing borrowers to pay back their debts.

## Parameters

# Open LTV (Loan-to-value)

Open LTV is a percentage that limits how much can be _initially_ borrowed against a deposit. 

Open LTV is less than or equal to 1, and is defined _per_ reserve. This is because some tokens are more risky than others. For example, using USDC as collateral is much safer than using DOGE.

# Close LTV

Close LTV is a percentage that represents the maximum amount that can be borrowed against a deposit. If the borrowed value exceeds this

# Obligations

An obligation is a representation of a user's deposits and borrows in Suilend.