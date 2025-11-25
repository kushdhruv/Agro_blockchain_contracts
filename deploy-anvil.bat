@echo off
REM Deploy AgroChain contracts to Anvil local network

echo 🚀 Deploying AgroChain contracts to Anvil...

REM Set the private key (Anvil default account #0)
set PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

REM RPC URL for local Anvil
set RPC_URL=http://127.0.0.1:8545

echo.
echo 📦 Step 1: Deploying AgroToken...
forge script script/DeployAgroToken.s.sol --rpc-url %RPC_URL% --private-key %PRIVATE_KEY% --broadcast -vvvv

echo.
echo 📦 Step 2: Deploying all other contracts...
forge script script/DeployAgroBlockchain.s.sol --rpc-url %RPC_URL% --private-key %PRIVATE_KEY% --broadcast -vvvv

echo.
echo ✅ All deployments complete!
echo.
echo 📝 Contract addresses have been logged above.
echo 📝 Update src/contracts/addresses.ts in the frontend with these addresses.
