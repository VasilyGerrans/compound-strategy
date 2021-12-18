# Compound Strategy

Contract for winding and unwinding a looped supply/borrow position on the [Compound Protocol](https://compound.finance/) for greater COMP reward accumulation. 

Can be used as a standalone contract or as part of a larger ecosystem.

## Usage

1. Clone the repo.
2. Run `npm install` to download dependencies.
3. Run `npx hardhat compile` to compile the contracts.
4. Run `npx hardhat test` to run all tests (they are not designed to be presentible).

## Notes

1. The tests are not designed for presentability. They are left as a rough guideline for the types of tests that were done in the process of writing these contracts.
2. CompoundStrategy01.sol implements a simple admin system to grant priviliged access to outside parties.
3. CompoundStrategy01.sol has an `admin_backdoor` function designed for emergency function calls by an admin in case of flaws in the contract itself or external contracts.
4. CompoundStrategy01.sol implements a default UniswapV3 swap for COMP reinvestment together with an optional `customSwapStrategy` address that can be used for implementing more advanced swapping strategies afrer deployment. The UniswapV3 swap always takes a path starting with COMP through WETH and into the chosen token.