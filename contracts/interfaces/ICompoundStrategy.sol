//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface ICompoundStrategy {
    /**
        @notice Can theoretically wind without limit, but will eventually
        revert when the token deposit amount is insufficient to give any 
        additional borrow amount.
        @param Count specifies the number of strategy loops. Set this to 0
        to turn this into a simple deposit function. 
     */
    function compound_loop_deposit(string calldata Coin, uint256 Count) external;
    function compound_loop_withdraw_all(string calldata Coin) external;
    
    /**
        @dev Partially unwinds the Compound position.
        @notice The method does not fail if Count is greater than loop depth,
        but instead calls compound_loop_withdraw_all.
     */
    function compound_loop_withdraw_part(string calldata Coin, uint256 Count) external;
    function compound_corrector_add(string calldata Coin) external;
    function compound_corrector_remove(string calldata Coin) external;
    
    /**
        @dev Claims COMP in all entered markets.
        @notice These calls are gas-inefficient.
     */
    function compound_comp_claim() external;
    function compound_comp_claim_to(address to) external returns (uint256 amount);
    
    /**
        @dev Claims COMP much more gas-efficiently.
     */
    function compound_comp_claim_in_markets(address[] memory cTokenAddresses) external;
    function compound_comp_claim_in_markets_to(address[] memory cTokenAddresses, address to) external returns (uint256 amount);
    
    /**
        @dev Claims all available COMP token and reinvests it into a specific `Coin` position.
        @notice This is not a gas-optimal call. If this is being called from another
        contract, it is better to call `compound_comp_claim_in_markets` and then to call
        `compound_comp_reinvest`.
        @param amountOutMinimum is an optional paramter. Set to 0 to ignore. Ignoring this 
        parameter may expose the sender to frontrunning attacks.
     */
    function compound_comp_claim_reinvest(string calldata Coin, uint256 Count, uint256 amountOutMinimum) external;
    function compound_comp_reinvest(string calldata Coin, uint256 Count, uint256 amountOutMinimum) external;
    function compound_stat(string calldata Coin) external view returns( 
        uint256 compBorrowSpeeds,
        uint256 compSupplySpeeds, 
        uint256 supplyRatePerBlock,
        uint256 borrowRatePerBlock, 
        uint256 totalCash, 
        uint256 totalBorrows,
        uint256 totalReserves, 
        uint256 reserveFactorMantissa,
        uint256 collateralFactorMantissa,
        uint256 contractCTokenBalance,
        uint256 contractBorrowBalance
    );
}