# Import necessary libraries
from flask import Flask, render_template, send_file, jsonify
from PIL import Image, ImageEnhance
from io import BytesIO
import argparse


menu_items = [
    {"name": "Claim Pool", "endpoint": "pool"},
    {"name": "Mine", "endpoint": "mine"},
    {"name": "Token Info", "endpoint": "info"},
    {"name": "Socials", "endpoint": "socials"},
    {"name": "Staking", "endpoint": "staking"},
]

# Load base images
treasure_img = Image.open("assets/treasure.png").convert("RGBA")  # Ensure it's in RGBA mode
sparkles_img = Image.open("assets/sparkles.png").convert("RGBA")  # Ensure it's in RGBA mode

# Ensure both images have the same size for composition
sparkles_img = sparkles_img.resize(treasure_img.size)

# Trial function to adjust sparkle opacity
def apply_sparkles(base_img, overlay_img, sparkle_opacity=1.0):
    # Adjust sparkle opacity (sparkle_opacity should be between 0.0 to 1.0)
    sparkle_layer = overlay_img.copy()  # Copy the overlay image to avoid modifying the original
    # Get the alpha channel of the sparkle image (transparency)
    alpha = sparkle_layer.split()[3]
    alpha = ImageEnhance.Brightness(alpha).enhance(sparkle_opacity)  # Adjust brightness to simulate opacity
    sparkle_layer.putalpha(alpha)

    # Composite the base and sparkle images together
    composite = Image.alpha_composite(base_img, sparkle_layer)

    return composite

app = Flask(__name__)


@app.route('/')
def index():
    return render_template('index.html', menu_items=menu_items)

@app.route('/pool')
def pool():
    return render_template('rewardpool.html', menu_items=menu_items)

@app.route('/games/mancala')
def mancala():
    return app.send_static_file('games/mancala.html')

#@app.route('/games/chess')
#def chess():
#    return app.send_static_file('games/chess.html')

@app.route('/utils/random')
def random():
    return app.send_static_file('utils/random.html')

@app.route('/utils/uniswap')
def uniswap():
    return app.send_static_file('utils/uniswap.html')

@app.route('/mine')
def mine():
    return render_template('mine.html', menu_items=menu_items)

@app.route('/media')
def media():
    sparkle_opacity_value = 0.9
    final_img = apply_sparkles(treasure_img, sparkles_img, sparkle_opacity=sparkle_opacity_value)
    
    # Create an in-memory bytes buffer
    img_io = BytesIO()
    
    # Save the image to the buffer in PNG format
    final_img.save(img_io, 'PNG')
    
    # Seek to the beginning of the buffer to prepare for reading
    img_io.seek(0)

    # Use send_file to send the image from the buffer
    return send_file(img_io, mimetype='image/png')

# New route to serve trading pools static page pool_info.html
@app.route('/info')
def info():
    return render_template('token_info.html', menu_items=menu_items)

# Route to serve socials
@app.route('/socials')
def socials():
    return render_template('socials.html', menu_items=menu_items)

@app.route('/staking')
def staking():
    return render_template('staking.html', menu_items=menu_items)

# Route to serve token list as JSON
@app.route('/tokens')
def tokenlist():
    # Updated token list with additional metadata
    token_list = {
        "name": "Barayin Ecosystem Tokens",
        "keywords": [
            "barayin",
            "ecosystem",
            "tokens",
            "governance",
            "community",
            "freedom",
            "prosperity",
            "decentralization",
            "cooperation",
            "heritage",
            "entertainment"
        ],
        "tags": {
            "gaming": {
                "name": "Gaming",
                "description": "Tokens related to gaming projects."
            },
            "social": {
                "name": "Social",
                "description": "Tokens related to social and community projects."
            },
            "governance": {
                "name": "Governance",
                "description": "Tokens related to governance within the Barayin ecosystem."
            },
            "heritage": {
                "name": "Heritage",
                "description": "Tokens focused on preserving cultural heritage and reconciliation."
            }
        },
        "timestamp": "2024-10-30T00:00:00Z",
        "tokens": [
            {
                "chainId": 42161,
                "address": "0xf70bad81af569a6a0e6a0096530585606ac68725",
                "symbol": "AYIN",
                "name": "Ayin",
                "decimals": 18,
                "tags": ["social", "governance"]
            },
            {
                "chainId": 42161,
                "address": "0x0657fa37cdebB602b73Ab437C62c48f02D8b3B8f",
                "symbol": "ACM",
                "name": "Arcadium",
                "decimals": 18,
                "tags": ["gaming", "entertainment"]
            },
            {
                "chainId": 42161,
                "address": "0x332ab16ce09f0fb18618219ba8658682e78bffe0",
                "symbol": "OLV",
                "name": "Olive",
                "decimals": 18,
                "tags": ["social", "heritage"]
            },
            {
                "chainId": 42161,
                "address": "0xd558fcFEce17e4B3591D9f718c4B8B67Ded81cBA",
                "symbol": "WAN",
                "name": "Sewan",
                "decimals": 18,
                "tags": ["social", "heritage"]
            },
            {
                "chainId": 42161,
                "address": "0xD24989CF630cc6b8EB3f70D1b56dFcE4d56c6615",
                "symbol": "SKL",
                "name": "Shekel",
                "decimals": 18,
                "tags": ["social", "heritage"]
            },
            {
                "chainId": 42161,
                "address": "0x6f6a5b1328ec5795f6b6f498a3e324aba59ad2e7",
                "symbol": "BATO",
                "name": "Bato",
                "decimals": 18,
                "tags": ["social", "heritage"]
            }
        ],
        "version": {
            "major": 1,
            "minor": 0,
            "patch": 0
        }
    }
    return jsonify(token_list)

# All other routes should go to a static page about feature not yet being implemented rather than basic 404
@app.errorhandler(404)
def page_not_found(e):
    return app.send_static_file('not_implemented.html')

if __name__ == '__main__':
    # Parse command line arguments, including debug mode, server port, etc.
    parser = argparse.ArgumentParser(description='Arcadium Server')
    parser.add_argument('--debug', action='store_true', help='Enable debug mode')
    parser.add_argument('--port', type=int, default=5000, help='Port number')
    parser.add_argument('--host', type=str, default='0.0.0.0', help='Host IP address')
    args = parser.parse_args()

    # Run the Flask app
    app.run(debug=args.debug, port=args.port, host=args.host)  # Set host to '
