//
//  ViewController.m
//  googly-eyes
//
//  Created by Nate Parrott on 2/15/16.
//  Copyright © 2016 Nate Parrott. All rights reserved.
//

#import "ViewController.h"
#import "DetectFace.h"
@import ReplayKit;

@interface Eye : UIView

@property (nonatomic) UIView *pupil;
@property (nonatomic) UICollisionBehavior *collision;
@property (nonatomic) UIDynamicAnimator *animator;
@property (nonatomic) UIGravityBehavior *gravity;
@property (nonatomic) UIDynamicItemBehavior *behavior;
@property (nonatomic) BOOL running;
@property (nonatomic) CADisplayLink *displayLink;
@property (nonatomic) CGPoint cumulativeTranslation;
@property (nonatomic) CGPoint lastTickVelocity;
@property (nonatomic) CGFloat scale;

@end

@implementation Eye

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(0, 0, 100, 100)];
    
    _scale = 1;
    
    UIView *bg = [[UIView alloc] initWithFrame:CGRectMake(-20, -20, 100 + 20*2, 100 + 20*2)];
    [self addSubview:bg];
    bg.backgroundColor = [UIColor whiteColor];
    bg.layer.cornerRadius = bg.frame.size.width/2;
    
    self.pupil = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 12)];
    // self.pupil.backgroundColor = [UIColor blackColor];
    self.pupil.center = CGPointMake(50, 50);
    self.pupil.layer.cornerRadius = 12/2.0;
    [self addSubview:self.pupil];
    
    UIView *v = [[UIView alloc] initWithFrame:self.pupil.bounds];
    [self.pupil addSubview:v];
    v.center = CGPointMake(self.pupil.bounds.size.width/2, self.pupil.bounds.size.height/2);
    v.backgroundColor = [UIColor blackColor];
    v.layer.cornerRadius = v.bounds.size.width / 2;
    v.transform = CGAffineTransformMakeScale(5, 5);
    
    // self.backgroundColor = [UIColor whiteColor];
    
    self.animator = [[UIDynamicAnimator alloc] initWithReferenceView:self];
    self.collision = [[UICollisionBehavior alloc] initWithItems:@[self.pupil]];
    // self.collision.translatesReferenceBoundsIntoBoundary = YES;
    [self.collision addBoundaryWithIdentifier:@"circle" forPath:[UIBezierPath bezierPathWithOvalInRect:self.bounds]];
    [self.animator addBehavior:self.collision];
    
    self.gravity = [[UIGravityBehavior alloc] initWithItems:@[self.pupil]];
    [self.animator addBehavior:self.gravity];
    
    self.behavior = [[UIDynamicItemBehavior alloc] initWithItems:@[self.pupil]];
    [self.animator addBehavior:self.behavior];
    self.behavior.friction = 0.3;
    self.behavior.elasticity = 0.06;
    self.behavior.resistance = 0.2;
    
    return self;
}

- (void)setScale:(CGFloat)scale {
    _scale = scale;
    self.transform = CGAffineTransformMakeScale(self.scale, self.scale);
}

- (void)smoothlyScale:(CGFloat)scale {
    CGFloat w = 0.3;
    self.scale = scale * w + self.scale * (1-w);
}

- (void)translateToCenter:(CGPoint)center {
    CGFloat w = 0.3;
    center = CGPointMake(center.x * w + self.center.x * (1-w), center.y * w + self.center.y * (1-w));
    self.cumulativeTranslation = CGPointMake(self.cumulativeTranslation.x + (center.x - self.center.x) / self.scale, self.cumulativeTranslation.y + (center.y - self.center.y) / self.scale);
    self.center = center;
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];
    self.running = newWindow != nil;
}

- (void)setRunning:(BOOL)running {
    if (running != _running) {
        _running = running;
        if (running) {
            self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
            [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        } else {
            [self.displayLink invalidate];
            self.displayLink = nil;
        }
    }
}

- (void)tick {
    CFTimeInterval dt = self.displayLink.duration;
    CGPoint velocity = CGPointMake(self.cumulativeTranslation.x / dt, self.cumulativeTranslation.y / dt);
    CGFloat w = 0.4;
    velocity = CGPointMake(velocity.x * w + self.lastTickVelocity.x * (1-w), velocity.y * w + self.lastTickVelocity.y * (1-w));
    CGPoint accel = CGPointMake((velocity.x - self.lastTickVelocity.x) / dt, (velocity.y - self.lastTickVelocity.y) / dt);
    // NSLog(@"accel: %f, %f", accel.x, accel.y);
    self.lastTickVelocity = velocity;
    self.cumulativeTranslation = CGPointZero;
    self.gravity.gravityDirection = CGVectorMake(-accel.x / 1000, 1 - accel.y / 1000);
}

@end



@interface ViewController () <DetectFaceDelegate, RPPreviewViewControllerDelegate, RPScreenRecorderDelegate> {
    CGPoint _centerAtStart;
    NSInteger _framesWithTooManyEyes;
}

// @property (nonatomic) Eye *eye1;
@property (nonatomic) DetectFace *detector;
@property (nonatomic) NSMutableArray *eyePairs;
@property (nonatomic) RPScreenRecorder *recorder;
@property (nonatomic) BOOL recording;
@property (nonatomic) AVCaptureDevicePosition curCamera;

@property (nonatomic) IBOutlet UIView *previewView;
@property (nonatomic) IBOutlet UIView *eyeView;
@property (nonatomic) IBOutlet UIButton *toggleCameraButton;
@property (nonatomic) IBOutlet UIButton *shutter;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.eyePairs = [NSMutableArray new];
    
    BOOL frontCamera = [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceFront];
    BOOL backCamera = [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceRear];
    self.toggleCameraButton.hidden = !(frontCamera && backCamera);
    self.curCamera = frontCamera ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
    
    [self screenRecorderDidChangeAvailability:[RPScreenRecorder sharedRecorder]];
    [[RPScreenRecorder sharedRecorder] setDelegate:self];
}

- (void)screenRecorderDidChangeAvailability:(RPScreenRecorder *)screenRecorder {
    self.shutter.hidden = ![[RPScreenRecorder sharedRecorder] isAvailable];
}

- (void)screenRecorder:(RPScreenRecorder *)screenRecorder didStopRecordingWithError:(NSError *)error previewViewController:(RPPreviewViewController *)previewViewController {
    self.recording = NO;
    self.view.userInteractionEnabled = YES;
    
    if (!error) {
        previewViewController.previewControllerDelegate = self;
        [self presentViewController:previewViewController animated:YES completion:nil];
    }
}

- (void)setCurCamera:(AVCaptureDevicePosition)curCamera {
    _curCamera = curCamera;
    
    [self.detector stopDetection];
    self.detector.delegate = nil;
    
    self.detector = [DetectFace new];
    self.detector.previewView = self.previewView;
    self.detector.delegate = self;
    [self.detector startDetectionWithCamera:self.curCamera];
}

- (IBAction)toggleCamera:(id)sender {
    self.curCamera = (self.curCamera == AVCaptureDevicePositionFront) ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
}

- (void)setRecording:(BOOL)recording {
    _recording = recording;
    [self.shutter setImage:[UIImage imageNamed:(recording ? @"Finish" : @"Record")] forState:UIControlStateNormal];
}

- (IBAction)toggleRecording:(id)sender {
    self.view.userInteractionEnabled = NO;
    if (!self.recording) {
        self.recording = YES;
        [[RPScreenRecorder sharedRecorder] startRecordingWithMicrophoneEnabled:YES handler:^(NSError * _Nullable error) {
            self.recording = (error == nil);
            self.view.userInteractionEnabled = YES;
        }];
    } else {
        self.recording = NO;
        [[RPScreenRecorder sharedRecorder] stopRecordingWithHandler:^(RPPreviewViewController * _Nullable previewViewController, NSError * _Nullable error) {
            [self screenRecorder:[RPScreenRecorder sharedRecorder] didStopRecordingWithError:error previewViewController:previewViewController];
            /*if (!error) {
                previewViewController.previewControllerDelegate = self;
                [self presentViewController:previewViewController animated:YES completion:nil];
            }
            self.view.userInteractionEnabled = YES;*/
        }];
    }
}

/*- (void)panned:(UIPanGestureRecognizer *)rec {
    if (rec.state == UIGestureRecognizerStateBegan) {
        _centerAtStart = self.eye1.center;
    } else if (rec.state == UIGestureRecognizerStateChanged) {
        CGPoint center = CGPointMake(_centerAtStart.x + [rec translationInView:self.view].x, _centerAtStart.y + [rec translationInView:self.view].y);
        [self.eye1 translateToCenter:center];
    }
}*/

- (void)detectedFaceController:(DetectFace *)controller features:(NSArray *)featuresArray forVideoBox:(CGRect)clap withPreviewBox:(CGRect)previewBox {
    if (self.eyePairs.count > featuresArray.count) {
        _framesWithTooManyEyes++;
    } else {
        _framesWithTooManyEyes = 0;
    }
    if (_framesWithTooManyEyes > 8 && self.eyePairs.lastObject) {
        for (Eye *eye in self.eyePairs.lastObject) {
            [eye removeFromSuperview];
        }
        [self.eyePairs removeLastObject];
        _framesWithTooManyEyes = 0;
    }
    NSInteger i = 0;
    for (CIFaceFeature *ff in featuresArray) {
        // find the correct position for the square layer within the previewLayer
        // the feature box originates in the bottom left of the video frame.
        // (Bottom right if mirroring is turned on)
        // CGRect faceRect = [ff bounds];
        
        //isMirrored because we are using front camera
        // faceRect = [DetectFace convertFrame:faceRect previewBox:previewBox forVideoBox:clap isMirrored:YES];
        // CGFloat eyeSize = (faceRect.size.width + faceRect.size.height)/2 * 0.1;
        
        BOOL mirrored = self.curCamera == AVCaptureDevicePositionFront;
        
        CGRect leftEye = CGRectMake(ff.leftEyePosition.x - ff.bounds.size.width * 0.05, ff.leftEyePosition.y - ff.bounds.size.height * 0.05, ff.bounds.size.width * 0.1, ff.bounds.size.height * 0.1);
        leftEye = [DetectFace convertFrame:leftEye previewBox:previewBox forVideoBox:clap isMirrored:mirrored];
        CGRect rightEye = CGRectMake(ff.rightEyePosition.x - ff.bounds.size.width * 0.05, ff.rightEyePosition.y - ff.bounds.size.height * 0.05, ff.bounds.size.width * 0.1, ff.bounds.size.height * 0.1);
        rightEye = [DetectFace convertFrame:rightEye previewBox:previewBox forVideoBox:clap isMirrored:mirrored];
        
        CGFloat nativeEyeRadius = sqrt(pow(140, 2) * 2)/2;
        CGFloat s = 3;
        CGFloat leftEyeRadius = sqrt(pow(leftEye.size.width, 2) + pow(leftEye.size.height, 2)) / 2 * s;
        CGFloat rightEyeRadius = sqrt(pow(rightEye.size.width, 2) + pow(rightEye.size.height, 2)) / 2 * s;
        
        CGPoint left = CGPointMake(CGRectGetMidX(leftEye), CGRectGetMidY(leftEye));
        CGPoint right = CGPointMake(CGRectGetMidX(rightEye), CGRectGetMidY(rightEye));
        
        BOOL added = i >= self.eyePairs.count;
        if (added) {
            Eye *eye1 = [Eye new];
            eye1.center = left;
            eye1.scale = leftEyeRadius / nativeEyeRadius;
            [self.eyeView addSubview:eye1];
            Eye *eye2 = [Eye new];
            eye2.center = right;
            eye2.scale = rightEyeRadius / nativeEyeRadius;
            [self.eyeView addSubview:eye2];
            [self.eyePairs addObject:@[eye1, eye2]];
        }
        NSArray *pair = nil;
        if (i < self.eyePairs.count) {
            pair = self.eyePairs[i];
            [pair[0] translateToCenter:left];
            [pair[0] smoothlyScale:leftEyeRadius / nativeEyeRadius];
            [pair[1] translateToCenter:right];
            [pair[1] smoothlyScale:rightEyeRadius / nativeEyeRadius];
        }
        
        i++;
    }
}

- (void)previewControllerDidFinish:(RPPreviewViewController *)previewController {
    [previewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)previewController:(RPPreviewViewController *)previewController didFinishWithActivityTypes:(NSSet <NSString *> *)activityTypes {
    [previewController dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

@end
