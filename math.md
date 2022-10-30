# Calculating Interest Rates

Example: Say I (ripleys) deposit 100 USDC into Suilend, and Soju (our bd guy) deposit 100 SUI and borrows 50 USDC. How much interest does Soju pay?

In Suilend, the interest rate is variable and also compounded every second. Therefore, every second, the variable APR (aka borrow rate) is recalculated. 

In Suilend, the APR is calculated as a function of reserve utilization. 

$U_{r} = B_{r} / (B_{r} + A_{r})$

Where:
- $U_{reserve}$ is reserve utilization. $0 < U_{reserve}

We use a piecewise function as seen below (x axis is reserve utilization

$APR(t) = f(reserveutil)$



