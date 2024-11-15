# Import necessary libraries
from flask import Flask, render_template, send_file, jsonify, request
from web3 import Web3

import argparse

# Replace with your Ethereum node URL
alchemy_url = "https://arb-mainnet.g.alchemy.com/v2/mc0BA8BfQIUKoarWN_eD3LtpBQrQZVKn"
w3 = Web3(Web3.HTTPProvider(alchemy_url))

# Check if connected
print(w3.is_connected())  # Should print True if the connection is successful

balance = w3.eth.get_balance("0x7cEec4d52d270BC1c0dBF11D7e0174f762d489Ca")
print(w3.from_wei(balance, 'ether'))

# Check balance of token 0x0657fa37cdebB602b73Ab437C62c48f02D8b3B8f

token_address = "0x0657fa37cdebB602b73Ab437C62c48f02D8b3B8f"

# Load the contract ABI
erc20_abi = [
    {
        "constant": True,
        "inputs": [],
        "name": "name",
        "outputs": [{"name": "", "type": "string"}],
        "payable": False,
        "stateMutability": "view",
        "type": "function",
    },
    {
        "constant": True,
        "inputs": [],
        "name": "symbol",
        "outputs": [{"name": "", "type": "string"}],
        "payable": False,
        "stateMutability": "view",
        "type": "function",
    },
    {
        "constant": True,
        "inputs": [],
        "name": "decimals",
        "outputs": [{"name": "", "type": "uint8"}],
        "payable": False,
        "stateMutability": "view",
        "type": "function",
    },
    {
        "constant": True,
        "inputs": [{"name": "_owner", "type": "address"}],
        "name": "balanceOf",
        "outputs": [{"name": "balance", "type": "uint256"}],
        "payable": False,
        "stateMutability": "view",
        "type": "function",
    },
]

# Create a contract instance
erc20_contract = w3.eth.contract(address=token_address, abi=erc20_abi)

# Get the token name
token_name = erc20_contract.functions.name().call()
print(token_name)

# Get the token symbol
token_symbol = erc20_contract.functions.symbol().call()
print(token_symbol)

# Get the token decimals
token_decimals = erc20_contract.functions.decimals().call()
print(token_decimals)

# Get the balance of the token
token_balance = erc20_contract.functions.balanceOf("0x7cEec4d52d270BC1c0dBF11D7e0174f762d489Ca").call()
print(token_balance / 10 ** token_decimals)
