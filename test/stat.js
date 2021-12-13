const { expect } = require("chai");
const { ethers } = require("hardhat");
const erc20_abi = require("./abi/ERC20_abi.json");
const cwbtc_abi = require("./abi/cWBTC_abi.json");
const comptroller_abi = require("./abi/comptroller_abi.json");

describe("Stats", function () { 
    let CS, 
    cs,
    WBTC,
    cWBTC,
    comptroller;

    before(async () => {
        WBTC = new ethers.Contract("0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", erc20_abi, ethers.provider);
        cWBTC = new ethers.Contract("0xccF4429DB6322D5C611ee964527D42E5d685DD6a", cwbtc_abi, ethers.provider);

        CS = await ethers.getContractFactory("CompoundStrategy01");
        cs = await CS.deploy();
        await cs.deployed();  
        
        comptroller = new ethers.Contract("0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B", comptroller_abi, ethers.provider);
    });

    it("fetches stats about COMP rewards for the WBTC market", async () => {
        const res = await cs.compound_stat_comp("WBTC");
        console.log(res);
    });

    it("fetches stats about the WBTC market", async () => {
        const res = await cs.compound_stat_coin("WBTC");
        console.log(res);
    });

    it("fetches global stats about Compound and the deployed contract address", async () => {
        const res = await cs.compound_stat_global();
        console.log(res);
    });
})