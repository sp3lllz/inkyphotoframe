echo "Welcome to the inkyphotoframe instller"
echo "This may take a few minutes but please be on hand for any prompts"
echo "This script is descigned for use with Rasberry Pi devices using the Pimrioni 7 Colour Inky Display only"
echo "No guarantee or warranty is provided with this software please use at your own risk."
echo "This script will make changes to your device including installing software and scripts"
#install pimoroni software
#curl https://get.pimoroni.com/inky | bash
#create nessisary folders
sudo mkdir /home/$USER/inkyframe
sudo mkdir /home/$USER/inkyframe/images
sudo mkdir /home/$USER/inkyframe/images/main
#download scipts from github
sudo curl -o /home/$USER/inkyframe/ranphoto.py https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/main/ranphoto.py
sudo curl -o /home/$USER/inkyframe/ranphoto.sh https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/refs/heads/main/randphoto.sh
sudo curl -o /home/$USER/inkyframe/ranupdate.sh https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/refs/heads/main/ranupdate.sh
#copy image.py script from the pimironi folder to the inkyframe folder
sudo cp /home/$USER/Pimoroni/inky/examples/7color/image.py /home/$USER/inkyframe/image.py
#make scripts executable
sudo chmod +x /home/$USER/inkyframe/ranphoto.py
sudo chmod +x /home/$USER/inkyframe/ranphoto.sh
sudo chmod +x /home/$USER/inkyframe/image.py
sudo chmod +x /home/$USER/inkyframe/ranupdate.sh
#setup chronjob
inkyjob="*/30 * * * * bash /home/$USER/inkyframe/ranphoto.sh"
if crontab -l | grep -Fxq "$inkyjob"; then
    echo "The cron job is already scheduled."
else
    (crontab -l; echo "$inkyjob") | crontab -
    echo "New cron job added."
fi
echo "Installation completed"
echo "We will now display a test image to test everything is working."
#download test image
sudo curl -o /home/$USER/inkyframe/testimage.jpg https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/ebaf87d4ec4db4c45492eafdbb4082691fef1315/inkytest.jpg
source ~/.virtualenvs/pimoroni/bin/activate
python3 /home/$USER/inkyframe/image.py --file /home/$USER/inkyframe/testimage.jpg
echo "image called to screen please give it a few seconds to display"
echo "please place images in the /home/$USER/inkyframe/images/main folder formatted as per the Readme on https://github.com/sp3lllz/inkyphotoframe/blob/main/README.md"
echo "after images have been placed as per the readme please update the maximum number for the random number generator using ranupdate.sh please see the readme for more details"
