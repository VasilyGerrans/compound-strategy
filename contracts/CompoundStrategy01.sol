//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/ComptrollerInterface.sol";
import "./interfaces/InterestRateModelInterface.sol";
import "./interfaces/CTokenInterface.sol";
import "./interfaces/PriceOracleInterface.sol";
import "hardhat/console.sol";

struct CompoundPair {
    address token;
    address ctoken;
}

contract CompoundStrategy01 is Ownable {
    using SafeMath for uint256;

    mapping(string => CompoundPair) public CompoundPairOf;

    /**
        @notice Compound market manager.
     */
    ComptrollerInterface comptroller;

    /**
        @notice COMP token
     */
    IERC20 comp;

    constructor() {
        CompoundPairOf["WBTC"] = CompoundPair(
            0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            0xccF4429DB6322D5C611ee964527D42E5d685DD6a
        );

        comptroller = ComptrollerInterface(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
        comp = IERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    }

    function compound_stat_comp(string memory Coin) external view returns(
        CompMarketState memory compSupplyState, 
        CompMarketState memory compBorrowState,
        uint256 compSupplierIndex,
        uint256 compBorrowerIndex,
        uint256 compAccrued,
        uint256 compBorrowSpeeds,
        uint256 compSupplySpeeds,
        uint256 compRate
    ) {
        address ctokenAddress = CompoundPairOf[Coin].ctoken;

        return (
            comptroller.compSupplyState(ctokenAddress),
            comptroller.compBorrowState(ctokenAddress),
            comptroller.compSupplierIndex(ctokenAddress, address(this)),
            comptroller.compBorrowerIndex(ctokenAddress, address(this)),
            comptroller.compAccrued(address(this)),
            comptroller.compBorrowSpeeds(ctokenAddress),
            comptroller.compSupplySpeeds(ctokenAddress),
            comptroller.compRate()
        );
    }

    function compound_stat_coin(string memory Coin) external view returns(
        uint256 exchangeRate,
        uint256 supplyRatePerBlock,
        uint256 borrowRatePerBlock,
        uint256 reserveFactorMantissa,
        uint256 collateralFactorMantissa,
        uint256 totalBorrows,
        uint256 totalReserves,
        uint256 totalCash,
        uint256 tokenBalance,
        uint256 borrowBalance
    ) {
        CTokenInterface ctoken = CTokenInterface(CompoundPairOf[Coin].ctoken);

        (, collateralFactorMantissa, ) = comptroller.markets(address(ctoken));
        (, tokenBalance, borrowBalance,) = ctoken.getAccountSnapshot(address(this));

        return (
            ctoken.exchangeRateStored(),
            ctoken.supplyRatePerBlock(),
            ctoken.borrowRatePerBlock(),
            ctoken.reserveFactorMantissa(),
            collateralFactorMantissa,
            ctoken.totalBorrows(),
            ctoken.totalReserves(),
            ctoken.getCash(),
            tokenBalance,
            borrowBalance
        );
    }

    function compound_stat_global() external view returns(
        uint256 accountLiquidity,
        uint256 accountShortfall,
        address[] memory assetsIn,
        uint256 maxAssets
    ) {
        (, accountLiquidity, accountShortfall) = comptroller.getAccountLiquidity(address(this));
        assetsIn = comptroller.getAssetsIn(address(this));
        maxAssets = comptroller.maxAssets();
    }

    function compound_comp_claim() public onlyOwner {
        comptroller.claimComp(address(this));
    }

    /**
        @dev Claims tokens for this contract and sends them to 
        `to` address.
     */
    function compound_comp_claim_to(address to) public onlyOwner returns (uint256 amount) {
        compound_comp_claim();
        amount = comp.balanceOf(address(this));
        comp.transfer(to, amount);
    }

    /**
        @notice We must deposit the coin into the contract first.
        @param tokenAmt indicates the amount of underlying token we want to depost.
     */
    function _compound_deposit(string memory Coin, uint256 tokenAmt) public { // change visibility later
        CTokenInterface ctoken = CTokenInterface(CompoundPairOf[Coin].ctoken);

        // we can enter multiple times without a problem
        address[] memory ctokenArray = new address[](1);
        ctokenArray[0] = address(ctoken);
        comptroller.enterMarkets(ctokenArray);

        approveMax(IERC20(CompoundPairOf[Coin].token), address(ctoken), tokenAmt);
        ctoken.mint(tokenAmt);
    }

    /**
        @param tokenAmt indicates the amount of underlying tokens we want to redeem.
     */
    function _compound_withdraw(string memory Coin, uint256 tokenAmt) public { // change visibility later
        CTokenInterface ctoken = CTokenInterface(CompoundPairOf[Coin].ctoken);
        require(ctoken.redeemUnderlying(tokenAmt) == 0, "_compound_withdraw fail");
    }

    /**
        @notice We can only borrow the USD value of our account liquidity.
        Call comptroller.getAccountLiquidity(address) to check it for  
        `address`. The second return value is how much liquidity we have. The 
        third value is how much negative liquidity we have. If we have negative
        account liquidity, our collateral can be liquidated at any moment.
        @param tokenAmt indicates the amount of underlying tokens we want
        to borrow.
     */
    function _compound_borrow(string memory Coin, uint256 tokenAmt) public { // change visibility later
        CTokenInterface ctoken = CTokenInterface(CompoundPairOf[Coin].ctoken);
        ctoken.borrow(tokenAmt);
    }

    /**
        @notice Repays underlying tokens. We should check the actual amount
        repayed ourselves, as there can be transaction fees in certain tokens.
        @param tokenAmt indicates the amount of underlying tokens we want
        to repay.
     */
    function _compound_repay(string memory Coin, uint256 tokenAmt) public { // change visibility later
        CTokenInterface ctoken = CTokenInterface(CompoundPairOf[Coin].ctoken);
        approveMax(IERC20(CompoundPairOf[Coin].token), address(ctoken), tokenAmt);
        require(ctoken.repayBorrow(tokenAmt) == 0, "_compound_repay fail");
    }

    function compound_loop_deposit_001(string memory Coin) public returns(uint256) {
        return compound_loop_deposit_002(Coin, IERC20(CompoundPairOf[Coin].token).balanceOf(address(this)));
    }

    function compound_loop_deposit_002(string memory Coin, uint256 tokenAmt) public returns(uint256) {
        require(tokenAmt > 0, "no tokens");

        _compound_deposit(Coin, tokenAmt);

        uint256 availableBorrowTokens = _get_free_to_borrow(Coin);

        // borrow 94% of available borrow tokens
        uint256 B1 = availableBorrowTokens.mul(94).div(100);
        _compound_borrow(Coin, B1);

        return B1;
    }

    function _loop_deposit_x(string memory Coin, uint Count, uint256 x1) public {
        for(uint256 i; i < Count; i++){
            x1 = compound_loop_deposit_002(Coin, x1);
        }
        _compound_deposit(Coin, x1);
    }

    uint256 _last_deposit_loop;
    function compound_loop_deposit_x(string memory Coin, uint Count) public onlyOwner {
        uint256 x1 = compound_loop_deposit_001(Coin);
        _last_deposit_loop = Count;
        _loop_deposit_x(Coin, Count, x1);
    }

    function compound_corrector_add(string memory Coin) public onlyOwner {
        uint256 borrow = _get_free_to_borrow(Coin);
        require( borrow > 0, "not enough tokens in the pool");
        _last_deposit_loop = _last_deposit_loop + 1;
        _compound_borrow(Coin, borrow);
        _compound_deposit(Coin, borrow);
    }

    function compound_corrector_remove(string memory Coin) public onlyOwner {
        require(_get_free_to_withdraw(Coin) > 0, "not enough tokens in the pool");
        _last_deposit_loop = _last_deposit_loop - 1;
        _withdraw_001(Coin);
    }

    /**
        @dev Redeem max possible underlying and repay outstanding borrow.
     */
    function _withdraw_001(string memory Coin) private returns(uint256) {
        uint256 safeRedeemAmt = _get_free_to_withdraw(Coin);

        _compound_withdraw(Coin, safeRedeemAmt);
        uint256 borrowBalance = CTokenInterface(CompoundPairOf[Coin].ctoken).borrowBalanceStored(address(this));
        uint256 repayAmt = borrowBalance > safeRedeemAmt ? safeRedeemAmt : borrowBalance;
        if (repayAmt > 0) {
            _compound_repay(Coin, repayAmt);
        }
        return borrowBalance - repayAmt;
    }

    /**
        @return tokens – a safe amount of tokens that can be borrowed.
        @notice This function only gives conservative approximate amounts.
     */
    function _get_free_to_borrow(string memory Coin) private view returns (uint256 tokens) {
        uint256 underlyingAssetDollarPrice = PriceOracleInterface(comptroller.oracle()).getUnderlyingPrice(CompoundPairOf[Coin].ctoken);
        (, uint256 accountLiquidity, ) = comptroller.getAccountLiquidity(address(this));
        tokens = accountLiquidity.mul(10**18).div(underlyingAssetDollarPrice);
    }

    /**
        @return tokens – a safe amount of underlying that can be withdrawn.
        @notice This function only gives conservative approximate amounts. 
     */
    function _get_free_to_withdraw(string memory Coin) public view returns (uint256 tokens) {
        (, uint256 accountLiquidity, ) = comptroller.getAccountLiquidity(address(this));
        address ctokenAddress = CompoundPairOf[Coin].ctoken;
        uint256 underlyingAssetDollarPrice = PriceOracleInterface(comptroller.oracle()).getUnderlyingPrice(ctokenAddress);
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(ctokenAddress);

        tokens = accountLiquidity.mul(10**36).div(underlyingAssetDollarPrice).div(collateralFactorMantissa);
    }

    function approveMax(IERC20 token, address spender, uint256 amount) private {
        if (token.allowance(address(this), spender) < amount) {
            require(token.approve(spender, type(uint256).max), "approve error");
        }
    }
}
