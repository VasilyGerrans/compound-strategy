//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IComptroller.sol";
import "./interfaces/IInterestRateModel.sol";
import "./interfaces/ICToken.sol";
import "./interfaces/IPriceOracle.sol";
import "./math/Exponential.sol";
import "hardhat/console.sol";

contract CompoundStrategy02 is Ownable, Exponential {
    using SafeMath for uint256;

    mapping(string => CompoundPair) public CompoundPairOf;

    /**
        @notice Compound market manager.
     */
    IComptroller comptroller;

    /**
        @notice COMP token
     */
    IERC20 COMP;

    struct CompoundPair {
        address basic;
        address c;
        bool wind;
    }    

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `cTokenBalance` is the number of cTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountLiquidityLocalVars {
        uint sumCollateral;
        uint sumBorrowPlusEffects;
        uint cTokenBalance;
        uint borrowBalance;
        uint exchangeRateMantissa;
        uint oraclePriceMantissa;
        uint liquidity;
        uint collateralFactorMantissa;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    constructor() {
        CompoundPairOf["WBTC"] = CompoundPair(
            0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            0xccF4429DB6322D5C611ee964527D42E5d685DD6a,
            false
        );

        CompoundPairOf["COMP"] = CompoundPair(
            0xc00e94Cb662C3520282E6f5717214004A7f26888, 
            0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4,
            false
        );

        comptroller = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
        COMP = IERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    }

    function _compound_deposit(string memory Coin, uint256 tokenAmt) public {
        CompoundPair storage COMPOUND = CompoundPairOf[Coin];
        IERC20 SToken = IERC20(COMPOUND.basic);
        require(SToken.balanceOf(address(this)) >= tokenAmt);
        approveMax(SToken, COMPOUND.c, tokenAmt);
        require(ICToken(COMPOUND.c).mint(tokenAmt) == 0, "_compound_deposit fail");
    }

    /**
        @param tokenAmt is the amount of underlying tokens we want to withdraw.
     */
    function _compound_withdraw(string memory Coin, uint256 tokenAmt) public {
        ICToken ctoken = ICToken(CompoundPairOf[Coin].c);
        require(ctoken.redeemUnderlying(tokenAmt) == 0, "_compound_withdraw fail");
    }

    /**
        @param tokenAmt indicates the amount of underlying tokens we want
        to borrow.
     */
    function _compound_borrow(string memory Coin, uint256 tokenAmt) public {
        ICToken ctoken = ICToken(CompoundPairOf[Coin].c);
        require(ctoken.borrow(tokenAmt) == 0, "_compound_borrow fail");
    }

    function _compound_repay(string memory Coin, uint256 tokenAmt) public {
        CompoundPair storage COMPOUND = CompoundPairOf[Coin];
        IERC20 SToken = IERC20(COMPOUND.basic);
        require(SToken.balanceOf(address(this)) >= tokenAmt);
        approveMax(SToken, COMPOUND.c, tokenAmt);
        require(ICToken(COMPOUND.c).repayBorrow(tokenAmt) == 0, "_compound_repay fail");
    }

    function compound_loop_deposit_001(string memory Coin) public returns(uint256 B1) {
        CompoundPair storage COMPOUND = CompoundPairOf[Coin];
        IERC20 SToken = IERC20(COMPOUND.basic);

        uint256 tokenAmt = SToken.balanceOf(address(this));

        _compound_deposit(Coin, tokenAmt);
        
        // collateralFactor is 65% for WBTC
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(COMPOUND.c);
        uint256 safeCollateralFactor = collateralFactorMantissa.sub(5 * 1e16); // reduce by 5%
        B1 = tokenAmt.mul(safeCollateralFactor).div(1e18);

        _compound_borrow(Coin, B1);
    } 

    function compound_loop_deposit_002(string memory Coin, uint256 tokenAmt) private returns(uint256 B1) {
        CompoundPair storage COMPOUND = CompoundPairOf[Coin];

        // collateralFactor is 65% for WBTC
        (, uint256 collateralFactorMantissa, ) = comptroller.markets(COMPOUND.c);
        uint256 safeCollateralFactor = collateralFactorMantissa.sub(5 * 1e16); // reduce by 5%

        _compound_deposit(Coin, tokenAmt);
        B1 = tokenAmt.mul(safeCollateralFactor).div(1e18);
        _compound_borrow(Coin, B1);
    } 

    function _loop_deposit_x(string memory Coin, uint256 Count, uint256 x1) private {
        for (uint256 i = 0; i < Count; i++) {
            x1 = compound_loop_deposit_002(Coin, x1);
        }
        _compound_deposit(Coin, x1);
    }

    uint256 private _last_deposit_loop;
    function compound_loop_deposit_x(string memory Coin, uint256 Count) public onlyOwner {
        uint256 x1 = compound_loop_deposit_001(Coin);
        _last_deposit_loop = Count;
        _loop_deposit_x(Coin, Count, x1);
    }
    
    /**
     *
     *   Strength of deposit
     *
     */

    function compound_corrector_add(string memory Coin) public onlyOwner {
        uint256 borrow = _get_free_to_borrow(Coin);
        require(borrow > 0, "not enough tokens in pool");
        _last_deposit_loop += 1;
        _compound_borrow(Coin, borrow);
        _compound_deposit(Coin, borrow);
    }

    function compound_corrector_remove(string memory Coin) public onlyOwner {
        require(_get_free_to_withdraw(Coin) > 0, "not enough tokens in the pool");
        _last_deposit_loop -= 1;
        _withdraw_001(Coin);
    }

    function _withdraw_001(string memory Coin) private returns (uint256) {
        console.log("WITHDRAWING");
        CompoundPair storage COMPOUND = CompoundPairOf[Coin];
        uint256 free_to_withdraw = _get_free_to_withdraw(Coin);
        _compound_withdraw(Coin, free_to_withdraw);
        console.log("Free to withdraw:");
        console.log(free_to_withdraw);
        (,, uint256 borrowBalance, ) = ICToken(COMPOUND.c).getAccountSnapshot(address(this));
        console.log("Borrow balance:");
        console.log(borrowBalance);
        if (free_to_withdraw > borrowBalance && borrowBalance > 0) {
            _compound_repay(Coin, borrowBalance);
            borrowBalance = 0;
        } else {
            _compound_repay(Coin, free_to_withdraw);
            borrowBalance -= free_to_withdraw;
        }
        return borrowBalance;
    }

    /* function _withdraw_001(string memory Coin) private returns (uint256) {
        (   uint256 balance_basic,
            uint256 balance_am,
            uint256 balance_variableDebtm,
            uint256 free_to_borrow,
            uint256 free_to_withdraw,
            uint256 true_balance
        ) = aave_balances(Coin);            
        _aave_withdraw(Coin, free_to_withdraw);
        if (free_to_withdraw > balance_variableDebtm) {
            // can be close now ...
            if (balance_variableDebtm > 0) {
                _aave_repay(Coin, balance_variableDebtm);
            }
            balance_variableDebtm = 0;
        } else {
            _aave_repay(Coin, free_to_withdraw);
            balance_variableDebtm = balance_variableDebtm - free_to_withdraw;
        }
        return balance_variableDebtm;        
    } */

    /* struct AccountLiquidityLocalVars {
        uint sumCollateral;
        uint sumBorrowPlusEffects;
        uint cTokenBalance;
        uint borrowBalance;
        uint exchangeRateMantissa;
        uint oraclePriceMantissa;
        uint collateralFactorMantissa;
        uint safeCollateralFactor;
        uint safeEtherBalance;
        uint etherBorrowBalance;
    } */

    function _get_free_to_borrow(string memory Coin) public view returns (uint256 tokens) {
        uint256 underlyingPrice = IPriceOracle(comptroller.oracle()).getUnderlyingPrice(CompoundPairOf[Coin].c);
        (, uint256 accountLiquidity, ) = comptroller.getAccountLiquidity(address(this));
        tokens = accountLiquidity.mul(1e18).div(underlyingPrice);

        /* CompoundPair storage COMPOUND = CompoundPairOf[Coin];
        AccountLiquidityLocalVars memory vars;
        (, vars.cTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = ICToken(COMPOUND.c).getAccountSnapshot(address(this));
        (, vars.collateralFactorMantissa, ) = comptroller.markets(COMPOUND.c);
        vars.safeCollateralFactor = vars.collateralFactorMantissa.sub(5 * 1e16); // reduce by 5%
        vars.oraclePriceMantissa = IPriceOracle(comptroller.oracle()).getUnderlyingPrice(COMPOUND.c);

        vars.safeEtherBalance = vars.cTokenBalance
            .mul(vars.exchangeRateMantissa).div(1e18)  // convert to underlying
            .mul(vars.safeCollateralFactor).div(1e18)  // convert to correct collateral factor
            .mul(vars.oraclePriceMantissa).div(1e18);  // convert to ether
        vars.etherBorrowBalance = vars.borrowBalance.mul(vars.oraclePriceMantissa).div(1e18);

        (, result) = vars.safeEtherBalance.trySub(vars.etherBorrowBalance);
        if (result > 0) {
            result = result.mul(1e18).div(vars.oraclePriceMantissa); // convert to tokens
        } */
/* 
        CompoundPair storage COMPOUND = CompoundPairOf[Coin];
        (, uint256 liquidity, ) = comptroller.getAccountLiquidity(address(this));
        uint256 oraclePriceMantissa = IPriceOracle(comptroller.oracle()).getUnderlyingPrice(COMPOUND.c);

        return liquidity
            .mul(95).div(100)                       // go 5% below liquidation level
            .mul(1e18).div(oraclePriceMantissa);    // convert from ether to underlying token quantity */
    }

    function _get_free_to_withdraw(string memory Coin) public view returns (uint256 tokens) {
        ICToken ctoken = ICToken(CompoundPairOf[Coin].c);   
        AccountLiquidityLocalVars memory vars;
        
        (, vars.cTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = ctoken.getAccountSnapshot(address(this));
        if (vars.borrowBalance == 0) {
            tokens = vars.cTokenBalance;
        } else {
            (, vars.liquidity, ) = comptroller.getAccountLiquidity(address(this));
            vars.oraclePriceMantissa = IPriceOracle(comptroller.oracle()).getUnderlyingPrice(address(ctoken));
            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});
            (, vars.collateralFactorMantissa, ) = comptroller.markets(address(ctoken));
            vars.collateralFactor = Exp({mantissa: vars.collateralFactorMantissa});
            vars.tokensToDenom = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePrice);

            tokens = div_(vars.liquidity, vars.tokensToDenom).mul(99999).div(100000); // conservative estimate
        }    
        /* 
        CompoundPair storage COMPOUND = CompoundPairOf[Coin];
        AccountLiquidityLocalVars memory vars;
        (, vars.cTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = ICToken(COMPOUND.c).getAccountSnapshot(address(this));
        (, vars.collateralFactorMantissa, ) = comptroller.markets(COMPOUND.c);
        vars.oraclePriceMantissa = IPriceOracle(comptroller.oracle()).getUnderlyingPrice(COMPOUND.c);

        if (vars.borrowBalance > 0) {
            vars.safeCollateralFactor = vars.collateralFactorMantissa.sub(1 * 1e16); // reduce by 1%
            vars.safeEtherBalance = vars.cTokenBalance
                .mul(vars.exchangeRateMantissa).div(1e18)  // convert to underlying
                .mul(vars.safeCollateralFactor).div(1e18)  // convert to safe collateral factor
                .mul(vars.oraclePriceMantissa).div(1e18);  // convert to ether balance
            vars.etherBorrowBalance = vars.borrowBalance.mul(vars.oraclePriceMantissa).div(1e18);

            (, free_to_withdraw) = vars.safeEtherBalance.trySub(vars.etherBorrowBalance);
            if (free_to_withdraw > 0) {
                free_to_withdraw = free_to_withdraw.mul(1e18).div(vars.oraclePriceMantissa);
            }
        } else {
            free_to_withdraw = vars.cTokenBalance
                .mul(vars.exchangeRateMantissa).div(1e18)      // convert to underlying
                .mul(vars.collateralFactorMantissa).div(1e18); // convert to collateral factor
        } */

        /* CompoundPair storage COMPOUND = CompoundPairOf[Coin];
        (, uint256 liquidity, ) = comptroller.getAccountLiquidity(address(this));
        uint256 oraclePriceMantissa = IPriceOracle(comptroller.oracle()).getUnderlyingPrice(COMPOUND.c);

        (,, uint256 borrowBalance, ) = ICToken(COMPOUND.c).getAccountSnapshot(address(this));

        if (borrowBalance > 0) {
            return liquidity
                .mul(1e18).div(oraclePriceMantissa);    // convert from ether to underlying token quantity
        } else {
            return liquidity
                .mul(1e18).div(oraclePriceMantissa);
        } */
    }

    function compound_balances(string memory Coin) public view returns (
        uint256 balance_basic,
        uint256 balance_c,
        uint256 balance_borrow,
        uint256 balance_underlying,
        uint256 free_to_borrow,
        uint256 free_to_withdraw,
        uint256 true_balance
    ) {
        CompoundPair storage COMPOUND = CompoundPairOf[Coin];
        address user = address(this);

        balance_basic   =   IERC20(COMPOUND.basic).balanceOf(user);



        /* uint256 exchangeRateMantissa;
        (, balance_c, balance_borrow, exchangeRateMantissa) = ICToken(COMPOUND.c).getAccountSnapshot(address(this));

        (, uint256 collateralFactorMantissa, ) = comptroller.markets(COMPOUND.c);
        uint256 safeCollateralFactor = collateralFactorMantissa.sub(5 * 1e16); // reduce by 5%

        balance_underlying = balance_c.mul(exchangeRateMantissa).div(1e18);
        uint256 balance = balance_underlying.mul(safeCollateralFactor).div(1e18); 

        (, free_to_borrow) = balance.trySub(balance_borrow);

        if (balance_borrow > 0) {
            free_to_withdraw = free_to_borrow;
        } else {
            free_to_withdraw = balance_underlying.mul(collateralFactorMantissa).div(1e18); 
        }

        true_balance = balance_underlying - balance_borrow; */
    }

    /* function aave_balances(string memory Coin) public view returns (
            uint256 balance_basic,
            uint256 balance_am,
            uint256 balance_variableDebtm,
            uint256 free_to_borrow,
            uint256 free_to_withdraw,
            uint256 true_balance
        ) {
        
        AavePair storage AAVE = AavePairOf[Coin];
        address _user = address(this);

        uint256 basic =         IERC20(AAVE.basic).balanceOf(_user);
        uint256 am =            IERC20(AAVE.am).balanceOf(_user);
        uint256 variableDebtm = IERC20(AAVE.variableDebtm).balanceOf(_user);

        free_to_borrow = am.mul(AAVE.ltv - 100).div(10000) - variableDebtm;

        if (variableDebtm > 0) {
            free_to_withdraw = am.mul(AAVE.liqvi - 100).div(10000) - variableDebtm;
        } else {
            free_to_withdraw = am;
        }

        balance_basic = basic;
        balance_am = am;
        balance_variableDebtm = variableDebtm;
        true_balance = balance_am - balance_variableDebtm;
    } */

    function approveMax(IERC20 token, address spender, uint256 amount) private {
        if (token.allowance(address(this), spender) < amount) {
            require(token.approve(spender, type(uint256).max), "approve error");
        }
    }
}