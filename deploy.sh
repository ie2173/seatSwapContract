#!/bin/bash
# Quick Deployment Script for TicketFactory
# Usage: ./deploy.sh [network]
# Example: ./deploy.sh sepolia

set -e

# Load environment variables
source .env

# Get network from argument (default to sepolia)
NETWORK=${1:-sepolia}

echo "🚀 Deploying TicketFactory to $NETWORK..."

if [ "$NETWORK" = "sepolia" ]; then
    RPC_URL=$SEPOLIA_RPC_URL
elif [ "$NETWORK" = "mainnet" ]; then
    RPC_URL=$MAINNET_RPC_URL
    echo "⚠️  WARNING: Deploying to MAINNET!"
    echo "Press Ctrl+C to cancel, or Enter to continue..."
    read
else
    echo "❌ Unknown network: $NETWORK"
    echo "Usage: ./deploy.sh [sepolia|mainnet]"
    exit 1
fi

# Check if using keystore or private key
# Expand tilde in KEYSTORE_PATH
KEYSTORE_PATH="${KEYSTORE_PATH/#\~/$HOME}"
if [ -n "$KEYSTORE_PATH" ] && [ -f "$KEYSTORE_PATH" ]; then
    echo "🔐 Using keystore deployment..."
    forge script script/DeployFactory.s.sol:DeployFactory \
        --rpc-url $RPC_URL \
        --account cheersFinance.eth \
        --sender $SENDER_ADDRESS \
        --broadcast \
        --verify \
        --etherscan-api-key $ETHERSCAN_API_KEY
else
    echo "🔑 Using private key deployment..."
    forge script script/DeployFactory.s.sol:DeployFactory \
        --rpc-url $RPC_URL \
        --private-key $PRIVATE_KEY \
        --broadcast \
        --verify \
        --etherscan-api-key $ETHERSCAN_API_KEY
fi

echo "✅ Deployment complete!"
