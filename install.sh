#!/bin/bash
# Get the logged-in username
username=$(whoami)
echo "Installing Pimoroni Inky library..."
# Install Pimoroni Inky library
curl https://get.pimoroni.com/inky | bash
echo "Creating 'images' folder in the user's home directory..."
# Create the "images" folder in the user's home directory if it doesn't exist
sudo mkdir -p /home/"$username"/images
echo "Downloading 'ranphoto.py' script..."
# Download the Python script from the URL and save it in the user's home directory
curl -o /home/"$username"/ranphoto.py https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/main/ranphoto.py
echo "Making 'ranphoto.py' script executable..."
# Make the downloaded Python script executable
sudo chmod +x /home/"$username"/ranphoto.py
echo "Copying 'image.py' file to the user's home directory..."
# Copy the image.py file to the user's home directory
sudo cp /home/"$username"/Pimoroni/inky/examples/7color/image.py /home/"$username"
echo "Adding cron job to the crontab..."
# Add cron job to the crontab
(crontab -l -u "$username" 2>/dev/null; echo "*/30 * * * * python3 /home/$username/ranphoto.py") | crontab -u "$username" -
echo "Cron job added successfully."
