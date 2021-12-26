# Compound Strategy

Contract for winding and unwinding a looped supply/borrow position on the [Compound Protocol](https://compound.finance/) for greater COMP reward accumulation. 

Can be used as a standalone contract or as part of a larger ecosystem.

## Usage

1. Clone the repo.
2. Run `npm install` to download dependencies.
3. Create a `.env` file and add your own RPC in the form: `MAINNET_RPC=...`.
4. Run `npx hardhat compile` to compile the contracts.
5. Run `npx hardhat test` to run simulation.

## Notes

* CompoundStrategy01.sol implements a simple admin system to grant priviliged access to outside parties.
* CompoundStrategy01.sol has an `admin_backdoor` function designed for emergency function calls by an admin in case of flaws in the contract itself or external contracts.
* CompoundStrategy01.sol implements a default UniswapV3 swap for COMP reinvestment together with an optional `customSwapStrategy` address that can be used for implementing more advanced swapping strategies afrer deployment. The UniswapV3 swap always takes a path starting with COMP through WETH and into the chosen token.
* All specified addresses in the test are Ethereum Mainnet addresses.
* Comments describing the main function behaviours are located in the ICompoundStrategy.sol interface. Descriptions of private or secondary functions are located in CompoundStrategy01.sol.
* CompoundStrategy01.sol doesn't prevent the user from creating positions in new tokens while a position in another token exists. The user must do his own checks to prevent that behaviour.
* CompoundStrategy01.sol will allow a user to loop to the absolute possible maximum (until no further borrows against the deposited collateral is possible), but user ought to be aware of the risks.

## Risks

The contract's positions cannot be liquidated so long as its [accountLiquidity](https://compound.finance/docs/comptroller#account-liquidity) remains positive. Once accountLiquidity hits below 0, the user may no longer withdraw or borrow until it is once again increased. Other than contract logic error risks, the possibility of negative accountLiquidity constitutes the primary financial risk.

A few factors to be aware of:

* In the event that the contract deposits and borrows different underlying assets, if the price of the deposited asset(s) drops or the price of the borrowed asset(s) increases, accountLiquidity drops.
* The contract's borrow balance is constantly incrementally growing. Hence, so long as the contract still has outstanding debt, accountLiquidity will continue to slowly shrink over time.
* The deeper the position pyramid is wound, the smaller the contract's initial accountLiquidity will be upon opening a position. In the event that a user decides to wind a position to its maximum depth (for example, 50+ steps for 1 WBTC), the user's accountLiquidity will fall below zero in a matter of a few blocks. 

## Test

The test does not use chai to assert specific outcomes. 

Instead, it runs a simulation to show the outcome of a potential wind strategy in the current state of the mainnet.

Here are the demonstrated steps:
1. Creates a `deployer` address with a lot of ether.
2. Swaps 10 ether for max WBTC via UniswapV3.
3. Deploys CompoundStrategy01.sol as deployer.
4. Transfers the 1 WBTC to CompoundStrategy01.sol.
5. Winds a position with a depth count of 20.
6. Wraps the position one more time (adjusting the position to depth of 21).
7. Waits for around 2 days (with a new block mined every 13 seconds).
8. Claims all the accrued COMP rewards for that period.
9. Reinvests it into WBTC via default swap strategy (UniswapV3 pools).
10. Unwraps the position one time.
11. Unwinds the position completely.

Keep in mind that this is a long list of transactions, so the default Hardhat timeout limit is disabled.
