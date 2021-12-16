const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const erc20_abi = require("./abi/ERC20_abi.json");
const cwbtc_abi = require("./abi/cWBTC_abi.json");
const comptroller_abi = require("./abi/comptroller_abi.json");

async function logBalances(address, tokens) {
  for (let i = 0; i < tokens.length; i++) {
    const element = tokens[i];
    const balance = await element.balanceOf(address);
    console.log(balance);
  }
}

async function logAccountLiquidity(comptroller, address) {
  const res = await comptroller.getAccountLiquidity(address);
  
  console.log(res);
}

describe("CompoundStrategy02", function () {
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
  const oneWBTC = "100000000";

  beforeEach(async () => {
    participants = await ethers.getSigners();
    pMint = "100000000";
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
    
    CS = await ethers.getContractFactory("CompoundStrategy02");
    cs = await CS.connect(whale).deploy();
    await cs.deployed();  
    
    comptroller = new ethers.Contract("0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B", comptroller_abi, ethers.provider);
    
    await WBTC.connect(whale).transfer(cs.address, oneWBTC);
  });

  /* it("calls compound_loop_deposit_001", async () => {
    await cs.connect(whale).compound_loop_deposit_001("WBTC");

    await logBalances(cs.address, [WBTC, cWBTC, COMP]);
    await logAccountLiquidity(comptroller, cs.address);
  }); */

  it("correctly tells me how much underlying we are free to withdraw", async () => {
    console.log("WBTC and cWBTC balances initially:");
    await logBalances(cs.address, [WBTC, cWBTC]);

    /* await cs.connect(whale).compound_loop_deposit_x("WBTC", 1);
    console.log("WBTC and cWBTC balances after 1 loop deposit:"); 
    await logBalances(cs.address, [WBTC, cWBTC]);
    */

    await cs._compound_deposit("WBTC", "100000000");
    console.log("WBTC and cWBTC balances after deposit:");
    await logBalances(cs.address, [WBTC, cWBTC]);

    console.log("how much we are free to borrow:");
    console.log(await cs._get_free_to_borrow("WBTC"));
    console.log("how much we are free to withdraw:");
    console.log(await cs._get_free_to_withdraw("WBTC"));

    /* let borrow = await cs._get_free_to_borrow("WBTC");
    let withdraw = await cs._get_free_to_withdraw("WBTC");

    console.log(borrow);
    console.log(withdraw); */

    /* await cs.connect(whale).compound_corrector_add("WBTC");
    await logBalances(cs.address, [WBTC, cWBTC]); */

    /* borrow = await cs._get_free_to_borrow("WBTC");
    withdraw = await cs._get_free_to_withdraw("WBTC");

    console.log(borrow);
    console.log(withdraw);

    await cs.connect(whale).compound_corrector_remove("WBTC");
    console.log("WBTC and cWBTC balances after corrector remove:");
    await logBalances(cs.address, [WBTC, cWBTC]);

   /*  borrow = await cs._get_free_to_borrow("WBTC");
    withdraw = await cs._get_free_to_withdraw("WBTC");

    console.log(borrow);
    console.log(withdraw);

    await cs.connect(whale).compound_corrector_remove("WBTC");
    console.log("WBTC and cWBTC balances after another corrector remove:");
    await logBalances(cs.address, [WBTC, cWBTC]);

    /* borrow = await cs._get_free_to_borrow("WBTC");
    withdraw = await cs._get_free_to_withdraw("WBTC");

    console.log(borrow);
    console.log(withdraw);

    await cs.connect(whale).compound_corrector_remove("WBTC");
    console.log("WBTC and cWBTC balances after another corrector remove:");
    await logBalances(cs.address, [WBTC, cWBTC]);

    /* borrow = await cs._get_free_to_borrow("WBTC");
    withdraw = await cs._get_free_to_withdraw("WBTC");

    console.log(borrow);
    console.log(withdraw); */
  });
});