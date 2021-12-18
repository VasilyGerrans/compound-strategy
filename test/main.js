const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const erc20_abi = require("./abi/ERC20_abi.json");
const cwbtc_abi = require("./abi/cWBTC_abi.json");
const comptroller_abi = require("./abi/comptroller_abi.json");
const uniswapv3router_abi = require("./abi/UniswapV3Router_abi.json");

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

  let deployer,
  CS, 
  cs,
  UniswapV3Router,
  UniswapV3Interface,
  WETH,
  WBTC,
  cWBTC,
  DAI,
  cDAI,
  COMP,
  comptroller,
  participants,
  pMint,
  pBorrow;

  const whaleAddress = "0x176F3DAb24a159341c0509bB36B833E7fdd0a132";
  const mintAmount = "1000000000"; // 10 WBTC

  beforeEach(async () => {
    [ deployer ] = await ethers.getSigners();
    participants = await ethers.getSigners();
    participants.shift();

    pMint =  "100000000";
    pBorrow = "50000000";

    WBTC = new ethers.Contract("0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", erc20_abi, ethers.provider);
    cWBTC = new ethers.Contract("0xccF4429DB6322D5C611ee964527D42E5d685DD6a", cwbtc_abi, ethers.provider);
    COMP = new ethers.Contract("0xc00e94Cb662C3520282E6f5717214004A7f26888", erc20_abi, ethers.provider);

    DAI = new ethers.Contract("0x6B175474E89094C44Da98b954EedeAC495271d0F", erc20_abi, ethers.provider);
    cDAI = new ethers.Contract("0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643", cwbtc_abi, ethers.provider);

    WETH = await (await ethers.getContractFactory("WETH9")).attach("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2");

    UniswapV3Router = new ethers.Contract("0xE592427A0AEce92De3Edee1F18E0157C05861564", uniswapv3router_abi, ethers.provider);
    UniswapV3Interface = new ethers.utils.Interface(uniswapv3router_abi);

    /* // Impersonate whale account
    whale = await ethers.getSigner(whaleAddress);
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [whaleAddress],
    }); */

    // give participants some WBTC

    /* for (let i = 0; i < 10; i++) {
      const p = participants[i];
      WBTC.connect(whale).transfer(p.address, "2000000000");
    } */
    
    CS = await ethers.getContractFactory("CompoundStrategy01");
    cs = await CS.connect(deployer).deploy();
    await cs.deployed();  
    
    comptroller = new ethers.Contract("0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B", comptroller_abi, ethers.provider);
  });

  /* 
  it("does the same thing but with loops", async () => {
    console.log("\nAFTER TRANSFER");
    await WBTC.connect(whale).transfer(cs.address, "100000000");
    await logBalances(cs.address, [WBTC, cWBTC, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
    let stat = await cs.compound_stat_strat("WBTC");
    console.log(stat);
    
    console.log("\nAFTER WIND");
    await cs.connect(whale).compound_loop_deposit("WBTC", 9);
    await logBalances(cs.address, [WBTC, cWBTC, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
    stat = await cs.compound_stat_strat("WBTC");
    console.log(stat);
    console.log("\n");

    console.log("\nAFTER ADD");
    await cs.connect(whale).compound_corrector_add("WBTC");
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

    console.log("\nAFTER REMOVE");
    await cs.connect(whale).compound_corrector_remove("WBTC");
    await logBalances(cs.address, [WBTC, cWBTC, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
    stat = await cs.compound_stat_strat("WBTC");
    console.log(stat);

    console.log("\nAFTER 3 STEP UNWIND");
    await cs.connect(whale).compound_loop_withdraw_part("WBTC", 3);
    await logBalances(cs.address, [WBTC, cWBTC, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
    stat = await cs.compound_stat_strat("WBTC");
    console.log(stat);

    console.log("\nAFTER FULL UNWIND");
    await cs.connect(whale).compound_loop_withdraw_all("WBTC");
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
 */

  it("does nice multicall on Uniswap v3", async () => {
    const initialEther = ethers.utils.parseEther("10");
    await WETH.deposit({value: initialEther});
    await WETH.approve(UniswapV3Router.address, initialEther);

    // console.log(UniswapV3Interface);
    const encodedSwap0 = UniswapV3Interface.encodeFunctionData('exactInputSingle', [
      [WETH.address, DAI.address, 3000, deployer.address, Date.now() + 120, initialEther, "0", "0"]
    ]);

    console.log(encodedSwap0);

    await UniswapV3Router.connect(deployer).multicall([encodedSwap0]);

    await logBalances(deployer.address, [WETH, DAI]);
  });

  /* it("DAI strat", async () => {
    const initialEther = ethers.utils.parseEther("10");

    await WETH.deposit({value: initialEther});
    await logBalances(deployer.address, [WETH]);

    let deadline = Date.now() + 120; // let the transaction simmer for around 2 minutes
    await WETH.approve(UniswapV3Router.address, initialEther);
    await UniswapV3Router.connect(deployer).exactInputSingle([
      WETH.address, DAI.address, 3000, deployer.address, deadline, initialEther, "0", "0"
    ]);

    // give each participant 500 bucks
    const participantBalance = ethers.utils.parseEther("500");
    for (let i = 0; i < 3; i++) {
      const element = participants[i];
      await DAI.connect(deployer).transfer(element.address, participantBalance);
    }

    await logBalances(deployer.address, [WETH, DAI]);

    const initialDaiBalance = await DAI.balanceOf(deployer.address);

    console.log("\nAFTER TRANSFER");
    await DAI.connect(deployer).transfer(cs.address, initialDaiBalance);
    await logBalances(cs.address, [DAI, cDAI, COMP]);
    await logAccountLiquidity(comptroller, cs.address);

    console.log("\nAFTER WIND");
    await cs.connect(deployer).compound_loop_deposit("DAI", 5);
    await logBalances(cs.address, [DAI, cDAI, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
    let stat = await cs.connect(deployer).compound_stat_strat("DAI");
    console.log(stat);

    console.log("\nAFTER REMOVE");
    await cs.connect(deployer).compound_corrector_remove("DAI");
    await logBalances(cs.address, [DAI, cDAI, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
    stat = await cs.connect(deployer).compound_stat_strat("DAI");
    console.log(stat);

    for (let i = 0; i < 3; i++) {
      console.log("user", i, "is depositing");
      let p = participants[i];

      for (let j = 0; j < 9; j++) { // increase time by 117 seconds with mining
        await network.provider.send("evm_increaseTime", [13]) 
        await network.provider.send("evm_mine")
      }

      await DAI.connect(p).approve(cDAI.address, participantBalance);
      await cDAI.connect(p).mint(participantBalance);
      console.log("user", i, "is borrowing");
      await cDAI.connect(p).borrow("100");
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

      const res = await cDAI.getAccountSnapshot(p.address);

      console.log("user", i, "will return", res[2].toString(), "after borrowing 100 for around 2 days");

      await DAI.connect(p).approve(cDAI.address, res[2]);
      await cDAI.connect(p).repayBorrow(res[2]);
    }

    console.log("\nAFTER OTHER USERS");
    await logBalances(cs.address, [DAI, cDAI, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
    stat = await cs.connect(deployer).compound_stat_strat("DAI");
    console.log(stat);

    console.log("\nAFTER FULL UNWIND");
    await cs.connect(deployer).compound_loop_withdraw_all("DAI");
    await logBalances(cs.address, [DAI, cDAI, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
    stat = await cs.compound_stat_strat("DAI");
    console.log(stat);

    console.log("\nAFTER CLAIM");
    await cs.connect(deployer).compound_comp_claim_in_markets([cDAI.address]);
    await logBalances(cs.address, [DAI, cDAI, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
    stat = await cs.compound_stat_strat("DAI");
    console.log(stat);
  }); */

  // DAI

  // initial DAI: 38934571169404199653703
  // peak cDAI:   582790011504554
  // peak liq:    13564239243237660687010
  // final DAI:   38934555729409238860419
  // final COMP:  49,276,764,635,988,478 = 0.049276...

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
