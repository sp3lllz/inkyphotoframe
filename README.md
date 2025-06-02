# inkyphotoframe

This is my latest project to make a digital photo frame that is virtually indistinguishable from a real photo frame.
I have also written a script to pick a random number and use that to determine which photo to display you can have this refresh are whatever interval youd like with chrontab which I will detail how to do in the set up instructions.

## How to

### Heres what you will need for this project.

1. Any rasberry pi from pi 2b or newer including the pi zero or zero 2 will work but I recommend the pi 3b or zero W as a minimum for the built in wifi.
2. A MicroSD card the bigger the SD card the more photos you can have in your random pool.
3. The [Pimoroni 5.7" 7 color e-ink display.](https://shop.pimoroni.com/products/inky-impression-5-7) This should work with the [4"](https://shop.pimoroni.com/products/inky-impression-4) or [7.3"](https://shop.pimoroni.com/products/inky-impression-7-3) version as well but you would need to format your photos and make your frame to different dimentions from the later steps of this tutoral.
4. A frame to put the assembly in once you're finished, I'll get into the details on this later

### Setup of the electronics and code. 

1. Use the [rasberry pi imaging tool](https://www.raspberrypi.com/software/) to image your MicroSD card with Rasberry PiOS Lite and use the advanced options to enable SSH and add your wifi SSID
2. put the MicroSD card into the Pi and then attach it to the inky dispaly using the GPIO headers. If you have a Pi Zero W or Pi Zero W 2 you can attach the Pi directly to the board if youre using a B sized Pi use the standoffs and GPIO extention headers included with the display.
3. Boot the Pi up and connect using your SSH client of choice
4. Now its time to install the inkyphotoframe software, this can be done with a simple one line command
`curl https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/refs/heads/main/setup.sh | bash`
First this will runn Pimirionis setup if you have already run that you can skip this by chosing no at the yes no prompt. After that it will create the nessisary folder structure and download the scripts to the pi and finally create a timed crontab job to rotate the image every 30 minutes at the top of the hour and at half past the hour. At the end of the script it should update the photo frame with the following image ![inkytest.jpg](https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/ebaf87d4ec4db4c45492eafdbb4082691fef1315/inkytest.jpg)
5. Now navigate to the following folder `/var/inkyframe/images/main` this is where you should place your images. For the best results images should be resize to 800*480 resolution but cropping to the same aspect ratio will usually serfice. Images should be renamed to be in the following format, `1.jpg` `2.jpg` `3.jpg` ect. all images should be in `.jpg` format.
6. Once you have renamed all your images to this format ensuring there are no gaps in the numbering run the ranupdate.sh script like so `bash /var/inkyframe/ranupdate.sh` and enter the highest number of the photo names. This will set the random number picker to only pick between 1 and the maximum number photo so that it can never select a photo that doesnt exist.
7. Setup is now complete! The photo should uptatically update as per the schedule. 

### The Frame

There is a few different options for the frame, you can make something from scratch or you can even use something like [this](https://makerworld.com/en/models/1221196-ikea-rodlam-inky-impression-7-mount#profileId-1238116) to mount it in an off the shelf frame to make it even more inconspicuous! 
