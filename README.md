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
4. Now its time to isntall the Inky Impression Drivers to the Pi, luckily Pimoroni make this super easy with a one liner. `curl https://get.pimoroni.com/inky | bash` This does take some time to run so patience is key.
5. while this is running its a good time to also prepare the photos you want to display. For best results i found cropping photos to 5:4 aspect ratio also for the script to work out the box right now the photos need to be in .jpg format spefically .JPG or .jpeg will or other formats not work with the randomiser script, I did this as i found the compression algorightm of .jpg work the best with the screens interpreter. As an optional step you could also crop the photo to match the resoltion of the screen (600 x 448 pixels for the 5.7" screen) but i found this made minimal differance. You will also need to name the photos sequentially for the randomiser script to work eg: 1.jpg, 2.jpg, 3.jpg ect. 
6. Once the Pimoroni script has finished installing you will find it has made a new folder in `/home/pi` called Pimoroni you can test the screen by copying a image to the your home folder and running the command `cp /home/pi/Pimoroni/inky/examples/7color/image.py /path/to/your/image.jpg`
7. Once youve confimed its use this oneliner to install the randomiser script to your pi `curl -o /home/pi/ranphoto.py https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/main/ranphoto.py ` You'll also want to copy the image.py script to the `/home/pi` as well, You can either do this mannually or by running the command `cp /home/pi/Pimoroni/inky/examples/7color/image.py /home/pi/image.py`
8. Transfer your photos to your pi to folder in the following location `/home/pi/images/main` for this on windows i used WinSCP.
9. Using `crontab -e` add the following cron job `*/30 * * * * python3 /home/pi/ranphoto.py` you can edit this to suit how oftern you want the photo to refresh. note that this is based on the time not the number of minutes so setting it to every 30 minutes will make it refresh on the top of the hour and at half past the hour. 
10. You'll also want to use your cli text edtior of choice (nano) to change the range of the random number generator to the number of photos you have in the images folder. And thats it for the setup now on your schedule the screen should up date.

### The Frame

For the frame I wanted it to look inconspicous if placed next to a real photo frame, but i also wanted to hide the edges of the inky display so that only the the image was showing as if it was a photo print. Note the following mesurements only apply for the 5.7" version of the screen. 
To do this I decided to make a frame from scratch, I made my frame out of oak but no reason you cant make it out of any other kind of wood or even somthing else. I measured that the visable area of the screen is 115mm x 85mm so i made the inside apature of my frame to this dimention. I then cut a thin sheet of balsa wood to act as a mount/backplate at the apature of the mounting frame if you then line up the stand off locations from the inky frame to the backplate and drill some very small holes for the screws to go through. this will then keep the frame suspended in the display in the correct place.

If you're not into wood working I also created a 3D model of the frame and a backplate for holding the inky frame into the correct position. Please note though that i currently do not have a 3D printer to validate it so double checking the dimentions is reccomended before printing. 
