/* TESTNET ONLY. Never use this script with a real asset or mainnet. */
const { ethers } = require("hardhat");

async function main() {
  const net = await ethers.provider.getNetwork();
  if (net.chainId !== 97n) throw new Error("Refusing deployment: only BNB Smart Chain testnet (97) allowed");
  const [deployer] = await ethers.getSigners();
  if (!deployer) throw new Error("No deployer signer. Set DEPLOYER_PRIVATE_KEY locally; do not post it in chat.");

  let tokenAddress = process.env.TEST_TOKEN_ADDRESS;
  if (!tokenAddress) {
    console.log("Deploying unlimited-mint MOCK USDT for sandbox testing ONLY.");
    const token = await ethers.deployContract("MockUSDT");
    await token.waitForDeployment();
    tokenAddress = await token.getAddress();
  }
  if (!ethers.isAddress(tokenAddress)) throw new Error("Invalid TEST_TOKEN_ADDRESS");
  const operator = process.env.SETTLEMENT_OPERATOR_ADDRESS || deployer.address;
  if (!ethers.isAddress(operator)) throw new Error("Invalid settlement operator");

  const vault = await ethers.deployContract("NexoraFundedVault", [
    tokenAddress,
    deployer.address,
    operator
  ]);
  await vault.waitForDeployment();
  const address = await vault.getAddress();

  console.log(JSON.stringify({
    status: "TESTNET_DEPLOYED",
    chainId: 97,
    token: tokenAddress,
    vault: address,
    owner: deployer.address,
    operator,
    vaultExplorer: "https://testnet.bscscan.com/address/" + address,
    note: "Mock asset only. No guaranteed yield, no mainnet activation."
  }, null, 2));
}

main().catch(e=>{ console.error(e.message); process.exitCode=1; });
