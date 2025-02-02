import { run, ethers } from "hardhat";
import { BigNumber, Contract, ContractFactory } from "ethers";
import { addresses } from "../../../utils/contracts";

/**
 * NOTE: First run `protocol.ts` -> update addresses in `utils/contracts.ts` -> run `rewards.ts` -> update address in `utils/contracts.ts`
 */

async function main() {
  await run("compile");

  console.log("\n");

  const packAddress: string = addresses.matic.pack;

  const manualGasPrice: BigNumber = ethers.utils.parseUnits("50", "gwei");
  const [deployer] = await ethers.getSigners();

  console.log(`Deploying contracts with account: ${await deployer.getAddress()}`);

  // Deploy Rewards.sol
  const Rewards_Factory: ContractFactory = await ethers.getContractFactory("Rewards");
  const rewards: Contract = await Rewards_Factory.deploy(packAddress, { gasPrice: manualGasPrice });

  console.log("Rewards.sol deployed at: ", rewards.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });

