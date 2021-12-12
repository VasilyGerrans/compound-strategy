const { expect } = require("chai");
const { ethers } = require("hardhat");
const erc20_abi = require("./abi/ERC20_abi.json");
const cwbtc_abi = require("./abi/cWBTC_abi.json");
const comptroller_abi = require("./abi/comptroller_abi.json");

async function logBalance(address, token0, token1) {
  const balance0 = await token0.balanceOf(address);
  const balance1 = await token1.balanceOf(address);
  
  console.log(balance0, balance1);
}

async function logAccountLiquidity(comptroller, address) {
  const res = await comptroller.getAccountLiquidity(address);
  
  console.log(res);
}

describe("CompoundAnalytics", function () {
  let CS, 
  cs,
  WBTC,
  cWBTC,
  comptroller;

  const whaleAddress = "0x176F3DAb24a159341c0509bB36B833E7fdd0a132";
  const mintAmount = "1000000000"; // 10 WBTC

  before(async () => {
    WBTC = new ethers.Contract("0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", erc20_abi, ethers.provider);
    cWBTC = new ethers.Contract("0xccF4429DB6322D5C611ee964527D42E5d685DD6a", cwbtc_abi, ethers.provider);

    // Impersonate whale account
    whale = await ethers.getSigner(whaleAddress);
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [whaleAddress],
    });
    
    CS = await ethers.getContractFactory("CompoundAnalytics");
    cs = await CS.connect(whale).deploy();
    await cs.deployed();  
    
    comptroller = new ethers.Contract("0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B", comptroller_abi, ethers.provider);
  });

  /* it("Should pull info", async () => {
    const res = await cs.compound_stat();
    console.log(res);
  }); */

  /* it("Should mint", async () => {
    await comptroller.connect(whale).enterMarkets([cWBTC.address]);
    await WBTC.connect(whale).approve(cWBTC.address, mintAmount);
    await cWBTC.connect(whale).mint(mintAmount);
    
    await getBalance(whaleAddress, WBTC, cWBTC);

    const res = await comptroller.getAccountLiquidity(whaleAddress);
    console.log(res);
  }); */

  /* it("Should deposit (mint ctokens) via contract", async () => {
    await WBTC.connect(whale).transfer(cs.address, mintAmount);
    await cs.connect(whale)._compound_deposit("WBTC", mintAmount);

    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);

    // put in 10 cWBTC, which will be much less than what we got
    await cs.connect(whale)._compound_withdraw("WBTC", mintAmount);

    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);
  }); */

  /* it("deposits", async () => {
    await WBTC.connect(whale).transfer(cs.address, mintAmount);
    await cs.connect(whale)._compound_deposit("WBTC", mintAmount);

    console.log("AFTER DEPOSIT");
    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);
  }); */

  it("Successfully borrows", async () => {
    await WBTC.connect(whale).transfer(cs.address, mintAmount);
    
    const res = await cs.connect(whale).compound_stat_comp("WBTC");
    console.log(res);
    
    await cs.connect(whale)._compound_deposit("WBTC", mintAmount);

    console.log("AFTER DEPOSIT");
    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);

    await cs.connect(whale)._compound_borrow("WBTC", "500000000"); // borrow 5 WBTC

    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);

  });

  /* it("Repays borrows", async () => {
    await WBTC.connect(whale).transfer(cs.address, mintAmount);
    await cs.connect(whale)._compound_deposit("WBTC", mintAmount);

    console.log("AFTER DEPOSIT");
    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);

    await cs.connect(whale)._compound_borrow("WBTC", "500000000"); // borrow 5 WBTC

    console.log("AFTER BORROW");
    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);

    await cs.connect(whale)._compound_repay("WBTC", "500000000"); // repay 5 WBTC

    console.log("AFTER REPAY");
    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);
  }); */

  /* it("Loop borrows", async () => {
    await WBTC.connect(whale).transfer(cs.address, mintAmount);
    await cs.connect(whale).compound_loop_deposit_001("WBTC");

    console.log("AFTER LOOP");
    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);
  });

  it("Executes strat 1", async () => {
    await WBTC.connect(whale).transfer(cs.address, "50000000");
    await cs.connect(whale).compound_loop_deposit_001("WBTC");

    console.log("AFTER LOOP");
    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);
  }); */

  /* it("Executes strat 2", async () => {
    await WBTC.connect(whale).transfer(cs.address, mintAmount);

    console.log("BEFORE LOOP");
    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);

    await cs.connect(whale).compound_loop_deposit_002("WBTC", mintAmount); // use 1 WBTC for strat

    console.log("AFTER LOOP");
    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);
  }); */

/* 
  it("deposits", async () => {
    await WBTC.connect(whale).transfer(cs.address, mintAmount);

    console.log("BEFORE DEPOSIT");
    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);

    await cs.connect(whale)._compound_deposit("WBTC", mintAmount);

    console.log("AFTER DEPOSIT");

    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);
  }); */

  /* it("loops epically", async () => {
    await WBTC.connect(whale).transfer(cs.address, mintAmount);

    console.log("BEFORE WIND");
    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);

    await cs.connect(whale)._loop_deposit_x("WBTC", 10, mintAmount);

    console.log("AFTER WIND");
    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);
  }); */

  /* it("checks withdraw amount correctly", async () => {
    await WBTC.connect(whale).transfer(cs.address, mintAmount);
    await cs.connect(whale)._compound_deposit("WBTC", mintAmount);

    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);

    await cs.connect(whale)._get_free_to_withdraw("WBTC");
    const res0 = await cs.connect(whale).freetowithdraw();
    const res1 = await cs.connect(whale).freetowithdrawctokens();

    console.log(res0, res1);

    const actualWithdraw = (Number(res1) + 50).toString();
    console.log(actualWithdraw);

    await cs.connect(whale)._compound_withdraw("WBTC", actualWithdraw);

    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);
  }); */

  // 49868023252
  // 114500882947 (3 loop)
  // 123706033805 (4 loop)
  // 140766531145 (10 loop)

  // 49867854479
  // 49867854483
  // 49867854339

  /* it("Repays borrow later", async () => {
    await WBTC.connect(whale).transfer(cs.address, mintAmount);
    await cs.connect(whale)._compound_deposit("WBTC", mintAmount);

    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);

    await cs.connect(whale)._compound_borrow("WBTC", "500000000"); // borrow 5 WBTC

    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);
    
    await hre.network.provider.send("evm_increaseTime", [60 * 60 * 24 * 2]) // increase time by 2 days

    await cs.connect(whale)._compound_repay("WBTC", "500000000"); // repay 5 WBTC

    await logBalance(cs.address, WBTC, cWBTC);
    await logAccountLiquidity(comptroller, cs.address);
  }); */
});
