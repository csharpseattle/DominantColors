//
//  UiImage+GetDominantColors.h
//  DominantColors
//
//  Created by Sharp, Chris T on 12/22/17.
//  Copyright © 2017 Apple. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIkit.h>

//
// This Objective-C Category extends UIImage to return
// an NSArray of the dominant colors in the image. 
//
@interface UIImage (getDominantColors)
- (NSArray<UIColor*> *) getDominantColors:(int) numberOfColors;
@end
