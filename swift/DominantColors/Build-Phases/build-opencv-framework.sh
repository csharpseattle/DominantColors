#!/bin/bash

#
# Give a default value to the opencv directory if it isn't set already
#
OPENCV_ROOT=${OPENCV_ROOT-../external/opencv}

echo "using OPENCV_ROOT: $OPENCV_ROOT"

#
# Check to see if the ios framework has been built.
#
if [ ! -d $OPENCV_ROOT/ios/opencv2.framework ]; then

    #
    # it looks like it isn't.  We should start the framework build
    #

    #
    # Check for python.  the opencv build_framework.py is a python script
    #
    which python > /dev/null
    if [ $? -eq 0 ]; then

        #
        # run the build_framework.py script.
        #
        if [ -f $OPENCV_ROOT/platforms/ios/build_framework.py ]; then
            python $OPENCV_ROOT/platforms/ios/build_framework.py $OPENCV_ROOT/ios
        else
            echo "build_framework.py script not found"
            exit 1
        fi
    else
        echo "python not found"
        exit 1
    fi
fi

exit 0
