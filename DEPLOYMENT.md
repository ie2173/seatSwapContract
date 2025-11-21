# Deployment Guide

## Prerequisites

1. Make sure you have Foundry installed
2. Copy `.env.example` to `.env` and fill in your values
3. Ensure you have ETH in your wallet for gas fees

## Deploy to Sepolia Testnet

### Option 1: Using Private Key (from .env)

```bash
# Load environment variables
source .env

# Deploy (dry run simulation)
forge script script/DeployFactory.s.sol:DeployFactory \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY

# Deploy for real
forge script script/DeployFactory.s.sol:DeployFactory \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast

# Deploy and verify on Etherscan
forge script script/DeployFactory.s.sol:DeployFactory \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### Option 2: Using Keystore (More Secure - Recommended)

```bash
# List your accounts
cast wallet list

# Deploy with keystore (will prompt for password)
forge script script/DeployFactory.s.sol:DeployFactory \
  --rpc-url $SEPOLIA_RPC_URL \
  --account crowweb3.eth \
  --sender $SENDER_ADDRESS \
  --broadcast

# Deploy and verify
forge script script/DeployFactory.s.sol:DeployFactory \
  --rpc-url $SEPOLIA_RPC_URL \
  --account cheersFinance.eth \
  --sender $SENDER_ADDRESS \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

## Deploy to Mainnet

```bash
# Load environment variables
source .env

# Deploy (dry run simulation) - ALWAYS TEST FIRST!
forge script script/DeployFactory.s.sol:DeployFactory --rpc-url $MAINNET_RPC_URL

# Deploy for real (USE WITH CAUTION!)
forge script script/DeployFactory.s.sol:DeployFactory --rpc-url $MAINNET_RPC_URL --broadcast

# Deploy and verify on Etherscan
forge script script/DeployFactory.s.sol:DeployFactory --rpc-url $MAINNET_RPC_URL --broadcast --verify
```

## Using Keystore (More Secure)

```bash
# Deploy with keystore
forge script script/DeployFactory.s.sol:DeployFactory \
  --rpc-url $SEPOLIA_RPC_URL \
  --account your_keystore_name \
  --broadcast
```

## Environment Variables

- `PRIVATE_KEY`: Your wallet private key (without 0x prefix)
- `SEPOLIA_RPC_URL`: Sepolia RPC endpoint (e.g., Alchemy, Infura)
- `MAINNET_RPC_URL`: Ethereum Mainnet RPC endpoint
- `USDC_ADDRESS`: USDC contract address (optional, defaults to Sepolia USDC)
- `ETHERSCAN_API_KEY`: For contract verification

## USDC Addresses

- **Sepolia Testnet**: `0xAF33ADd7918F685B2A82C1077bd8c07d220FFA04`
- **Ethereum Mainnet**: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`

## After Deployment

The script will output:

- Factory contract address
- Owner address
- USDC address being used

Save these addresses for frontend integration!

## Verify Contract Manually

If automatic verification fails:

```bash
forge verify-contract \
  --chain-id 11155111 \
  --num-of-optimizations 200 \
  --watch \
  --constructor-args $(cast abi-encode "constructor(address,address)" YOUR_OWNER_ADDRESS YOUR_USDC_ADDRESS) \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --compiler-version v0.8.30 \
  CONTRACT_ADDRESS \
  src/Factory.sol:TicketFactory
```

## Quick Start (Easiest Method)

```bash
# Make script executable (first time only)
chmod +x deploy.sh

# Deploy to Sepolia
./deploy.sh sepolia

# Deploy to Mainnet (with confirmation prompt)
./deploy.sh mainnet
```

## Troubleshooting

### "Insufficient funds"

Make sure your wallet has enough ETH for gas fees.

### "Nonce too low/high"

Wait a few seconds and try again, or use `--legacy` flag.

### "Contract verification failed"

Try manual verification or check that your Etherscan API key is correct.

### "environment variable not found"

Make sure you've created a `.env` file from `.env.example` and filled in your values.
