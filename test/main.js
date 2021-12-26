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

  before(async () => {
    [ deployer ] = await ethers.getSigners();
    participants = await ethers.getSigners();
    participants.shift();

    comptroller = new ethers.Contract("0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B", comptroller_abi, ethers.provider);

    WETH = await (await ethers.getContractFactory("WETH9")).attach("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2");
    WBTC = new ethers.Contract("0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", erc20_abi, ethers.provider);
    cWBTC = new ethers.Contract("0xccF4429DB6322D5C611ee964527D42E5d685DD6a", cwbtc_abi, ethers.provider);
    COMP = new ethers.Contract("0xc00e94Cb662C3520282E6f5717214004A7f26888", erc20_abi, ethers.provider);

    UniswapV3Router = new ethers.Contract("0xE592427A0AEce92De3Edee1F18E0157C05861564", uniswapv3router_abi, ethers.provider);

    const ten_ether = ethers.utils.parseEther("20");

    // set us up with some WBTC via UniswapV3
    await WETH.deposit({value: ten_ether});
    await WETH.approve(UniswapV3Router.address, ten_ether);
    await UniswapV3Router.connect(deployer).exactInputSingle([
      WETH.address, WBTC.address, 3000, deployer.address, Date.now() + 120, ten_ether, "0", "0"
    ]);
    
    CS = await ethers.getContractFactory("CompoundStrategy01");
    cs = await CS.connect(deployer).deploy(
      comptroller.address,
      COMP.address,
      UniswapV3Router.address,
      WETH.address,
      [
        "WBTC", 
        "COMP", 
        "DAI", 
        "USDC"
      ],
      [
        [
          "0xccF4429DB6322D5C611ee964527D42E5d685DD6a",
          "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
          ethers.utils.parseEther("0.95"),
          ethers.utils.parseEther("0.99"),
          3000
        ],
        [
          "0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4",
          "0xc00e94Cb662C3520282E6f5717214004A7f26888", 
          ethers.utils.parseEther("0.95"),
          ethers.utils.parseEther("0.99"),
          3000
        ], 
        [
          "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643",
          "0x6B175474E89094C44Da98b954EedeAC495271d0F",
          ethers.utils.parseEther("0.95"),
          ethers.utils.parseEther("0.99"),
          500
        ],
        [
          "0x39AA39c021dfbaE8faC545936693aC917d5E7563",
          "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
          ethers.utils.parseEther("0.95"),
          ethers.utils.parseEther("0.99"),
          3000
        ]
      ]
    );
    await cs.deployed();  
  });
  
  it("transfers", async () => {
    await WBTC.connect(deployer).transfer(cs.address, "100000000");
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);
  });
  
  it("winds", async () => {
    await cs.connect(deployer).compound_loop_deposit("WBTC", 20);
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);
  });

  it("wraps", async () => {
    await cs.connect(deployer).compound_corrector_add("WBTC");
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);
  });

  it("waits", async () => {
    for (let i = 0; i < (6646 * 2); i++) { // do nothing for roughly 2 days
      await network.provider.send("evm_increaseTime", [13]);
      await network.provider.send("evm_mine");
    }
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);
  });

  it("claims", async () => {
    await cs.connect(deployer).compound_comp_claim_in_markets([cWBTC.address]);
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);
  });

  it("reinvests", async () => {
    await cs.connect(deployer).compound_comp_reinvest("WBTC", 0, 0);
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);
  });

  it("unwraps", async () => {
    await cs.connect(deployer).compound_corrector_remove("WBTC");
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);
  });

  it("unwinds", async () => {
    await cs.connect(deployer).compound_loop_withdraw_all("WBTC");
    await logAnalytics(cs, comptroller, [WBTC, cWBTC, COMP]);
  });
});
