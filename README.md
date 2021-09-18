# sbts-base

Base system for the stalkedbythestate project

The project installs a robust project environment for the NVIDIA Jetson nano, NX and AGX computers. This is used for the StalkedByTheState (https://github.com/hcfman/stalkedbythestate) project but can be used as a base for other projects as well.

It is installed as follows:

* Install the latest SD card image for your system, for example, follow instructions for the Jetson Nano here: https://developer.nvidia.com/embedded/learn/get-started-jetson-nano-devkit

If you have a Jetson Nano, then you should disable the GUI interface first with:

```
sudo systemctl set-default multi-user.target; sudo reboot
```


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

This release is in preparation stage. i.e. it's not formally released yet as I'm working on documentation and instructional videos. It all works fine but likely you won't know what to do with it just yet.
