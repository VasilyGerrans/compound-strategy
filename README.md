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
* All hardcoded addresses in the CompoundStrategy01.sol contructor are Ethereum Mainnet addresses.
* Comments describing the main function behaviours are located in the ICompoundStrategy.sol interface. Descriptions of private or unimportant functions are located in CompoundStrategy01.sol.
* CompoundStrategy01.sol doesn't prevent the user from creating positions in new tokens while a position in another token exists. The user must do his own checks to prevent that behaviour.

## Test

The test does not use chai to assert specific outcomes. 

Instead, it runs a simulation to show the outcome of a potential wind strategy in the current state of the mainnet.

Here are the demonstrated steps:
1. Creates a `deployer` address with a lot of ether.
2. Swaps 10 ether for max WBTC via UniswapV3.
3. Deploys CompoundStrategy01.sol as deployer.
4. Transfers the full amount of WBTC to CompoundStrategy01.sol.
5. Winds a position with a depth count of 5.
6. Wraps the position one more time (adjusting the position to depth of 6).
7. Waits for around 2 days (with a new block mined every 13 seconds).
8. Claims all the accrued COMP rewards for that period.
9. Reinvests it into WBTC via default swap strategy (UniswapV3 pools).
10. Unwraps the position one time.
11. Unwinds the position completely.

Keep in mind that this is a long list of transactions, so the default Hardhat timeout limit is disabled.