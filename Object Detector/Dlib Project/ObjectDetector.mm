//
//  ObjectDetector.m
//  Dlib Project
//
//  Created by Robert Sanders on 21/01/2017.
//  Copyright © 2017 Red Hand Technologies. All rights reserved.
//

#import "ObjectDetector.h"

#import "Detection.h"

#include <dlib/image_processing.h>
#include <dlib/image_io.h>

using namespace dlib;

typedef scan_fhog_pyramid<pyramid_down<6> > image_scanner_type;

@interface ObjectDetector ()

@property (nonatomic) object_detector<image_scanner_type> detector;
@property (nonatomic) BOOL processingImage;
@property (nonatomic) BOOL isObjectDetectorReady;

@end

@implementation ObjectDetector

#pragma mark - Constructors

#pragma mark - Public

- (void)loadSVMFile:(NSString *)path handler:(ObjectDetectorLoadingHandler)handler
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (handler) {
            NSError *error = [self errorWithCode:ObjectDetectorErrorInvalidFilePath message:@"Unable to load SVM file"];
            handler(NO, error);
        }
        return;
    }
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        object_detector<image_scanner_type> det;
        deserialize(path.UTF8String) >> det;
        self.detector = det;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (handler) {
                self.isObjectDetectorReady = YES;
                handler(YES, nil);
            }
        });
    });
}

- (void)processImage:(CGImageRef)image detectionHandler:(ObjectDetectorProcessingHandler _Nonnull)detectionHandler
{
    if (self.processingImage) {
        NSError *error = [self errorWithCode:ObjectDetectorErrorAlreadyProcessingImage message:@"Already processing image."];
        if (detectionHandler) { detectionHandler(NO, error, nil); }
        return;
    }
    
    if (!self.isObjectDetectorReady) {
        NSError *error = [self errorWithCode:ObjectDetectorErrorObjectDetectorNotLoaded message:@"Already processing image."];
        if (detectionHandler) { detectionHandler(NO, error, nil); }
        return;
    }
    
    self.processingImage = YES;
    
    dispatch_queue_t queue = dispatch_queue_create("com.RedHand.queue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_async(queue, ^{
        
        /*
         * NOTE: The following code is not efficient.
         * A better way would be to convert the CGImageRef to a Open CV image and then convert that to the dlib image.
         * This would only involve pointer assigment and wouldn't actually copy the values of the data accross.
         */
        
        // get image info
        size_t width = CGImageGetWidth(image);
        size_t height = CGImageGetHeight(image);
        size_t bytesPerRow = CGImageGetBytesPerRow(image);
        size_t bytesPerPixel = bytesPerRow / width;
        
        // get image data
        CGDataProviderRef dataProvider = CGImageGetDataProvider(image);
        CFDataRef data = CGDataProviderCopyData(dataProvider);
        const unsigned char *rawData = CFDataGetBytePtr(data);
        
        // setup dlib rgb image
        array2d<rgb_pixel> dlibImg;
        dlibImg.set_size(width, height);
        
        // copy values into dlib image
        // this is probably the most efficient O(n) (or I guess O(n/bytesPerPixel)?)
        for (int i = 0; i < width * height; i += bytesPerPixel) {
            int row = (i / bytesPerPixel) / width;
            int column = (i / bytesPerPixel) - ((int)width * row);
            
            dlibImg[row][column] = rgb_pixel(rawData[i],
                                             rawData[i + 1],
                                             rawData[i + 2]);
        }
        
        // release quartz resources
        CFRelease(data);
        CGDataProviderRelease(dataProvider);
        
        // apply object detector
        pyramid_up(dlibImg);
        std::vector<dlib::rectangle> detectionBounds = self.detector(dlibImg);
        
        /*
         * Here is where shape / landmark detection can take place
         */
        
        // convert detections into objc
        NSMutableArray *detections = [[NSMutableArray alloc] initWithCapacity:detectionBounds.size()];
        for (int i = 0; i < detectionBounds.size(); i++) {
            Bounds b;
            b.x = detectionBounds[i].left();
            b.y = detectionBounds[i].top();
            b.width = detectionBounds[i].width();
            b.height = detectionBounds[i].height();
            [detections addObject:[Detection detectionWithPixelBounds:b]];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (detectionHandler) { detectionHandler(YES, nil, detections); }
        });
        
    });
}

#pragma mark - Private

- (NSError *)errorWithCode:(ObjectDetectorError)code message:(NSString *)message
{
    NSDictionary *info = message ? @{NSLocalizedDescriptionKey: message} : nil;
    return [NSError errorWithDomain:@"ObjectDetectorDomain" code:code userInfo:info];
}

@end





















