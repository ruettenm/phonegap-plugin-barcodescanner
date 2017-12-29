/*
 * PhoneGap is available under *either* the terms of the modified BSD license *or* the
 * MIT License (2008). See http://opensource.org/licenses/alphabetical for full text.
 *
 * Copyright 2011 Matt Kane. All rights reserved.
 * Copyright (c) 2011, IBM Corporation
 */

#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>

//------------------------------------------------------------------------------
// use the all-in-one version of zxing that we built
//------------------------------------------------------------------------------
#import "zxing-all-in-one.h"
#import <Cordova/CDVPlugin.h>


//------------------------------------------------------------------------------
// Delegate to handle orientation functions
//------------------------------------------------------------------------------
@protocol CDVBarcodeScannerOrientationDelegate <NSObject>
- (NSUInteger)supportedInterfaceOrientations;
- (BOOL)shouldAutorotate;
@end

//------------------------------------------------------------------------------
@class CDVbcsProcessor;
@class CDVbcsViewController;

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@interface CDVBarcodeScanner : CDVPlugin {}
- (NSString*)isScanNotPossible;
- (void)scan:(CDVInvokedUrlCommand*)command;
- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled callback:(NSString*)callback;
- (void)returnError:(NSString*)message callback:(NSString*)callback;
@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@interface CDVbcsProcessor : NSObject <AVCaptureMetadataOutputObjectsDelegate> {}
@property (nonatomic, retain) CDVBarcodeScanner*          plugin;
@property (nonatomic, retain) NSString*                   callback;
@property (nonatomic, retain) UIViewController*           parentViewController;
@property (nonatomic, retain) CDVbcsViewController*       viewController;
@property (nonatomic, retain) AVCaptureSession*           captureSession;
@property (nonatomic, retain) AVCaptureVideoPreviewLayer* previewLayer;
@property (nonatomic, retain) NSMutableArray*             results;
@property (nonatomic, retain) NSString*                   formats;
@property (nonatomic)         BOOL                        capturing;
@property (nonatomic)         BOOL                        isTransitionAnimated;
@property (nonatomic, retain) NSString*                   upperViewlabel;
@property (nonatomic, retain) NSString*                   lowerViewlabel;
@property (nonatomic, retain) NSString*                   cancelButtonlabel;

- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback parentViewController:(UIViewController*)parentViewController;
- (void)scanBarcode;
- (void)barcodeScanSucceeded:(NSString*)text format:(NSString*)format;
- (void)barcodeScanFailed:(NSString*)message;
- (void)barcodeScanCancelled;
- (void)openDialog;
- (NSString*)setUpCaptureSession;
- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection;
- (NSString*)formatStringFrom:(zxing::BarcodeFormat)format;
- (UIImage*)getImageFromSample:(CMSampleBufferRef)sampleBuffer;
@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@interface CDVbcsViewController : UIViewController <CDVBarcodeScannerOrientationDelegate> {}
@property (nonatomic, retain) CDVbcsProcessor*          processor;
@property (nonatomic, retain) IBOutlet UIView*          overlayView;

- (id)initWithProcessor:(CDVbcsProcessor*)processor;
- (void)startCapturing;
- (UIView*)buildOverlayView;
- (UIImage*)buildReticleImageWithWidth;
- (void)shutterButtonPressed;
- (IBAction)cancelButtonPressed:(id)sender;
@end

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@implementation CDVBarcodeScanner

//--------------------------------------------------------------------------
- (NSString*)isScanNotPossible {
    NSString* result = nil;

    Class aClass = NSClassFromString(@"AVCaptureSession");
    if (aClass == nil) {
        return @"AVFoundation Framework not available";
    }

    return result;
}

- (BOOL)notHasPermission {
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    return (authStatus == AVAuthorizationStatusDenied || authStatus == AVAuthorizationStatusRestricted);
}

//--------------------------------------------------------------------------
- (void)scan:(CDVInvokedUrlCommand*)command {
    CDVbcsProcessor*    processor;
    NSString*           callback;
    NSString*           capabilityError;

    callback = command.callbackId;

    NSDictionary* options;
    if (command.arguments.count == 0) {
        options = [NSDictionary dictionary];
    } else {
        options = command.arguments[0];
    }

    BOOL disableAnimations = [options[@"disableAnimations"] boolValue];

    NSString *upperViewlabel = options[@"upperViewlabel"];
    NSString *lowerViewlabel = options[@"lowerViewlabel"];
    NSString *cancelButtonlabel = options[@"cancelButtonlabel"];

    capabilityError = [self isScanNotPossible];
    if (capabilityError) {
        [self returnError:capabilityError callback:callback];
        return;
    } else if ([self notHasPermission]) {
        NSString * error = NSLocalizedString(@"Access to the camera has been prohibited; please enable it in the Settings app to continue.",nil);
        [self returnError:error callback:callback];
        return;
    }

    processor = [[[CDVbcsProcessor alloc] initWithPlugin:self callback:callback parentViewController:self.viewController] autorelease];

    if (upperViewlabel) {
        processor.upperViewlabel = upperViewlabel;
    }
    if (lowerViewlabel) {
        processor.lowerViewlabel = lowerViewlabel;
    }
    if (cancelButtonlabel) {
        processor.cancelButtonlabel = cancelButtonlabel;
    }

    processor.isTransitionAnimated = !disableAnimations;

    processor.formats = options[@"formats"];

    [processor performSelector:@selector(scanBarcode) withObject:nil afterDelay:0];
}

//--------------------------------------------------------------------------
- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled callback:(NSString*)callback {
    NSMutableDictionary* resultDict = [[NSMutableDictionary new] autorelease];
    resultDict[@"text"] = scannedText;
    resultDict[@"format"] = format;
    resultDict[@"cancelled"] = @(cancelled ? 1 : 0);

    CDVPluginResult* result = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsDictionary: resultDict];
    [self.commandDelegate sendPluginResult:result callbackId:callback];
}

//--------------------------------------------------------------------------
- (void)returnError:(NSString*)message callback:(NSString*)callback {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus: CDVCommandStatus_ERROR messageAsString: message];
    [self.commandDelegate sendPluginResult:result callbackId:callback];
}
@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@implementation CDVbcsProcessor

@synthesize plugin               = _plugin;
@synthesize callback             = _callback;
@synthesize parentViewController = _parentViewController;
@synthesize viewController       = _viewController;
@synthesize captureSession       = _captureSession;
@synthesize previewLayer         = _previewLayer;
@synthesize capturing            = _capturing;
@synthesize results              = _results;

//--------------------------------------------------------------------------
- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback parentViewController:(UIViewController*)parentViewController {
    self = [super init];
    if (!self) return self;

    self.plugin                 = plugin;
    self.callback               = callback;
    self.parentViewController   = parentViewController;

    self.capturing = NO;
    self.results = [[NSMutableArray new] autorelease];

    self.upperViewlabel = @"Center barcode on your card between the corners";
    self.lowerViewlabel = @"Barcode will scan automatically.\nTry to avoid shadows and glare.";
    self.cancelButtonlabel = @"Cancel";

    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.plugin = nil;
    self.callback = nil;
    self.parentViewController = nil;
    self.viewController = nil;
    self.captureSession = nil;
    self.previewLayer = nil;
    self.results = nil;

    self.capturing = NO;

    [super dealloc];
}

//--------------------------------------------------------------------------
- (void)scanBarcode {
    NSString* errorMessage = [self setUpCaptureSession];
    if (errorMessage) {
        [self barcodeScanFailed:errorMessage];
        return;
    }

    self.viewController = [[[CDVbcsViewController alloc] initWithProcessor: self] autorelease];

    // delayed [self openDialog];
    [self performSelector:@selector(openDialog) withObject:nil afterDelay:1];
}

//--------------------------------------------------------------------------
- (void)openDialog {
    [self.parentViewController presentViewController:self.viewController animated:self.isTransitionAnimated completion:nil];
}

//--------------------------------------------------------------------------
- (void)barcodeScanDone:(void (^)(void))callbackBlock {
    self.capturing = NO;
    [self.captureSession stopRunning];
    [self.parentViewController dismissViewControllerAnimated:self.isTransitionAnimated completion:callbackBlock];

    // viewcontroller holding onto a reference to us, release them so they will release us
    self.viewController = nil;
}

//--------------------------------------------------------------------------
- (BOOL)checkResult:(NSString *)result {
    [self.results addObject:result];

    NSInteger treshold = 7;

    if (self.results.count > treshold) {
        [self.results removeObjectAtIndex:0];
    }

    if (self.results.count < treshold)
    {
        return NO;
    }

    BOOL allEqual = YES;
    NSString *compareString = self.results[0];

    for (NSString *aResult in self.results)
    {
        if (![compareString isEqualToString:aResult])
        {
            allEqual = NO;
            break;
        }
    }

    return allEqual;
}

//--------------------------------------------------------------------------
- (void)barcodeScanSucceeded:(NSString*)text format:(NSString*)format {
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self barcodeScanDone:^{
            [self.plugin returnSuccess:text format:format cancelled:FALSE callback:self.callback];
        }];
    });
}

//--------------------------------------------------------------------------
- (void)barcodeScanFailed:(NSString*)message {
    [self barcodeScanDone:^{
        [self.plugin returnError:message callback:self.callback];
    }];
}

//--------------------------------------------------------------------------
- (void)barcodeScanCancelled {
    [self barcodeScanDone:^{
        [self.plugin returnSuccess:@"" format:@"" cancelled:TRUE callback:self.callback];
    }];
}

//--------------------------------------------------------------------------
- (NSString*)setUpCaptureSession {
    NSError* error = nil;

    AVCaptureSession* captureSession = [[[AVCaptureSession alloc] init] autorelease];
    self.captureSession = captureSession;

    AVCaptureDevice* __block device = nil;

    device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!device) return @"unable to obtain video capture device";

    // set focus params if available to improve focusing
    [device lockForConfiguration:&error];
    if (error == nil) {
        if([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
            [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
        }
        if([device isAutoFocusRangeRestrictionSupported]) {
            [device setAutoFocusRangeRestriction:AVCaptureAutoFocusRangeRestrictionNear];
        }
    }
    [device unlockForConfiguration];

    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) return @"unable to obtain video capture device input";

    AVCaptureMetadataOutput* output = [[[AVCaptureMetadataOutput alloc] init] autorelease];
    if (!output) return @"unable to obtain video capture output";

    [output setMetadataObjectsDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)];

    if ([captureSession canSetSessionPreset:AVCaptureSessionPresetHigh]) {
        captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    } else if ([captureSession canSetSessionPreset:AVCaptureSessionPresetMedium]) {
        captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    } else {
        return @"unable to preset high nor medium quality video capture";
    }

    if ([captureSession canAddInput:input]) {
        [captureSession addInput:input];
    }
    else {
        return @"unable to add video capture device input to session";
    }

    if ([captureSession canAddOutput:output]) {
        [captureSession addOutput:output];
    }
    else {
        return @"unable to add video capture output to session";
    }

    [output setMetadataObjectTypes:@[AVMetadataObjectTypeQRCode,
                                     AVMetadataObjectTypeAztecCode,
                                     AVMetadataObjectTypeDataMatrixCode,
                                     AVMetadataObjectTypeUPCECode,
                                     AVMetadataObjectTypeEAN8Code,
                                     AVMetadataObjectTypeEAN13Code,
                                     AVMetadataObjectTypeCode128Code,
                                     AVMetadataObjectTypeCode93Code,
                                     AVMetadataObjectTypeCode39Code,
                                     AVMetadataObjectTypeITF14Code,
                                     AVMetadataObjectTypePDF417Code,
                                     AVMetadataObjectTypeInterleaved2of5Code
                                     ]];

    // setup capture preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    // run on next event loop pass [captureSession startRunning]
    [captureSession performSelector:@selector(startRunning) withObject:nil afterDelay:0];

    return nil;
}

//--------------------------------------------------------------------------
// this method gets sent the captured frames
//--------------------------------------------------------------------------
- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection*)connection {

    if (!self.capturing) return;

    try {
        // This will bring in multiple entities if there are multiple 2D codes in frame.
        for (AVMetadataObject *metaData in metadataObjects) {
            AVMetadataMachineReadableCodeObject* code = (AVMetadataMachineReadableCodeObject*)[self.previewLayer transformedMetadataObjectForMetadataObject:(AVMetadataMachineReadableCodeObject*)metaData];

            if ([self checkResult:code.stringValue]) {
                [self barcodeScanSucceeded:code.stringValue format:[self formatStringFromMetadata:code]];
            }
        }
    }
    catch (...) {
        //            NSLog(@"decoding: unknown exception");
        //            [self barcodeScanFailed:@"unknown exception decoding barcode"];
    }

    //        NSTimeInterval timeElapsed  = [NSDate timeIntervalSinceReferenceDate] - timeStart;
    //        NSLog(@"decoding completed in %dms", (int) (timeElapsed * 1000));

}

//--------------------------------------------------------------------------
// convert barcode format to string
//--------------------------------------------------------------------------
- (NSString*)formatStringFrom:(zxing::BarcodeFormat)format {
    if (format == zxing::BarcodeFormat_QR_CODE)      return @"QR_CODE";
    if (format == zxing::BarcodeFormat_DATA_MATRIX)  return @"DATA_MATRIX";
    if (format == zxing::BarcodeFormat_UPC_E)        return @"UPC_E";
    if (format == zxing::BarcodeFormat_UPC_A)        return @"UPC_A";
    if (format == zxing::BarcodeFormat_EAN_8)        return @"EAN_8";
    if (format == zxing::BarcodeFormat_EAN_13)       return @"EAN_13";
    if (format == zxing::BarcodeFormat_CODE_128)     return @"CODE_128";
    if (format == zxing::BarcodeFormat_CODE_39)      return @"CODE_39";
    if (format == zxing::BarcodeFormat_ITF)          return @"ITF";
    return @"???";
}

//--------------------------------------------------------------------------
// convert metadata object information to barcode format string
//--------------------------------------------------------------------------
- (NSString*)formatStringFromMetadata:(AVMetadataMachineReadableCodeObject*)format {
    if (format.type == AVMetadataObjectTypeQRCode)          return @"QR_CODE";
    if (format.type == AVMetadataObjectTypeAztecCode)       return @"AZTEC";
    if (format.type == AVMetadataObjectTypeDataMatrixCode)  return @"DATA_MATRIX";
    if (format.type == AVMetadataObjectTypeUPCECode)        return @"UPC_E";
    // According to Apple documentation, UPC_A is EAN13 with a leading 0.
    if (format.type == AVMetadataObjectTypeEAN13Code && [format.stringValue characterAtIndex:0] == '0') return @"UPC_A";
    if (format.type == AVMetadataObjectTypeEAN8Code)        return @"EAN_8";
    if (format.type == AVMetadataObjectTypeEAN13Code)       return @"EAN_13";
    if (format.type == AVMetadataObjectTypeCode128Code)     return @"CODE_128";
    if (format.type == AVMetadataObjectTypeCode93Code)      return @"CODE_93";
    if (format.type == AVMetadataObjectTypeCode39Code)      return @"CODE_39";
    if (format.type == AVMetadataObjectTypeITF14Code || format.type == AVMetadataObjectTypeInterleaved2of5Code) return @"ITF";
    if (format.type == AVMetadataObjectTypePDF417Code)      return @"PDF_417";
    return @"???";
}
@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@implementation CDVbcsViewController
@synthesize processor      = _processor;
@synthesize overlayView    = _overlayView;

//--------------------------------------------------------------------------
- (id)initWithProcessor:(CDVbcsProcessor*)processor {
    self = [super init];
    if (!self) return self;

    self.processor = processor;
    self.overlayView = nil;
    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.view = nil;
    self.processor = nil;
    self.overlayView = nil;
    [super dealloc];
}

//--------------------------------------------------------------------------
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame: self.processor.parentViewController.view.frame];

    // setup capture preview layer
    AVCaptureVideoPreviewLayer* previewLayer = self.processor.previewLayer;
    previewLayer.frame = self.view.bounds;
    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    if ([previewLayer.connection isVideoOrientationSupported]) {
        [previewLayer.connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    }

    [self.view.layer insertSublayer:previewLayer below:[[self.view.layer sublayers] objectAtIndex:0]];

    [self.view addSubview:[self buildOverlayView]];
}

//--------------------------------------------------------------------------
- (void)viewWillAppear:(BOOL)animated {
    // set video orientation to what the camera sees
    self.processor.previewLayer.connection.videoOrientation = (AVCaptureVideoOrientation) [[UIApplication sharedApplication] statusBarOrientation];
}

//--------------------------------------------------------------------------
- (void)viewDidAppear:(BOOL)animated {
    [self startCapturing];

    [super viewDidAppear:animated];
}

//--------------------------------------------------------------------------
- (void)startCapturing {
    self.processor.capturing = YES;
}

//--------------------------------------------------------------------------
- (IBAction)cancelButtonPressed:(id)sender {
    [self.processor performSelector:@selector(barcodeScanCancelled) withObject:nil afterDelay:0];
}

//--------------------------------------------------------------------------
- (UIView*)buildOverlayView {
    CGRect bounds = self.view.bounds;
    bounds = CGRectMake(0, 0, bounds.size.width, bounds.size.height);

    UIView* overlayView = [[UIView alloc] initWithFrame:bounds];
    overlayView.autoresizesSubviews = YES;
    overlayView.autoresizingMask    = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlayView.opaque              = NO;

    bounds = overlayView.bounds;

    CGFloat rootViewHeight  = CGRectGetHeight(bounds);
    CGFloat rootViewWidth   = CGRectGetWidth(bounds);
    CGFloat rectHeight      = rootViewHeight/4;

    // barcode scanner area
    UIImage* reticleImage   = [self buildReticleImageWithWidth: rootViewWidth andHeight: rectHeight * 2];
    UIView*  reticleView    = [[[UIImageView alloc] initWithImage:reticleImage] autorelease];
    CGRect   rectArea       = CGRectMake(0, rectHeight, rootViewWidth, rectHeight*2);
    [reticleView setFrame:rectArea];

    // custom scanner ui
    CGRect upperViewRect = CGRectMake(0, 0, rootViewWidth, rectHeight);
    CGRect lowerViewRect = CGRectMake(0, rootViewHeight - rectHeight, rootViewWidth, rectHeight);

    CGFloat labelPadding = 50;
    CGFloat labelWidth = rootViewWidth - labelPadding;
    UIView* upperView = [[UIView alloc] initWithFrame:upperViewRect];
    upperView.backgroundColor = UIColor.blackColor;
    upperView.alpha = 0.70;
    UILabel* upperViewlabel = [[UILabel alloc] initWithFrame:CGRectMake(labelPadding/2, 0, labelWidth, upperView.bounds.size.height)];
    upperViewlabel.text = _processor.upperViewlabel;
    upperViewlabel.font = [UIFont systemFontOfSize: 22];
    upperViewlabel.textColor = UIColor.whiteColor;
    upperViewlabel.textAlignment = NSTextAlignmentCenter;
    upperViewlabel.numberOfLines = 2;
    [upperView addSubview: upperViewlabel];

    UIView* lowerView = [[UIView alloc] initWithFrame:lowerViewRect];
    lowerView.backgroundColor = UIColor.blackColor;
    lowerView.alpha = 0.70;
    UILabel* lowerViewlabel = [[UILabel alloc] initWithFrame:CGRectMake(labelPadding/2, 0, labelWidth, lowerView.bounds.size.height / 2)];
    lowerViewlabel.text = _processor.lowerViewlabel;
    lowerViewlabel.textColor = UIColor.whiteColor;
    lowerViewlabel.textAlignment = NSTextAlignmentCenter;
    lowerViewlabel.numberOfLines = 2;
    [lowerView addSubview: lowerViewlabel];

    UIView* lowerButtonView = [[UIView alloc] initWithFrame:lowerViewRect];
    UILabel* cancelButtonLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelPadding / 2, rectHeight / 2, labelWidth, 50)];
    cancelButtonLabel.backgroundColor = UIColor.whiteColor;
    cancelButtonLabel.text = _processor.cancelButtonlabel;
    cancelButtonLabel.textAlignment = NSTextAlignmentCenter;
    cancelButtonLabel.userInteractionEnabled = YES;
    cancelButtonLabel.layer.cornerRadius = 6;
    cancelButtonLabel.clipsToBounds = YES;
    UITapGestureRecognizer *tapGesture =
    [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cancelButtonPressed:)];
    [cancelButtonLabel addGestureRecognizer:tapGesture];
    [lowerButtonView addSubview:cancelButtonLabel];

    [overlayView addSubview: upperView];
    [overlayView addSubview: lowerView];
    [overlayView addSubview: lowerButtonView];
    [overlayView addSubview: reticleView];

    return overlayView;
}

#define LINE_SIZE           40.0f
#define LINE_STROKE_WIDTH   2.0f
#define PADDING_RIGHT_LEFT  50.0f
#define PADDING_TOP_BOTTOM  PADDING_RIGHT_LEFT * 2
#define ALPHA               1.0f
//-------------------------------------------------------------------------
// builds yellow box
//-------------------------------------------------------------------------
- (UIImage*)buildReticleImageWithWidth: (CGFloat)width andHeight: (CGFloat) height {
    UIImage* result;
    UIGraphicsBeginImageContext(CGSizeMake(width, height));
    CGContextRef context = UIGraphicsGetCurrentContext();

    UIColor* color = [UIColor colorWithRed:0.99 green:0.89 blue:0.00 alpha:ALPHA];
    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetLineWidth(context, LINE_STROKE_WIDTH);
    CGContextBeginPath(context);

    // top left
    CGContextMoveToPoint(context, PADDING_RIGHT_LEFT, PADDING_TOP_BOTTOM);
    CGContextAddLineToPoint(context, PADDING_RIGHT_LEFT, PADDING_TOP_BOTTOM + LINE_SIZE);

    CGContextMoveToPoint(context, PADDING_RIGHT_LEFT, PADDING_TOP_BOTTOM);
    CGContextAddLineToPoint(context, PADDING_RIGHT_LEFT + LINE_SIZE, PADDING_TOP_BOTTOM);

    // top right
    CGContextMoveToPoint(context, width - PADDING_RIGHT_LEFT, PADDING_TOP_BOTTOM);
    CGContextAddLineToPoint(context, width - PADDING_RIGHT_LEFT, PADDING_TOP_BOTTOM + LINE_SIZE);

    CGContextMoveToPoint(context, width - PADDING_RIGHT_LEFT, PADDING_TOP_BOTTOM);
    CGContextAddLineToPoint(context, width - PADDING_RIGHT_LEFT - LINE_SIZE, PADDING_TOP_BOTTOM);

    // bottom right
    CGContextMoveToPoint(context, width - PADDING_RIGHT_LEFT, height - PADDING_TOP_BOTTOM);
    CGContextAddLineToPoint(context, width - PADDING_RIGHT_LEFT, height - PADDING_TOP_BOTTOM - LINE_SIZE);

    CGContextMoveToPoint(context, width - PADDING_RIGHT_LEFT, height - PADDING_TOP_BOTTOM);
    CGContextAddLineToPoint(context, width - PADDING_RIGHT_LEFT - LINE_SIZE, height - PADDING_TOP_BOTTOM);

    // bottom left
    CGContextMoveToPoint(context, PADDING_RIGHT_LEFT, height - PADDING_TOP_BOTTOM);
    CGContextAddLineToPoint(context, PADDING_RIGHT_LEFT, height - PADDING_TOP_BOTTOM - LINE_SIZE);

    CGContextMoveToPoint(context, PADDING_RIGHT_LEFT, height - PADDING_TOP_BOTTOM);
    CGContextAddLineToPoint(context, PADDING_RIGHT_LEFT + LINE_SIZE, height - PADDING_TOP_BOTTOM);

    CGContextStrokePath(context);

    result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return result;
}

#pragma mark CDVBarcodeScannerOrientationDelegate
- (BOOL)shouldAutorotate
{
    return NO;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

@end

