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

async function logAnalytics(strategy, comptroller, tokens) {
  await logBalances(strategy.address, tokens);
  await logAccountLiquidity(comptroller, strategy.address);
  let symbol = await tokens[0].symbol();
  let stat = await strategy.compound_stat(symbol);
  console.log("compound_stat output:", stat);
}

describe("CompoundStrategy01", function () {
  this.timeout(0);

  let deployer,
  CS, 
  cs,
  UniswapV3Router,
  WETH,
  WBTC,
  cWBTC,
  COMP,
  comptroller,
  participants;

  beforeEach(async () => {
    [ deployer ] = await ethers.getSigners();
    participants = await ethers.getSigners();
    participants.shift();

    WETH = await (await ethers.getContractFactory("WETH9")).attach("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2");
    WBTC = new ethers.Contract("0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", erc20_abi, ethers.provider);
    cWBTC = new ethers.Contract("0xccF4429DB6322D5C611ee964527D42E5d685DD6a", cwbtc_abi, ethers.provider);
    COMP = new ethers.Contract("0xc00e94Cb662C3520282E6f5717214004A7f26888", erc20_abi, ethers.provider);

    UniswapV3Router = new ethers.Contract("0xE592427A0AEce92De3Edee1F18E0157C05861564", uniswapv3router_abi, ethers.provider);

    const ten_ether = ethers.utils.parseEther("10");

    // set us up with some WBTC via UniswapV3
    await WETH.deposit({value: ten_ether});
    await WETH.approve(UniswapV3Router.address, ten_ether);
    await UniswapV3Router.connect(deployer).exactInputSingle([
      WETH.address, WBTC.address, 3000, deployer.address, Date.now() + 120, ten_ether, "0", "0"
    ]);
    
    CS = await ethers.getContractFactory("CompoundStrategy01");
    cs = await CS.connect(deployer).deploy();
    await cs.deployed();  
    
    comptroller = new ethers.Contract("0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B", comptroller_abi, ethers.provider);
  });

  it("demonstrates hypothetical scenario", async () => {
    const WBTCbalance = await WBTC.balanceOf(deployer.address);

    console.log("\nAFTER TRANSFER");
    await WBTC.connect(deployer).transfer(cs.address, WBTCbalance);
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);

    console.log("\nAFTER WIND");
    await cs.connect(deployer).compound_loop_deposit("WBTC", 5);
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);

    console.log("\nAFTER ANOTHER WRAP");
    await cs.connect(deployer).compound_corrector_add("WBTC");
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);


    console.log("\nWAITING...");
    for (let i = 0; i < (6646 * 2); i++) { // do nothing for roughly 2 days
      await network.provider.send("evm_increaseTime", [13]);
      await network.provider.send("evm_mine");
    }

    console.log("\nAFTER WAITING");
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);


    console.log("\nAFTER CLAIM");
    await cs.connect(deployer).compound_comp_claim_in_markets([cWBTC.address]);
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);


    console.log("\nAFTER REINVEST");
    await cs.connect(deployer).compound_comp_reinvest("WBTC", 0, 0);
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);


    console.log("\nAFTER ONE UNWRAP");
    await cs.connect(deployer).compound_corrector_remove("WBTC");
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);


    console.log("\nAFTER FULL UNWIND");
    await cs.connect(deployer).compound_loop_withdraw_all("WBTC");
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);
  });
});
