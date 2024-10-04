from setuptools import setup, find_packages

setup(
    name='Arcadium Server',  # Replace with your app's name
    version='1.0.0',
    packages=find_packages(),
    include_package_data=True,  # This will include static files and assets
    install_requires=[
        'flask',  # Web framework
        'Pillow',  # Image processing library
    ],
    entry_points={
        'console_scripts': [
            'myapp = server:main',  # If server.py has a main() function
        ],
    },
    author='Your Name',
    description='Web application for serving Arcadium',
    license='MIT',  # Specify your license
)
