#!/usr/bin/python3

# Copyright (c) 2021 Kim Hendrikse

import sys
import os
import parted

VERY_BIG_SIZE = 10000
# Partition size in GB
OS_PARTITION_SIZE = 50
CONFIG_PARTITION_SIZE = 5
SWAP_PARTITION_SIZE = 16
total_size = 0

#
# If size is not defined, then create till the end of the disk. This should be called last
#
def create_partition(disk, partedDevice, size = None):
    global total_size,VERY_BIG_SIZE

    if not size is None:
        geometry = parted.Geometry(start=parted.sizeToSectors(total_size, "GB", partedDevice.sectorSize),
                                   length=parted.sizeToSectors(size, "GB", partedDevice.sectorSize), device=partedDevice)
        min_size = parted.sizeToSectors(size, "GB", partedDevice.sectorSize)
        max_size = parted.sizeToSectors(size + 1, "GB", partedDevice.sectorSize)
    else:
        geometry = parted.Geometry(start=parted.sizeToSectors(total_size, "GB", partedDevice.sectorSize),
                                   end=partedDevice.getLength() - 1,
                                   device=partedDevice)
        min_size = parted.sizeToSectors(1, "GB", partedDevice.sectorSize)
        max_size = parted.sizeToSectors(VERY_BIG_SIZE, "GB", partedDevice.sectorSize)

    new_partition = parted.Partition(disk=disk, type=parted.PARTITION_NORMAL, geometry=geometry)

    # Start constraint, within first 100GB
    start_range = parted.Geometry(device=partedDevice, start=parted.sizeToSectors(total_size, "GB", partedDevice.sectorSize),
                            length=parted.sizeToSectors(VERY_BIG_SIZE, "GB", partedDevice.sectorSize))

    # End constraint, within first 100GB
    end_range = parted.Geometry(device=partedDevice, start=parted.sizeToSectors(total_size, "GB", partedDevice.sectorSize),
                          length=parted.sizeToSectors(VERY_BIG_SIZE, "GB", partedDevice.sectorSize))

    optimal = partedDevice.optimumAlignment
    constraint = parted.Constraint(startAlign=optimal, endAlign=optimal, startRange=start_range, endRange=end_range, minSize=min_size,
                                   maxSize=max_size)
    disk.addPartition(partition=new_partition, constraint=constraint)
    disk.commit()

    if not size is None:
        total_size += size
    print("Created partition")


if len(sys.argv) != 2:
    print("Usage: {} path-to-the-disk".format(sys.argv[0]))
    sys.exit(1)
    
devicePath = sys.argv[1]
if not os.path.exists(devicePath):
    print("Device ({}) does not exist".format(devicePath))
    sys.exit(1)

partedDevice = parted.getDevice(devicePath)
print("Disk model: {}".format(partedDevice.model))
print("")

print("Wiping disk: {}".format(devicePath))
partedDevice.clobber()

print("Creating GPT partitions")
disk = parted.freshDisk(partedDevice, "gpt")

# create_partion(0, disk, 20)
# create_partion(20, disk, 5)

#
# The OS partition - 40GB should be enough to contain the OS, will be mounted read-only during operation
#
create_partition(size=OS_PARTITION_SIZE, disk=disk, partedDevice=partedDevice)

#
# Config partition - Small partition for updateable configuration
#
create_partition(size=CONFIG_PARTITION_SIZE, disk=disk, partedDevice=partedDevice)


#
# swap partition - provide swap even though we don't want to use it perse
#
create_partition(size=SWAP_PARTITION_SIZE, disk=disk, partedDevice=partedDevice)
#
# third partition - The rest of the disk, to be used as a data partition
#
create_partition(disk=disk, partedDevice=partedDevice)

