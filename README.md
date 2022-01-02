# sbts-base

Base system for the stalkedbythestate project

The project installs a robust project environment for the NVIDIA Jetson nano, NX and AGX computers. This is used for the StalkedByTheState (https://github.com/hcfman/stalkedbythestate) project but can be used as a base for other projects as well.

It is installed as follows:

* Install the latest SD card image for your system, for example, follow instructions for the Jetson Nano here: https://developer.nvidia.com/embedded/learn/get-started-jetson-nano-devkit

If you have a Jetson Nano, then you should disable the GUI interface first with:

```
sudo systemctl set-default multi-user.target; sudo reboot
```
There's not enough memory on the Nano for both running the algorithms and a GUI interface.

Then you can install:

```
git clone https://github.com/hcfman/sbts-base.git
cd sbts-base
sudo -H ./sbts_install_base.sh
```

After the first reboot the system should be in read-write mode.

Permanent changes can be made in read-write mode.

After permanent OS changes have been made, revert to read-only mode for operation as follows:

```
cd sbts-bin
sudo ./make_readonly.sh
sudo reboot
```

For detailed tutorials about using this software please view my YouTube channel

https://www.youtube.com/channel/UCXn7Z37_xwuxLPpcPTtdNRQ

Kim Hendrikse
