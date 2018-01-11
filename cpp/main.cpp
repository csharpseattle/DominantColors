#include <stdio.h>
#include <opencv2/opencv.hpp>
#include <queue>

using namespace std;


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


std::vector<cv::Vec3b> get_dominant_colors(t_color_node *root)
{
    std::vector<t_color_node*> leaves = get_leaves(root);
    std::vector<cv::Vec3b> ret;

    for(int i = 0; i < leaves.size(); ++i)
    {
        cv::Mat mean = leaves[i]->mean;
        ret.push_back(cv::Vec3b(mean.at<double>(0) * 255.0f,
                                mean.at<double>(1) * 255.0f,
                                mean.at<double>(2) * 255.0f));
    }

    return ret;
}


cv::Mat get_quantized_image(cv::Mat classes, t_color_node *root)
{
    std::vector<t_color_node*> leaves = get_leaves(root);

    const int height = classes.rows;
    const int width = classes.cols;
    cv::Mat ret(height, width, CV_8UC3, cv::Scalar(0));

    for(int y=0; y<height; ++y)
    {
        uchar *ptrClass = classes.ptr<uchar>(y);

        cv::Vec3b *ptr = ret.ptr<cv::Vec3b>(y);

        for(int x=0; x < width; ++x)
        {
            uchar pixel_class = ptrClass[x];
            for(int i=0; i < leaves.size(); ++i)
            {
                if(leaves[i]->classid == pixel_class)
                {
                    ptr[x] = cv::Vec3b(leaves[i]->mean.at<double>(0)*255,
                                       leaves[i]->mean.at<double>(1)*255,
                                       leaves[i]->mean.at<double>(2)*255);
                }
            }
        }
    }

    return ret;
}


cv::Mat get_viewable_image(cv::Mat classes) {
    const int height = classes.rows;
    const int width = classes.cols;

    const int max_color_count = 18;
    cv::Vec3b *palette = new cv::Vec3b[max_color_count];
    palette[0]  = cv::Vec3b(  0,   0,   0);
    palette[1]  = cv::Vec3b(255,   0,   0);
    palette[2]  = cv::Vec3b(  0, 255,   0);
    palette[3]  = cv::Vec3b(  0,   0, 255);
    palette[4]  = cv::Vec3b(255, 255,   0);
    palette[5]  = cv::Vec3b(  0, 255, 255);
    palette[6]  = cv::Vec3b(255,   0, 255);
    palette[7]  = cv::Vec3b(128, 128, 128);
    palette[8]  = cv::Vec3b(128, 255, 128);
    palette[9]  = cv::Vec3b( 32,  32,  32);
    palette[10] = cv::Vec3b(255, 128, 128);
    palette[11] = cv::Vec3b(128, 128, 255);
    palette[12] = cv::Vec3b(255, 255, 255);
    palette[13] = cv::Vec3b( 32, 128, 128);
    palette[14] = cv::Vec3b(128,  32, 128);
    palette[15] = cv::Vec3b(128, 128,  32);
    palette[16] = cv::Vec3b(128,  32,  32);
    palette[17] = cv::Vec3b( 32, 128,  32);

    cv::Mat ret = cv::Mat(height, width, CV_8UC3, cv::Scalar(0, 0, 0));

    for(int y = 0; y < height; ++y)
    {
        cv::Vec3b *ptr = ret.ptr<cv::Vec3b>(y);
        uchar *ptrClass = classes.ptr<uchar>(y);
        for(int x = 0; x < width; ++x)
        {
            int color = ptrClass[x];
            if(color >= max_color_count)
            {
                printf("You should increase the number of predefined colors!\n");
                continue;
            }

            ptr[x] = palette[color];
        }
    }

    return ret;
}



cv::Mat get_dominant_palette(std::vector<cv::Vec3b> colors)
{
    const int tile_size = 64;
    cv::Mat ret = cv::Mat(tile_size, tile_size*colors.size(), CV_8UC3, cv::Scalar(0));
    for(int i = 0; i < colors.size(); ++i)
    {
        cv::Rect rect(i*tile_size, 0, tile_size, tile_size);
        cv::rectangle(ret, rect, cv::Scalar(colors[i][0], colors[i][1], colors[i][2]), CV_FILLED);
    }

    return ret;
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
std::vector<cv::Vec3b> find_dominant_colors(cv::Mat img, int count)
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

    std::vector<cv::Vec3b> colors = get_dominant_colors(root);

    cv::Mat quantized = get_quantized_image(classes, root);
    cv::Mat viewable = get_viewable_image(classes);
    cv::Mat dom = get_dominant_palette(colors);

    cv::imwrite("./classification.png", viewable);
    cv::imwrite("./quantized.png", quantized);
    cv::imwrite("./palette.png", dom);

    return colors;
}



int main(int argc, char* argv[])
{
    //
    // Check cmd line args
    //
    if(argc<3)
    {
        printf("Usage: %s <image> <count>\n", argv[0]);
        return 0;
    }

    //
    // read the file into an opencv matrix
    //
    char* filename = argv[1];
    cv::Mat matImage = cv::imread(filename);

    if(!matImage.data)
    {
        printf("Unable to open the file: %s\n", filename);
        return 1;
    }

    //
    // get the number of colors from the cmd line
    //
    int count = atoi(argv[2]);
    if(count <=0 || count >255)
    {
        printf("The color count needs to be between 1-255. You picked: %d\n", count);
        return 2;
    }

    //
    // find the dominant colors in the image.  This will output
    // the quantized image and color palette as pngs
    //
    find_dominant_colors(matImage, count);

    return 0;

}
