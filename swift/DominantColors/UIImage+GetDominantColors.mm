//
//  UiImage+GetDominantColors.mm
//
//  Created by Sharp, Chris T on 12/22/17.
//  Copyright © 2017 Apple. All rights reserved.
//

#import "UIImage+GetDominantColors.h"
#ifdef __cplusplus
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#include <opencv2/opencv.hpp>
#pragma clang diagnostic pop
#import <opencv2/imgcodecs/ios.h>
#endif

//
// This Objective-C Category extends UIImage to return
// an NSArray of the dominant colors in the image.
//
@implementation UIImage (getDominantColors)

- (NSArray<UIColor*> *) getDominantColors: (int) numberOfColors
{
    //
    // Verify that we have a valid number of colors.
    //
    if(numberOfColors <= 0 || numberOfColors > 255)
    {
        printf("The color count needs to be between 1-255. You picked: %d\n", numberOfColors);
        return nil;
    }

    //
    // Make an openCV Mat from the UIImage
    //
    cv::Mat cvMat = [self convertUIImageToCVMat:self];


    //
    // Check our cv Mat object first.
    //
    if(!cvMat.data)
    {
        printf("no Image data.\n");
        return nil;
    }

    //
    // determine the dominant colors and return
    //
    NSArray<UIColor*> * colors = [self find_dominant_colors:cvMat count:numberOfColors];
    return colors;
}

//
// This method converts the given UIImage to an openCV Mat.
// Using CoreGraphics methods the image is scaled down, a CGContext is created,
// and the image is drawn into the cv::Mat object.  The resulting cv::Mat is returned.
//
- (cv::Mat) convertUIImageToCVMat:(UIImage*) image
{
    //
    // Create a CGImageRef from the UIImage
    //
    CGImageRef imageRef = image.CGImage;

    //
    // To create the Bitmap Context we will need to gather the
    // colorSpace, the number of Components per pixel and the type of Alpha
    // from the CGImageRef
    //
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(imageRef);
    size_t numberOfComponents = CGColorSpaceGetNumberOfComponents(colorSpace);
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(imageRef);

    //
    // for perf reasons we need to scale the image down.  A typical iPhone portrait
    // image will be scaled down to 240x320.  Use a scale factor to scale both width
    // and height so that we keep aspect ratio
    //
    CGFloat scaleFactor = 240 / image.size.width;
    CGFloat cols = image.size.width * scaleFactor;
    CGFloat rows = image.size.height * scaleFactor;

    //
    // The camera preview may give us a "sideways" image. If necessary we can simply
    // swap the height and width.
    //
    if (image.imageOrientation == UIImageOrientationLeft ||
        image.imageOrientation == UIImageOrientationRight)
    {
        cols = image.size.height * scaleFactor;
        rows = image.size.width * scaleFactor;
    }

    //
    // Lastly we will need the number of bits per pixel component.
    //
    size_t numComponentsIncludingAlpha = (alphaInfo == kCGImageAlphaNone) ? numberOfComponents : numberOfComponents + 1;
    size_t bitsPerComponent = CGImageGetBitsPerPixel(imageRef) / numComponentsIncludingAlpha;

    //
    // We need to specify the byte order and alpha type.  Otherwise we
    // might draw into the context in the wrong order.
    //
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | alphaInfo;

    //
    // We have all the info we need.  Create the cv::Mat object to fill
    // and create the context.
    //
    cv::Mat cvMat(rows, cols, (int) CV_8UC(numComponentsIncludingAlpha));
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // Pointer to data
                                                    cols,                       // Width of bitmap
                                                    rows,                       // Height of bitmap
                                                    bitsPerComponent,           // Bits per component
                                                    cvMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    bitmapInfo); // Bitmap info flags

    //
    // Draw the image into the bitmap context.
    //
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), imageRef);

    //
    // We no longer need the context.
    //
    CGContextRelease(contextRef);

    //
    // Remove the alpha channel if the image had one.
    //
    if (alphaInfo != kCGImageAlphaNone)
    {
        cv::cvtColor(cvMat, cvMat, CV_RGBA2RGB);
    }

    return cvMat;
}


//
// We define a node for the tree that holds the information
// of each color "class".
// The node holds an ID, the mean and covariance of each class
// and the pointers to the left and right nodes.
//
typedef struct t_color_node
{
    cv::Mat     mean;
    cv::Mat     covariance;
    uchar       classid;

    t_color_node *left;
    t_color_node *right;
} t_color_node;


//
// this method searches the tree for the highest classID
// and returns the max + 1
//
int get_next_classid(t_color_node *root)
{
    int maxid = 0;
    std::queue<t_color_node*> queue;
    queue.push(root);

    while(queue.size() > 0)
    {
        t_color_node *current = queue.front();
        queue.pop();

        if(current->classid > maxid)
        {
            maxid = current->classid;
        }

        if(current->left)
        {
            queue.push(current->left);
        }

        if(current->right)
        {
            queue.push(current->right);
        }
    }

    return maxid + 1;
}


//
// This method calculates the mean and covariance for the pixel of the given class
//
void get_class_mean_cov(cv::Mat img, cv::Mat classes, t_color_node *node) {
    const int width = img.cols;
    const int height = img.rows;
    const uchar classid = node->classid;

    //
    // Create a couple of matrices to hold the mean and covariance.
    //
    cv::Mat mean = cv::Mat(3, 1, CV_64FC1, cv::Scalar(0));
    cv::Mat cov  = cv::Mat(3, 3, CV_64FC1, cv::Scalar(0));

    //
    // Loop through all pixels.
    //
    double pixcount = 0;
    for(int y = 0; y < height; ++y)
    {
        cv::Vec3b *ptr = img.ptr<cv::Vec3b>(y);
        uchar* ptrClass = classes.ptr<uchar>(y);
        for(int x = 0; x < width; ++x)
        {
            //
            // we ignore pixels that aren't a member of the
            // current class
            //
            if(ptrClass[x] != classid)
            {
                continue;
            }
            cv::Vec3b color = ptr[x];

            //
            // create a 3x1 matrix to hold the color.  We normalize
            // the color values to between 0 and 1 to avoid overflows
            // as we sum all the color values for calculating mean.
            //
            cv::Mat scaled = cv::Mat(3, 1, CV_64FC1, cv::Scalar(0));
            scaled.at<double>(0) = color[0]/255.0f;
            scaled.at<double>(1) = color[1]/255.0f;
            scaled.at<double>(2) = color[2]/255.0f;

            mean = mean + scaled;
            cov  = cov + (scaled * scaled.t());
            pixcount++;
        }
    }

    //
    // complete the covariance
    //
    cov = cov - (mean * mean.t()) / pixcount;

    //
    // up until now mean has actually been a summation
    // dividing by the pixel count makes it a mean
    //
    mean = mean / pixcount;

    //
    // assign the values to the node
    //
    node->mean = mean.clone();
    node->covariance = cov.clone();
    return;
}


//
// Walk the tree and return the node with
// the highest covariance eigenvalue
//
t_color_node* get_max_eigenvalue_node(t_color_node *current) {
    double max_eigen = -1;

    //
    // a couple of matrices to hold the max eigen
    //
    cv::Mat eigenvalues, eigenvectors;

    //
    // Handle the case where the given node is the
    // whole tree. (a tree with 1 node)
    //
    t_color_node *ret = current;
    if(!current->left && !current->right)
    {
        return current;
    }

    //
    // push the node to start the search
    //
    std::queue<t_color_node*> queue;
    queue.push(current);

    while(queue.size() > 0)
    {
        //
        // Pop a node off the queue
        //
        t_color_node *node = queue.front();
        queue.pop();

        //
        // if it has children push those on and continue.
        // we are only concerned with the leaf nodes.
        //
        if(node->left && node->right)
        {
            queue.push(node->left);
            queue.push(node->right);
            continue;
        }

        //
        // otherwise, we must be a leaf node.  Note that partitioning always
        // creates both left and right children.  We don't have the case where
        // a node has only 1 child.  Now calculate the eigenvalues of the covariance
        // matrix and pick the max.  cv::eigen will return eigenvalues in
        // descending order. To pick the highest value we choose the value at index 0.
        //
        cv::eigen(node->covariance, eigenvalues, eigenvectors);
        double val = eigenvalues.at<double>(0);
        if(val > max_eigen)
        {
            max_eigen = val;
            ret = node;
        }
    }

    return ret;
}


//
// This method walks the tree and returns a vector of
// the leaf nodes. Each leaf node represents a dominant
// color in the image.
//
std::vector<t_color_node*> get_leaves(t_color_node *root)
{
    //
    // our return vector of leaf nodes
    //
    std::vector<t_color_node*> leaf_nodes;

    //
    // maintain a queue of nodes.  We will
    // walk the tree and only add nodes
    // if they don't have children.
    //
    std::queue<t_color_node*> queue;
    queue.push(root);

    while(queue.size() > 0)
    {
        t_color_node *current = queue.front();
        queue.pop();

        if(current->left && current->right)
        {
            queue.push(current->left);
            queue.push(current->right);
            continue;
        }

        //
        // No Children.  push onto our return list.
        //
        leaf_nodes.push_back(current);
    }

    return leaf_nodes;
}


//
// this method takes a class represented by a cv::Mat and splits it into two
//
void partition_class(cv::Mat img, cv::Mat classes, uchar nextid, t_color_node *node)
{
    const int width = img.cols;
    const int height = img.rows;
    const int classid = node->classid;

    //
    // the new ids for each new node.
    //
    const uchar newidleft = nextid;
    const uchar newidright = nextid + 1;

    //
    // we use the class's mean and covariance
    // come up with a comparison_value for splitting.
    //
    cv::Mat mean = node->mean;
    cv::Mat cov = node->covariance;
    cv::Mat eigenvalues, eigenvectors;
    cv::eigen(cov, eigenvalues, eigenvectors);
    cv::Mat eig = eigenvectors.row(0);
    cv::Mat comparison_value = eig * mean;

    //
    // Setup our new class nodes
    //
    node->left = new t_color_node();
    node->right = new t_color_node();
    node->left->classid = newidleft;
    node->right->classid = newidright;

    //
    // Loop through all pixels in the class
    // and split on the comparison value
    //
    for(int y = 0; y < height; ++y)
    {
        cv::Vec3b *ptr = img.ptr<cv::Vec3b>(y);
        uchar *ptrClass = classes.ptr<uchar>(y);
        for(int x = 0; x < width; ++x)
        {
            //
            // disregard pixels that do not belong to class
            // we are splitting
            //
            if(ptrClass[x] != classid)
            {
                continue;
            }

            cv::Vec3b color = ptr[x];
            cv::Mat scaled = cv::Mat(3, 1, CV_64FC1, cv::Scalar(0));
            scaled.at<double>(0) = color[0]/255.0f;
            scaled.at<double>(1) = color[1]/255.0f;
            scaled.at<double>(2) = color[2]/255.0f;

            cv::Mat this_value = eig*scaled;
            if(this_value.at<double>(0, 0) <= comparison_value.at<double>(0, 0))
            {
                ptrClass[x] = newidleft;
            }
            else
            {
                ptrClass[x] = newidright;
            }
        }
    }
    return;
}


//
// This method determines the dominant colors in the given image.
// Returns an array of UIColors representing the 'count' dominant colors
//
-(NSArray<UIColor*>*) find_dominant_colors: (cv::Mat) img count: (int) count
{
    //
    // we will be bucketing each pixel into one of 'count' Classes.
    // we create a Mat to represent the class of each pixel.
    // each pixel starts out with a class of 1
    const int width  = img.cols;
    const int height = img.rows;
    cv::Mat classes = cv::Mat(height, width, CV_8UC1, cv::Scalar(1));

    //
    // We will maintain a tree of classes.  Every pixel in the
    // image will be eventually mapped to one of the classes.
    // Here we create the inital tree - a tree of one node
    // with a class id of 1
    //
    t_color_node *root = new t_color_node();
    root->classid = 1;
    root->left = NULL;
    root->right = NULL;

    //
    // Initialize our working pointer to the root node.
    //
    t_color_node *next = root;

    //
    // Calculate the initial mean and covariance
    //
    get_class_mean_cov(img, classes, root);


    //
    // Keep splitting until we get to 'count' number of classes
    //
    for(int i = 0; i < count-1; ++i)
    {
        //
        // find the leaf node with the largest eigenvalue
        //
        next = get_max_eigenvalue_node(root);

        //
        // partition on that node.
        //
        partition_class(img, classes, get_next_classid(root), next);

        //
        // now recalculate the mean and covariance for the new classes
        // in each side of the tree
        //
        get_class_mean_cov(img, classes, next->left);
        get_class_mean_cov(img, classes, next->right);
    }


    //
    // Now all pixels have been split into the desired number of
    // classes.  The leaf nodes of the tree have the mean pixel
    // values of each class. Package up an NSArray of UIColors
    // and return.
    //
    std::vector<t_color_node*> leaves = get_leaves(root);
    size_t num_leaves = leaves.size();
    NSMutableArray<UIColor*> * colors = [[NSMutableArray alloc] initWithCapacity:num_leaves];

    for(int i = 0; i < num_leaves; ++i)
    {
        cv::Mat mean = leaves[i]->mean;
        UIColor * color = [UIColor colorWithRed:mean.at<double>(0) green:mean.at<double>(1) blue:mean.at<double>(2) alpha:1.0f];
        [colors addObject:color];
    }

    return colors;
}




@end
