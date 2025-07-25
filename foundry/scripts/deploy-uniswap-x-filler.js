require('dotenv').config();
const {ethers} = require("hardhat");
const hre = require("hardhat");
const path = require("path");
const fs = require("fs");

async function main() {
    const network = hre.network.name;
    let uniswapXReactor;
    let nativeToken;
    if (network === "ethereum") {
        uniswapXReactor = "0x00000011F84B9aa48e5f8aA8B9897600006289Be";
        nativeToken = "0x0000000000000000000000000000000000000000";
    } else if (network === "base") {
        uniswapXReactor = "0x000000001Ec5656dcdB24D90DFa42742738De729";
        nativeToken = "0x0000000000000000000000000000000000000000";
    } else if (network === "unichain") {
        uniswapXReactor = "0x00000006021a6Bce796be7ba509BBBA71e956e37";
        nativeToken = "0x0000000000000000000000000000000000000000";
    } else {
        throw new Error(`Unsupported network: ${network}`);
    }

    const routerAddressesFilePath = path.join(__dirname, "../../config/router_addresses.json");
    const tychoRouter = JSON.parse(fs.readFileSync(routerAddressesFilePath, "utf8"))[network];

    console.log(`Deploying Uniswap X filler to ${network} with:`);
    console.log(`- Tycho router: ${tychoRouter}`);
    console.log(`- Uniswap X reactor: ${uniswapXReactor}`);
    console.log(`- Native token: ${nativeToken}`);

    const [deployer] = await ethers.getSigners();
    console.log(`Deploying with account: ${deployer.address}`);
    console.log(`Account balance: ${ethers.utils.formatEther(await deployer.getBalance())} ETH`);

    const UniswapXFiller = await ethers.getContractFactory("UniswapXFiller");
    const filler = await UniswapXFiller.deploy(tychoRouter, uniswapXReactor, nativeToken);

    await filler.deployed();
    console.log(`Uniswap X Filler deployed to: ${filler.address}`);

    console.log("Waiting for 1 minute before verifying the contract on the blockchain explorer...");
    await new Promise(resolve => setTimeout(resolve, 60000));

    // Verify on Etherscan
    try {
        await hre.run("verify:verify", {
            address: filler.address,
            constructorArguments: [tychoRouter, uniswapXReactor, nativeToken],
        });
        console.log(`Uniswap X filler verified successfully on blockchain explorer!`);
    } catch (error) {
        console.error(`Error during blockchain explorer verification:`, error);
    }

}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("Deployment failed:", error);
        process.exit(1);
    });