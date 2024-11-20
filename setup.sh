echo "Welcome to the inkyphotoframe instller"
echo "This may take a few minutes but please be on hand for any prompts"
echo "This script is descigned for use with Rasberry Pi devices using the Pimrioni 7 Colour Inky Display only"
echo "No guarantee or warranty is provided with this software please use at your own risk."
echo "This script will make changes to your device including installing software and scripts"
#install pimoroni software
curl https://get.pimoroni.com/inky | bash
#create nessisary folders
sudo mkdir /var/inkyframe
sudo mkdir /var/inkyframe/images
sudo mkdir /var/inkyframe/images/main
sudo chown -R $USER:$USER /var/inkyframe
sudo chmod -R u+rwx /var/inkyframe
#download scipts from github
curl -o /var/inkyframe/ranphoto.py https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/main/ranphoto.py
curl -o /var/inkyframe/ranphoto.sh https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/refs/heads/main/randphoto.sh
curl -o /var/inkyframe/ranupdate.sh https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/refs/heads/main/ranupdate.sh
#copy image.py script from the pimironi folder to the inkyframe folder
cp /var/Pimoroni/inky/examples/7color/image.py /var/inkyframe/image.py
#make scripts executable
sudo chmod +x /var/inkyframe/ranphoto.py
sudo chmod +x /var/inkyframe/ranphoto.sh
sudo chmod +x /var/inkyframe/image.py
sudo chmod +x /var/inkyframe/ranupdate.sh
#setup chronjob
inkyjob="*/30 * * * * bash /var/inkyframe/ranphoto.sh"
if crontab -l | grep -Fxq "$inkyjob"; then
    echo "The cron job is already scheduled."
else
    (crontab -l; echo "$inkyjob") | crontab -
    echo "New cron job added."
fi
echo "Installation completed"
echo "We will now display a test image to test everything is working."
#download test image
curl -o /var/inkyframe/testimage.jpg https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/ebaf87d4ec4db4c45492eafdbb4082691fef1315/inkytest.jpg
source ~/.virtualenvs/pimoroni/bin/activate
python3 /var/inkyframe/image.py --file /var/inkyframe/testimage.jpg
echo "please place images in the /var/inkyframe/images/main folder formatted as per the Readme on https://github.com/sp3lllz/inkyphotoframe/blob/main/README.md"
echo "after images have been placed as per the readme please update the maximum number for the random number generator using ranupdate.sh please see the readme for more details"
