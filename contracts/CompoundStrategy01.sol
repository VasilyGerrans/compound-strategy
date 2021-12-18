//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interfaces/IComptroller.sol";
import "./interfaces/ICToken.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IWETH9.sol";
import "./interfaces/ICompoundStrategy.sol";

contract CompoundStrategy01 is ICompoundStrategy {
    using SafeMath for uint256;

    struct CompoundLoop {
        address ctoken;
        address token;
        uint256 depth;
        uint256 borrowMantissa;
        uint256 withdrawMantissa;
        uint24 uniswapFee; // identifies the most collateralised UniswapV3 token/WETH pool
    }

    IComptroller private immutable comptroller;
    IERC20 private immutable comp;
    ISwapRouter private immutable uniswapV3Router;
    address private immutable wethAddress;

    /**
        @dev An optional address for upgradable swap strategies. If set
        to address(0), a default uniswapV3 strategy is executed (see `_swap_strategy`).
     */
    address public customSwapStrategy;

    mapping(string => CompoundLoop) public CompoundLoops;

    mapping(address => bool) public admin;
    modifier onlyAdmin() {
        require(admin[msg.sender] == true, "not admin");
        _;
    }

    constructor() {
        admin[msg.sender] = true;

        CompoundLoops["WBTC"] = CompoundLoop(
            0xccF4429DB6322D5C611ee964527D42E5d685DD6a,
            0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            0,
            0.95 * 1e18,    // 95%
            0.995 * 1e18,   // 99.5%
            3000
        );

        CompoundLoops["COMP"] = CompoundLoop(
            0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4,
            0xc00e94Cb662C3520282E6f5717214004A7f26888, 
            0,
            0.95 * 1e18,
            0.995 * 1e18,
            3000
        );

        CompoundLoops["DAI"] = CompoundLoop(
            0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643,
            0x6B175474E89094C44Da98b954EedeAC495271d0F,
            0,
            0.95 * 1e18,
            0.995 * 1e18,
            500
        );

        CompoundLoops["USDC"] = CompoundLoop(
            0x39AA39c021dfbaE8faC545936693aC917d5E7563,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            0,
            0.95 * 1e18,
            0.995 * 1e18,
            3000
        );

        comptroller = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
        comp = IERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
        uniswapV3Router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    }

    function compound_loop_deposit(string calldata Coin, uint256 Count) public onlyAdmin {
        CompoundLoop storage loop = CompoundLoops[Coin];
        for (uint256 i = 0; i < Count; i++) {
            uint256 tokenAmt = IERC20(loop.token).balanceOf(address(this));

            _compound_deposit(Coin, tokenAmt);

            uint256 B1 = _get_free_to_borrow(Coin);
            require(B1 > 0, "not enough tokens in the pool");
            _compound_borrow(Coin, B1);
        }
        _compound_deposit(Coin, IERC20(loop.token).balanceOf(address(this)));
        loop.depth += Count;
    }

    function compound_loop_withdraw_all(string calldata Coin) public onlyAdmin {
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

    function compound_loop_withdraw_part(string calldata Coin, uint256 Count) public onlyAdmin {
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

    function compound_corrector_add(string calldata Coin) public onlyAdmin {
        uint256 borrow = _get_free_to_borrow(Coin);
        require(borrow > 0, "not enough tokens in pool");
        CompoundLoops[Coin].depth++;
        _compound_borrow(Coin, borrow);
        _compound_deposit(Coin, borrow);
    }

    function compound_corrector_remove(string calldata Coin) public onlyAdmin {
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

    function compound_comp_claim_in_markets(address[] memory cTokenAddresses) public onlyAdmin {
        comptroller.claimComp(address(this), cTokenAddresses);
    }

    function compound_comp_claim_in_markets_to(address[] memory cTokenAddresses, address to) external onlyAdmin returns (uint256 amount) {
        compound_comp_claim_in_markets(cTokenAddresses);
        amount = comp.balanceOf(address(this));
        comp.transfer(to, amount);
    }

    function compound_comp_claim() public onlyAdmin {
        comptroller.claimComp(address(this));
    }

    function compound_comp_claim_to(address to) external onlyAdmin returns (uint256 amount) {
        compound_comp_claim();
        amount = comp.balanceOf(address(this));
        comp.transfer(to, amount);
    }

    function compound_comp_claim_reinvest(string calldata Coin, uint256 Count, uint256 amountOutMinimum) external onlyAdmin {
        compound_comp_claim();
        compound_comp_reinvest(Coin, Count, amountOutMinimum);
    }

    function compound_comp_reinvest(string calldata Coin, uint256 Count, uint256 amountOutMinimum) public onlyAdmin {
        _swap_strategy(Coin, amountOutMinimum);
        compound_loop_deposit(Coin, Count);
    }

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

    function setAdmin(address user, bool isAdmin) external onlyAdmin {
        require(msg.sender != user, "self set not allowed");
        admin[user] = isAdmin;
    }

    /**
        @dev Adds or overwrites existing Compound loop. 
     */
    function set_compound_loop(
        string calldata Coin,
        address ctoken,
        address token,
        uint256 borrowMantissa,
        uint256 withdrawMantissa,
        uint24 uniswapFee
    ) external onlyAdmin {
        CompoundLoop storage loop = CompoundLoops[Coin];
        CompoundLoop memory newLoop = CompoundLoop(
            ctoken == address(0) ? loop.ctoken : ctoken,
            token == address(0) ? loop.token : token,
            loop.depth,
            borrowMantissa == 0 ? loop.borrowMantissa : borrowMantissa,
            withdrawMantissa == 0 ? loop.withdrawMantissa : withdrawMantissa,
            uniswapFee == 0 ? loop.uniswapFee : uniswapFee
        );
        CompoundLoops[Coin] = newLoop;
    }

    function set_custom_swap_strategy(address newCustomSwapStrategy) external onlyAdmin {
        customSwapStrategy = newCustomSwapStrategy;
    }

    /**
        @dev An emergency admin backdoor.
        @notice Can be used to destroy this contract when it becomes deprecated.
     */
    function admin_backdoor(address target, bytes calldata data) external onlyAdmin returns(bool, bytes memory) {
        return target.call(data);
    } 

    /**
        @notice We must deposit the coin into the contract first.
        @param tokenAmt indicates the amount of underlying token we want to depost.
     */
    function _compound_deposit(string calldata Coin, uint256 tokenAmt) private {
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
    function _compound_withdraw(string calldata Coin, uint256 tokenAmt) private { 
        ICToken ctoken = ICToken(CompoundLoops[Coin].ctoken);
        require(ctoken.redeem(tokenAmt) == 0, "_compound_withdraw fail");
    }

    /**
        @param tokenAmt indicates the amount of underlying tokens we want
        to borrow.
     */
    function _compound_borrow(string calldata Coin, uint256 tokenAmt) private { 
        ICToken ctoken = ICToken(CompoundLoops[Coin].ctoken);
        require(ctoken.borrow(tokenAmt) == 0, "_compound_borrow fail");
    }

    /**
        @notice Repays underlying tokens. We should check the actual amount
        repayed ourselves, as there can be transaction fees in certain tokens.
        @param tokenAmt indicates the amount of underlying tokens we want
        to repay.
     */
    function _compound_repay(string calldata Coin, uint256 tokenAmt) private { 
        ICToken ctoken = ICToken(CompoundLoops[Coin].ctoken);
        _approve_max(IERC20(CompoundLoops[Coin].token), address(ctoken), tokenAmt);
        require(ctoken.repayBorrow(tokenAmt) == 0, "_compound_repay fail");
    }

    /**
        @return tokens – a safe amount of underlying that can be borrowed.
     */
    function _get_free_to_borrow(string calldata Coin) private view returns (uint256 tokens) {
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
    function _get_free_to_withdraw(string calldata Coin) private view returns (uint256) {
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

    function _swap_strategy(string calldata Coin, uint256 amountOutMinimum) private {
        CompoundLoop storage loop = CompoundLoops[Coin];
        
        if (customSwapStrategy == address(0)) {
            // No custom swap strategy set. Execute default strategy.
            CompoundLoop storage compLoop = CompoundLoops["COMP"];

            uint256 tokenAmt = comp.balanceOf(address(this));

            _approve_max(comp, address(uniswapV3Router), tokenAmt);

            uniswapV3Router.exactInput(ISwapRouter.ExactInputParams({
                path: abi.encodePacked(compLoop.token, compLoop.uniswapFee, wethAddress, loop.uniswapFee, loop.token),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: tokenAmt,
                amountOutMinimum: amountOutMinimum
            }));
        } else {
            // Custom swap strategy set. Calling it now. 
            IERC20 token = IERC20(loop.token);

            uint256 balanceBefore = token.balanceOf(address(this));

            (bool success,) = customSwapStrategy.delegatecall(abi.encodeWithSignature("swap(address,uint256)", loop.token, amountOutMinimum));
            require(success == true, "delegatecall failed");
            require(token.balanceOf(address(this)).sub(balanceBefore) >= amountOutMinimum, "not enough out");
        }
    }

    function _approve_max(IERC20 token, address spender, uint256 amount) private {
        if (token.allowance(address(this), spender) < amount) {
            require(token.approve(spender, type(uint256).max), "approve error");
        }
    }
}
