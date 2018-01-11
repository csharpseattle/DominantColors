# Find Dominant Colors in an image

Contains two versions:
1) a cpp command line utility
2) an Objective-c Category that extends UIImage to find its dominant colors.

## Overview

This demonstrates how to find the dominant colors in an image. Included are Swift and command-line(cpp) samples.  The command-line version outputs a PNG file of the palette and a PNG image quantized to the resulting palette.  The Swift version uses an Objective-C Category to extend UIImage and Objective-C Bridging Header to expose the extension to Swift.  A Camera preview allows the user to take a photo from which dominant colors are found.

Based on algorithms found [here.] (http://aishack.in/tutorials/dominant-color-implementation)


## Requirements

- *OpenCV 3.0* --  OpenCV is included as a submodule.  The opencv2.framework needs to be built for ios.
- *pkg-config*  -- used to find the necessary libs when building the command line utilty

### Building the Swift app

1. This project has the OpenCV repo as a submodule.
   - If you want to use it be sure to do `git submodule init`.
        The `opencv2.framework` will be built by an XCode build script
   - If you wish to use your own (probably because the framework takes so long to build and opencv2.framework is already built) then open `opencv.xcconfig` and edit the path to point to your own clone of the opencv repo at `https://github.com/opencv/opencv`

2. Select your device in the device list and hit ⌘R


### Running the command line:
- use the included makefile to compile the command line version

`./getDominantColors <image> <number of colors>`

- image is the image your wish to quantize
- the number of colors is the number of dominant colors you wish to find.
