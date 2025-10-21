import { ethers } from "hardhat";

/**
 * Test script to verify Ethereum mainnet fork is working correctly
 * and that we can interact with the real Uniswap V2 Router
 */
async function main() {
  console.log("🔍 Testing Ethereum Mainnet Fork Configuration...\n");

  // Check network
  const network = await ethers.provider.getNetwork();
  console.log("📡 Network:", network.name);
  console.log("🔗 Chain ID:", network.chainId.toString());

  // Get current block
  const blockNumber = await ethers.provider.getBlockNumber();
  console.log("📦 Current Block:", blockNumber);
  console.log("");

  // Connect to Uniswap V2 Router on Ethereum mainnet
  const UNISWAP_V2_ROUTER = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
  console.log("🦄 Connecting to Uniswap V2 Router:", UNISWAP_V2_ROUTER);

  const router = await ethers.getContractAt(
    "IUniswapV2Router02",
    UNISWAP_V2_ROUTER
  );

  try {
    // Test 1: Get WETH address
    console.log("\n✅ Test 1: Calling WETH()...");
    const wethAddress = await router.WETH();
    console.log("   WETH Address:", wethAddress);

    // Test 2: Get Factory address
    console.log("\n✅ Test 2: Calling factory()...");
    const factoryAddress = await router.factory();
    console.log("   Factory Address:", factoryAddress);

    // Test 3: Check WETH contract exists
    console.log("\n✅ Test 3: Checking WETH contract code...");
    const wethCode = await ethers.provider.getCode(wethAddress);
    console.log("   WETH Contract has code:", wethCode !== "0x" ? "YES" : "NO");
    console.log("   WETH Code length:", wethCode.length, "bytes");

    console.log("\n✅ SUCCESS: Ethereum mainnet fork is working correctly!");
    console.log("🎉 You can now interact with real Uniswap V2 contracts in tests\n");

  } catch (error: any) {
    console.error("\n❌ ERROR:", error.message);
    console.error("\n🔧 Troubleshooting:");
    console.error("   1. Check MAINNET_RPC_URL in .env is a valid Ethereum mainnet endpoint");
    console.error("   2. Ensure forking.enabled = true in hardhat.config.ts");
    console.error("   3. Verify you have a stable internet connection");
    console.error("   4. Try increasing the blockNumber in hardhat.config.ts\n");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
