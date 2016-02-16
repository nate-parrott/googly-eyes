//  DetectFace.h
//  SantaFace
//
//  Created by Tadas Z on 11/30/12.
//  DevBridge

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@class DetectFace;
@protocol DetectFaceDelegate <NSObject>
- (void)detectedFaceController:(DetectFace *)controller features:(NSArray *)featuresArray forVideoBox:(CGRect)clap withPreviewBox:(CGRect)previewBox;
@end

@interface DetectFace : NSObject
@property (nonatomic, weak) id delegate;

@property (nonatomic, strong) UIView *previewView;

@property (nonatomic,readonly) AVCaptureDevicePosition position;

- (void)startDetectionWithCamera:(AVCaptureDevicePosition)position;
- (void)stopDetection;

+ (CGRect)convertFrame:(CGRect)originalFrame previewBox:(CGRect)previewBox forVideoBox:(CGRect)videoBox isMirrored:(BOOL)isMirrored;

@end
