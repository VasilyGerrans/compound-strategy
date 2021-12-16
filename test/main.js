const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const erc20_abi = require("./abi/ERC20_abi.json");
const cwbtc_abi = require("./abi/cWBTC_abi.json");
const comptroller_abi = require("./abi/comptroller_abi.json");

async function logBalances(address, tokens) {
  for (let i = 0; i < tokens.length; i++) {
    const element = tokens[i];
    const balance = await element.balanceOf(address);
    const symbol = await element.symbol();
    console.log(symbol, "balance:", balance.toString());
  }
}

async function logAccountLiquidity(comptroller, address) {
  const res = await comptroller.getAccountLiquidity(address);
  
  console.log("Account liquidity:", res[1].toString());
  console.log("Account shortfall:", res[2].toString());
}

describe("CompoundStrategy01", function () {
  this.timeout(0);

  let CS, 
  cs,
  WBTC,
  cWBTC,
  COMP,
  comptroller,
  participants,
  pMint,
  pBorrow;

  const whaleAddress = "0x176F3DAb24a159341c0509bB36B833E7fdd0a132";
  const mintAmount = "1000000000"; // 10 WBTC

  beforeEach(async () => {
    participants = await ethers.getSigners();
    pMint =  "100000000";
    pBorrow = "50000000";

    WBTC = new ethers.Contract("0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", erc20_abi, ethers.provider);
    cWBTC = new ethers.Contract("0xccF4429DB6322D5C611ee964527D42E5d685DD6a", cwbtc_abi, ethers.provider);
    COMP = new ethers.Contract("0xc00e94Cb662C3520282E6f5717214004A7f26888", erc20_abi, ethers.provider);

    // Impersonate whale account
    whale = await ethers.getSigner(whaleAddress);
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [whaleAddress],
    });

    // give participants some WBTC
    for (let i = 0; i < 10; i++) {
      const p = participants[i];
      WBTC.connect(whale).transfer(p.address, "2000000000");
    }
    
    CS = await ethers.getContractFactory("CompoundStrategy01");
    cs = await CS.connect(whale).deploy();
    await cs.deployed();  
    
    comptroller = new ethers.Contract("0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B", comptroller_abi, ethers.provider);
  });

  /////////////////////////////////////
  //////////// THIS  WORKS ////////////
  /////////////////////////////////////

  /*
  it("does regular strat", async () => {
    await WBTC.connect(whale).transfer(cs.address, mintAmount);

    console.log("AFTER TRANSFER");
    await logBalances(cs.address, [WBTC, cWBTC, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
    
    await cs.connect(whale)._compound_deposit("WBTC", "1000000000");

    console.log("AFTER DEPOSIT");
    await logBalances(cs.address, [WBTC, cWBTC, COMP]);
    await logAccountLiquidity(comptroller, cs.address);

    for (let i = 0; i < 3; i++) {
      console.log("mint", i);
      let p = participants[i];

      for (let j = 0; j < 9; j++) { // increase time by 117 seconds with mining
        await network.provider.send("evm_increaseTime", [13]) 
        await network.provider.send("evm_mine")
      }

      await WBTC.connect(p).approve(cWBTC.address, pMint);
      await cWBTC.connect(p).mint(pMint);
      console.log("borrow", i);
      await cWBTC.connect(p).borrow(pBorrow);
    }

    for (let i = 0; i < 13292; i++) { // do nothing for roughly 2 days
      await network.provider.send("evm_increaseTime", [13]);
      await network.provider.send("evm_mine");
    }

    for (let i = 0; i < 3; i++) {
      console.log("redeem", i);
      let p = participants[i];

      for (let j = 0; j < 9; j++) { // increase time by 117 seconds with mining
        await network.provider.send("evm_increaseTime", [13]) 
        await network.provider.send("evm_mine")
      }

      const res = await cWBTC.getAccountSnapshot(p.address);

      await WBTC.connect(p).approve(cWBTC.address, res[2]);
      await cWBTC.connect(p).repayBorrow(res[2]);
    }

    console.log("AFTER OTHER USERS");
    await logBalances(cs.address, [WBTC, cWBTC, COMP]);
    await logAccountLiquidity(comptroller, cs.address);

    const withdraw = await cWBTC.balanceOf(cs.address);

    console.log("WITHDRAW AMOUNT:", withdraw);

    await cs.connect(whale)._compound_withdraw("WBTC", withdraw);

    console.log("AFTER WITHDRAW");
    await logBalances(cs.address, [WBTC, cWBTC, COMP]);
    await logAccountLiquidity(comptroller, cs.address);

    console.log("AFTER CLAIM");

    await cs.connect(whale).compound_comp_claim();
    await logBalances(cs.address, [WBTC, cWBTC, COMP]);
    await logAccountLiquidity(comptroller, cs.address);  
  });
  */

  it("does the same thing but with loops", async () => {
    console.log("\nAFTER TRANSFER");
    await WBTC.connect(whale).transfer(cs.address, "100000000");
    await logBalances(cs.address, [WBTC, cWBTC, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
    let stat = await cs.compound_stat_strat("WBTC");
    console.log(stat);
    
    console.log("\nAFTER WIND");
    await cs.connect(whale).compound_loop_deposit("WBTC", 15);
    await logBalances(cs.address, [WBTC, cWBTC, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
    stat = await cs.compound_stat_strat("WBTC");
    console.log(stat);
    console.log("\n");

    for (let i = 0; i < 3; i++) {
      console.log("user", i, "is depositing");
      let p = participants[i];

      for (let j = 0; j < 9; j++) { // increase time by 117 seconds with mining
        await network.provider.send("evm_increaseTime", [13]) 
        await network.provider.send("evm_mine")
      }

      await WBTC.connect(p).approve(cWBTC.address, pMint);
      await cWBTC.connect(p).mint(pMint);
      console.log("user", i, "is borrowing");
      await cWBTC.connect(p).borrow(pBorrow);
    }

    console.log("waiting 2 days");
    for (let i = 0; i < (13292); i++) { // do nothing for roughly 2 days
      await network.provider.send("evm_increaseTime", [13]);
      await network.provider.send("evm_mine");
    }

    for (let i = 0; i < 3; i++) {
      console.log("user", i, "is redeeming");
      let p = participants[i];

      for (let j = 0; j < 9; j++) { // increase time by 117 seconds with mining
        await network.provider.send("evm_increaseTime", [13]) 
        await network.provider.send("evm_mine")
      }

      const res = await cWBTC.getAccountSnapshot(p.address);

      console.log("user", i, "will return", res[2].toString(), "WBTC after borrowing", pBorrow, "for around 2 days");

      await WBTC.connect(p).approve(cWBTC.address, res[2]);
      await cWBTC.connect(p).repayBorrow(res[2]);
    }

    console.log("\nAFTER OTHER USERS");
    await logBalances(cs.address, [WBTC, cWBTC, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
    stat = await cs.compound_stat_strat("WBTC");
    console.log(stat);

    await cs.connect(whale).compound_loop_withdraw_all("WBTC");
    console.log("\nAFTER UNWIND");
    await logBalances(cs.address, [WBTC, cWBTC, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
    stat = await cs.compound_stat_strat("WBTC");
    console.log(stat);

    console.log("\nAFTER CLAIM");
    await cs.connect(whale).compound_comp_claim_in_markets([cWBTC.address]);
    await logBalances(cs.address, [WBTC, cWBTC, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
    stat = await cs.compound_stat_strat("WBTC");
    console.log(stat);
  });

  /*
  it("collects stats", async () => {
    console.log("\nAFTER TRANSFER");
    await WBTC.connect(whale).transfer(cs.address, "100000000");

    let stat = await cs.compound_stat_strat("WBTC");
    console.log(stat);

    console.log("\nAFTER WIND");
    await cs.connect(whale).compound_wind_loop("WBTC", 5);

    stat = await cs.compound_stat_strat("WBTC");
    console.log(stat);

    console.log("\nAFTER UNWIND");
    await cs.connect(whale).compound_unwind_loop_full("WBTC");
    stat = await cs.compound_stat_strat("WBTC");
    console.log(stat);
  });
  */

  // 15 loops 
  // cWBTC:         14216526139
  // after users:   86756679504103781828
  // WBTC:          99962265
  // COMP:          129179534961793251
  
  // 10 loops
  // cWBTC:         14039716713
  // after users:   681698131225684407393
  // WBTC:          99963012
  // COMP:          126787161283027335
  
  // 5 loops
  // cWBTC:         12859866108
  // after users:   4682801263081524106853
  // WBTC:          99967989
  // COMP:          110821463063847480
  
  // liq:           105521330784657814682
  // liq:           699987718784873436714
  // liq:           4698752968076817501327
});
