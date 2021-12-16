pragma solidity ^0.8.10;

/**
    @dev Slightly updated version of the official
    Comptroller interface from the Compound github:

    https://github.com/compound-finance/compound-protocol/blob/master/contracts/ComptrollerInterface.sol
 */

struct CompMarketState {
    /// @notice The market's last updated compBorrowIndex or compSupplyIndex
    uint224 index;

    /// @notice The block number the index was last updated at
    uint32 block;
}

interface IComptroller {
    /*** Assets You Are In ***/

    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);
    function exitMarket(address cToken) external returns (uint);

    function getAssetsIn(address account) external view returns (address[] memory);
    function maxAssets() external view returns(uint);

    /*** Policy Hooks ***/

    function mintAllowed(address cToken, address minter, uint mintAmount) external returns (uint);
    function mintVerify(address cToken, address minter, uint mintAmount, uint mintTokens) external;

    function redeemAllowed(address cToken, address redeemer, uint redeemTokens) external returns (uint);
    function redeemVerify(address cToken, address redeemer, uint redeemAmount, uint redeemTokens) external;

    function borrowAllowed(address cToken, address borrower, uint borrowAmount) external returns (uint);
    function borrowVerify(address cToken, address borrower, uint borrowAmount) external;

    function repayBorrowAllowed(
        address cToken,
        address payer,
        address borrower,
        uint repayAmount) external returns (uint);
    function repayBorrowVerify(
        address cToken,
        address payer,
        address borrower,
        uint repayAmount,
        uint borrowerIndex) external;

    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount) external returns (uint);
    function liquidateBorrowVerify(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount,
        uint seizeTokens) external;

    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external returns (uint);
    function seizeVerify(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external;

    function transferAllowed(address cToken, address src, address dst, uint transferTokens) external returns (uint);
    function transferVerify(address cToken, address src, address dst, uint transferTokens) external;

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint repayAmount) external view returns (uint, uint);

    function getAccountLiquidity(address account) external view returns (uint, uint, uint);
    function getHypotheticalAccountLiquidity(
        address account,
        address cTokenModify,
        uint redeemTokens,
        uint borrowAmount) external view returns (uint, uint, uint);
    function claimComp(address holder) external;
    function claimComp(address holder, address[] memory cTokens) external;
    function oracle() external view returns (address);
    function markets(address cTokenAddress) external view returns (bool, uint, bool);

    function compSupplyState(address) external view returns(CompMarketState calldata);
    function compBorrowState(address) external view returns(CompMarketState calldata);
    function compSupplierIndex(address,address) external view returns(uint);
    function compBorrowerIndex(address,address) external view returns(uint);
    function compAccrued(address) external view returns(uint);
    function compContributorSpeeds(address) external view returns(uint); 
    function lastContributorBlock(address) external view returns(uint);
    function compBorrowSpeeds(address) external view returns(uint);
    function compSupplySpeeds(address) external view returns(uint);
    function compReceivable(address) external view returns(uint); // internal accounting
    function compRate() external view returns(uint);
    
    /*
    /// @notice The COMP market supply state for each market
    mapping(address => CompMarketState) public compSupplyState;

    /// @notice The COMP market borrow state for each market
    mapping(address => CompMarketState) public compBorrowState;

    /// @notice The COMP borrow index for each market for each supplier as of the last time they accrued COMP
    mapping(address => mapping(address => uint)) public compSupplierIndex;

    /// @notice The COMP borrow index for each market for each borrower as of the last time they accrued COMP
    mapping(address => mapping(address => uint)) public compBorrowerIndex;

    /// @notice The COMP accrued but not yet transferred to each user
    mapping(address => uint) public compAccrued;

    /// @notice The portion of COMP that each contributor receives per block
    mapping(address => uint) public compContributorSpeeds;

    /// @notice Last block at which a contributor's COMP rewards have been allocated
    mapping(address => uint) public lastContributorBlock;

    /// @notice The rate at which comp is distributed to the corresponding borrow market (per block)
    mapping(address => uint) public compBorrowSpeeds;

    /// @notice The rate at which comp is distributed to the corresponding supply market (per block)
    mapping(address => uint) public compSupplySpeeds;

    /// @notice Accounting storage mapping account addresses to how much COMP they owe the protocol.
    mapping(address => uint) public compReceivable;
    */
}