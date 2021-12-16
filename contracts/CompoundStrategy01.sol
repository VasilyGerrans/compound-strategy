//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IComptroller.sol";
import "./interfaces/IInterestRateModel.sol";
import "./interfaces/ICToken.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IWETH9.sol";
import "hardhat/console.sol";

contract CompoundStrategy01 is Ownable {
    using SafeMath for uint256;

    mapping(string => CompoundLoop) public CompoundLoops;

    /**
        @notice Compound market manager.
     */
    IComptroller comptroller;

    /**
        @notice COMP token
     */
    IERC20 comp;

    struct CompoundLoop {
        address ctoken;
        address token;
        uint256 depth;
        uint256 borrowMantissa;
        uint256 withdrawMantissa;
    }

    constructor() {
        CompoundLoops["WBTC"] = CompoundLoop(
            0xccF4429DB6322D5C611ee964527D42E5d685DD6a,
            0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            0,
            0.95 * 1e18,    // 95%
            0.995 * 1e18    // 99.5%
        );

        CompoundLoops["COMP"] = CompoundLoop(
            0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4,
            0xc00e94Cb662C3520282E6f5717214004A7f26888, 
            0,
            0.95 * 1e18,
            0.995 * 1e18
        );

        CompoundLoops["DAI"] = CompoundLoop(
            0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643,
            0x6B175474E89094C44Da98b954EedeAC495271d0F,
            0,
            0.95 * 1e18,
            0.995 * 1e18
        );

        CompoundLoops["USDC"] = CompoundLoop(
            0x39AA39c021dfbaE8faC545936693aC917d5E7563,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            0,
            0.95 * 1e18,
            0.995 * 1e18
        );

        comptroller = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
        comp = IERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    }

    /**
        @dev Set new mantissas for specific coin.
        @param borrowMantissa set to 0 to leave it unchanged.
        @param withdrawMantissa set to 0 to leave it unchanged.
     */
    function set_loop_mantissas(string memory Coin, uint256 borrowMantissa, uint256 withdrawMantissa) public onlyOwner {
        CompoundLoop storage loop = CompoundLoops[Coin];
        loop.borrowMantissa = borrowMantissa == 0 ? loop.borrowMantissa : borrowMantissa;
        loop.withdrawMantissa = withdrawMantissa == 0 ? loop.withdrawMantissa : withdrawMantissa;
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
        @dev Claims tokens much more efficiently (saves gas).
     */
    function compound_comp_claim_in_markets(address[] memory cTokenAddresses) public onlyOwner {
        comptroller.claimComp(address(this), cTokenAddresses);
    }

    function compound_comp_claim_in_markets_to(address[] memory cTokenAddresses, address to) public onlyOwner returns (uint256 amount) {
        compound_comp_claim_in_markets(cTokenAddresses);
        amount = comp.balanceOf(address(this));
        comp.transfer(to, amount);
    }

    function compound_comp_claim_reinvest(string memory Coin, uint256 Count) public onlyOwner {
        // reinvest earned COMP via Swapper as Coin
    }

    function compound_comp_reinvest(string memory Coin, uint256 Count) public onlyOwner {
        // reinvest COMP on balance via Swapper as Coin
    }

    function compound_loop_deposit(string memory Coin, uint256 depth) public onlyOwner {
        CompoundLoop storage loop = CompoundLoops[Coin];
        require(loop.depth == 0, "position already exists");
        for (uint256 i = 0; i < depth; i++) {
            uint256 tokenAmt = IERC20(loop.token).balanceOf(address(this));

            _compound_deposit(Coin, tokenAmt);

            uint256 B1 = _get_free_to_borrow(Coin);
            _compound_borrow(Coin, B1);
        }
        _compound_deposit(Coin, IERC20(loop.token).balanceOf(address(this)));
        loop.depth = depth;
    }

    function compound_loop_withdraw_all(string memory Coin) public onlyOwner {
        CompoundLoop storage loop = CompoundLoops[Coin];
        while(loop.depth > 0) {  
            loop.depth--;

            uint256 safeRedeemAmt = _get_free_to_withdraw(Coin);
            _compound_withdraw(Coin, safeRedeemAmt);

            (,, uint256 borrowBalance, uint256 exchangeRateMantissa) = ICToken(loop.ctoken).getAccountSnapshot(address(this));
            uint256 redeemedUnderlying = safeRedeemAmt.mul(exchangeRateMantissa).div(1e18);
            uint256 repayAmt = borrowBalance > redeemedUnderlying ? redeemedUnderlying : borrowBalance;
            if (repayAmt > 0) {
                if (loop.depth == 0) {loop.depth++;}
                _compound_repay(Coin, repayAmt);
            } else {
                if (loop.depth > 0) {loop.depth = 0;}
                break;
            }
        }
    }

    /**
        @dev Partially unwinds the Compound position.
        @notice The method does not fail if Count is greater than loop depth,
        but instead calls compound_loop_withdraw_all.
     */
    function compound_loop_withdraw_part(string memory Coin, uint256 Count) public onlyOwner {
        CompoundLoop storage loop = CompoundLoops[Coin];
        if (Count >= loop.depth) {
            compound_loop_withdraw_all(Coin);
        } else {
            loop.depth -= Count;
            while(Count > 0) {
                Count--;

                uint256 safeRedeemAmt = _get_free_to_withdraw(Coin);
                _compound_withdraw(Coin, safeRedeemAmt);

                (,, uint256 borrowBalance, uint256 exchangeRateMantissa) = ICToken(loop.ctoken).getAccountSnapshot(address(this));
                uint256 redeemedUnderlying = safeRedeemAmt.mul(exchangeRateMantissa).div(1e18);
                uint256 repayAmt = borrowBalance > redeemedUnderlying ? redeemedUnderlying : borrowBalance;
                if (repayAmt > 0) {
                    _compound_repay(Coin, repayAmt);
                } else {
                    break;
                }
            }
        }
    }

    function compound_corrector_add(string memory Coin) public onlyOwner {
        uint256 borrow = _get_free_to_borrow(Coin);
        require(borrow > 0, "not enough tokens in pool");
        CompoundLoops[Coin].depth++;
        _compound_borrow(Coin, borrow);
        _compound_deposit(Coin, borrow);
    }

    function compound_corrector_remove(string memory Coin) public onlyOwner {
        CompoundLoop storage loop = CompoundLoops[Coin];
        require(loop.depth > 0, "loop depth is already 0");
        
        loop.depth--;

        uint256 safeRedeemAmt = _get_free_to_withdraw(Coin);
        _compound_withdraw(Coin, safeRedeemAmt);

        (,, uint256 borrowBalance, uint256 exchangeRateMantissa) = ICToken(loop.ctoken).getAccountSnapshot(address(this));
        uint256 redeemedUnderlying = safeRedeemAmt.mul(exchangeRateMantissa).div(1e18);
        uint256 repayAmt = borrowBalance > redeemedUnderlying ? redeemedUnderlying : borrowBalance;
        if (repayAmt > 0) {
            if (loop.depth == 0) {loop.depth++;}
            _compound_repay(Coin, repayAmt);
        } else if (loop.depth > 0)  {
            loop.depth = 0;
        }
    }

    /**
        @notice We must deposit the coin into the contract first.
        @param tokenAmt indicates the amount of underlying token we want to depost.
     */
    function _compound_deposit(string memory Coin, uint256 tokenAmt) private {
        ICToken ctoken = ICToken(CompoundLoops[Coin].ctoken);

        // we can enter multiple times without a problem
        address[] memory ctokenArray = new address[](1);
        ctokenArray[0] = address(ctoken);
        comptroller.enterMarkets(ctokenArray);

        _approve_max(IERC20(CompoundLoops[Coin].token), address(ctoken), tokenAmt);
        ctoken.mint(tokenAmt);
    }

    /**
        @param tokenAmt indicates the amount of ctokens we want to redeem.
     */
    function _compound_withdraw(string memory Coin, uint256 tokenAmt) private { 
        ICToken ctoken = ICToken(CompoundLoops[Coin].ctoken);
        require(ctoken.redeem(tokenAmt) == 0, "_compound_withdraw fail");
    }

    function _compound_withdraw_all(string memory Coin) private {
        ICToken ctoken = ICToken(CompoundLoops[Coin].ctoken);
        require(ctoken.redeem(ctoken.balanceOf(address(this))) == 0, "_compound_withdraw_all fail");
    }

    /**
        @param tokenAmt indicates the amount of underlying tokens we want
        to borrow.
     */
    function _compound_borrow(string memory Coin, uint256 tokenAmt) private { 
        ICToken ctoken = ICToken(CompoundLoops[Coin].ctoken);
        require(ctoken.borrow(tokenAmt) == 0, "_compound_borrow fail");
    }

    /**
        @notice Repays underlying tokens. We should check the actual amount
        repayed ourselves, as there can be transaction fees in certain tokens.
        @param tokenAmt indicates the amount of underlying tokens we want
        to repay.
     */
    function _compound_repay(string memory Coin, uint256 tokenAmt) private { 
        ICToken ctoken = ICToken(CompoundLoops[Coin].ctoken);
        _approve_max(IERC20(CompoundLoops[Coin].token), address(ctoken), tokenAmt);
        require(ctoken.repayBorrow(tokenAmt) == 0, "_compound_repay fail");
    }

    /**
        @return tokens – a safe amount of underlying that can be borrowed.
     */
    function _get_free_to_borrow(string memory Coin) private view returns (uint256 tokens) {
        CompoundLoop storage loop = CompoundLoops[Coin];
        uint256 underlyingAssetPrice = IPriceOracle(comptroller.oracle()).getUnderlyingPrice(loop.ctoken);
        (, uint256 accountLiquidity, ) = comptroller.getAccountLiquidity(address(this));
        tokens = accountLiquidity
            .mul(1e18).div(underlyingAssetPrice)    // convert to underlying tokens
            .mul(loop.borrowMantissa).div(1e18);    // conservative amount
    }

    /**
        @return tokens – a safe amount of ctoken that can be redeemed.
     */
    function _get_free_to_withdraw(string memory Coin) private view returns (uint256) {
        CompoundLoop storage loop = CompoundLoops[Coin];
        ICToken ctoken = ICToken(loop.ctoken);

        (, uint256 cTokenBalance, uint256 borrowBalance, uint256 exchangeRateMantissa) = ctoken.getAccountSnapshot(address(this));
        if (borrowBalance == 0) {
            return cTokenBalance;
        } else {
            (, uint256 collateralFactorMantissa, ) = comptroller.markets(address(ctoken));

            uint256 cTokenDebt = borrowBalance
                .mul(1e18).div(exchangeRateMantissa)        // convert to ctokens
                .mul(1e18).div(collateralFactorMantissa);   // adjust for collateral factor
            
            return cTokenBalance.sub(cTokenDebt).mul(loop.withdrawMantissa).div(1e18);
        }
    }

    function _approve_max(IERC20 token, address spender, uint256 amount) private {
        if (token.allowance(address(this), spender) < amount) {
            require(token.approve(spender, type(uint256).max), "approve error");
        }
    }

    /**
     *
     *
     *  @dev analytics view calls. 
     *
     *
     */

    function compound_stat_strat(string memory Coin) external view returns(
        uint256 compBorrowSpeeds, // used for calculating compBorrowIndex 
        uint256 compSupplySpeeds, // used for calculating compSupplyIndex
        uint256 supplyRatePerBlock, // the current supply rate per block given cash, borrows, reserves, and reserveFactorMantissa 
        uint256 borrowRatePerBlock, // the current supply rate per block given cash, borrows, reserves, and reserveFactorMantissa 
        uint256 totalCash, // total non-borrowed tokens in specific market
        uint256 totalBorrows, // total borrowed tokens in specific market
        uint256 totalReserves, // total non-borrowed tokens reserved for the protocol (not available for users)
        uint256 reserveFactorMantissa, // percent mantissa for interest that gets supplied to the protocol
        uint256 collateralFactorMantissa,
        uint256 contractCTokenBalance,
        uint256 contractBorrowBalance
    ) {
        ICToken ctoken = ICToken(CompoundLoops[Coin].ctoken);

        compBorrowSpeeds = comptroller.compBorrowSpeeds(address(ctoken));
        compSupplySpeeds = comptroller.compSupplySpeeds(address(ctoken));
        supplyRatePerBlock = ctoken.supplyRatePerBlock();
        borrowRatePerBlock = ctoken.borrowRatePerBlock();
        totalCash = ctoken.getCash();
        totalBorrows = ctoken.totalBorrows();
        totalReserves = ctoken.totalReserves();
        reserveFactorMantissa = ctoken.reserveFactorMantissa();
        
        (, collateralFactorMantissa, ) = comptroller.markets(address(ctoken));
        (, contractCTokenBalance, contractBorrowBalance, ) = ctoken.getAccountSnapshot(address(this));
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
        address ctokenAddress = CompoundLoops[Coin].ctoken;

        return (
            comptroller.compSupplyState(ctokenAddress),
            comptroller.compBorrowState(ctokenAddress),
            comptroller.compSupplierIndex(ctokenAddress, address(this)),
            comptroller.compBorrowerIndex(ctokenAddress, address(this)),
            comptroller.compAccrued(address(this)),
            comptroller.compBorrowSpeeds(ctokenAddress), //
            comptroller.compSupplySpeeds(ctokenAddress), //
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
        ICToken ctoken = ICToken(CompoundLoops[Coin].ctoken);

        (, collateralFactorMantissa, ) = comptroller.markets(address(ctoken));
        (, tokenBalance, borrowBalance,) = ctoken.getAccountSnapshot(address(this));

        return (
            ctoken.exchangeRateStored(),
            ctoken.supplyRatePerBlock(), //
            ctoken.borrowRatePerBlock(), //
            ctoken.reserveFactorMantissa(),
            collateralFactorMantissa,
            ctoken.totalBorrows(), //
            ctoken.totalReserves(), //
            ctoken.getCash(), //
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
}
