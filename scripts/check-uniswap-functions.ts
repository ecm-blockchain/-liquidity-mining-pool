import { ethers } from "hardhat";

/**
 * Check what functions are available on the real Uniswap V2 Router
 */
async function main() {
  console.log("🔍 Checking Uniswap V2 Router Functions...\n");

  const UNISWAP_V2_ROUTER = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
  
  // Get the contract bytecode
  const code = await ethers.provider.getCode(UNISWAP_V2_ROUTER);
  console.log("✅ Router contract exists:", code !== "0x");
  console.log("   Bytecode length:", code.length, "bytes\n");

  // Try to connect with full interface
  const router = await ethers.getContractAt(
    "IUniswapV2Router02",
    UNISWAP_V2_ROUTER
  );

  console.log("📋 Testing Router Functions:\n");

  // Test 1: WETH (should work)
  try {
    const weth = await router.WETH();
    console.log("✅ WETH():", weth);
  } catch (e: any) {
    console.log("❌ WETH() failed:", e.message);
  }

  // Test 2: factory (should work)
  try {
    const factory = await router.factory();
    console.log("✅ factory():", factory);
  } catch (e: any) {
    console.log("❌ factory() failed:", e.message);
  }

  // Test 3: getAmountOut (THIS is the problem!)
  try {
    const amountIn = ethers.parseUnits("1000", 6); // 1000 USDT
    const reserveIn = ethers.parseUnits("50000", 6); // 50K USDT
    const reserveOut = ethers.parseEther("100000"); // 100K ECM

    console.log("\n🧪 Testing getAmountOut():");
    console.log("   Input: 1000 USDT");
    console.log("   ReserveIn: 50000 USDT");
    console.log("   ReserveOut: 100000 ECM");
    
    const amountOut = await router.getAmountOut(amountIn, reserveIn, reserveOut);
    console.log("✅ getAmountOut():", ethers.formatEther(amountOut), "ECM");
  } catch (e: any) {
    console.log("❌ getAmountOut() FAILED:", e.message);
    console.log("\n⚠️  ISSUE: The real Uniswap V2 Router doesn't have getAmountOut()!");
    console.log("   The function exists in UniswapV2Library, not the Router contract.");
  }

  // Test 4: getAmountsOut (this SHOULD work)
  try {
    console.log("\n🧪 Testing getAmountsOut() with path:");
    const WETH = await router.WETH();
    const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"; // USDC on mainnet
    
    const path = [WETH, USDC];
    const amountsOut = await router.getAmountsOut(ethers.parseEther("1"), path);
    console.log("✅ getAmountsOut() works!");
    console.log("   1 WETH =", ethers.formatUnits(amountsOut[1], 6), "USDC");
  } catch (e: any) {
    console.log("❌ getAmountsOut() failed:", e.message);
  }

  console.log("\n" + "=".repeat(70));
  console.log("💡 SOLUTION:");
  console.log("   Your PoolManager calls router.getAmountOut() which doesn't exist");
  console.log("   on the real Uniswap router. You have two options:");
  console.log("");
  console.log("   1. Calculate locally using the Uniswap formula (recommended)");
  console.log("   2. Use mock router for testing (current approach)");
  console.log("   3. Use getAmountsOut() with a path instead");
  console.log("=".repeat(70) + "\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
