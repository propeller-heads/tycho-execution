require('dotenv').config();
const {ethers} = require("hardhat");
const hre = require("hardhat");
const {proposeOrSendTransaction} = require("./utils");
const prompt = require('prompt-sync')();

async function main() {
    const network = hre.network.name;
    const routerAddress = process.env.ROUTER_ADDRESS;
    const safeAddress = process.env.SAFE_ADDRESS;
    if (!routerAddress) {
        throw new Error("Missing ROUTER_ADDRESS");
    }

    console.log(`Removing executor on TychoRouter at ${routerAddress} on ${network}`);

    const [signer] = await ethers.getSigners();
    console.log(`Removing executors with account: ${signer.address}`);
    console.log(`Account balance: ${ethers.utils.formatEther(await signer.getBalance())} ETH`);

    const TychoRouter = await ethers.getContractFactory("TychoRouter");
    const router = TychoRouter.attach(routerAddress);

    const executorAddress = prompt("Enter executor address to remove: ");

    if (!executorAddress) {
        console.error("Please provide the executorAddress as an argument.");
        process.exit(1);
    }

    const txData = {
        to: router.address,
        data: router.interface.encodeFunctionData("removeExecutor", [executorAddress]),
        value: "0",
        gasLimit: 50000
    };

    const txHash = await proposeOrSendTransaction(safeAddress, txData, signer, "removeExecutor");
    console.log(`TX hash: ${txHash}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("Error removing executor:", error);
        process.exit(1);
    });