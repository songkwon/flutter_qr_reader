//
//  ReReaderViewController.m
//  flutter_qr_reader
//
//  Created by 王贺天 on 2019/6/7.
//

#import "QrReaderViewController.h"

@interface QrReaderViewController()<AVCaptureMetadataOutputObjectsDelegate,UIGestureRecognizerDelegate>
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *videoPreviewLayer;
@property (nonatomic, assign) BOOL hasAutoVideoZoom;
@property (nonatomic, assign) CGPoint centerPoint;
@property (nonatomic, strong) AVCaptureStillImageOutput *stillImageOutput;
@property (strong, nonatomic) AVCaptureDeviceInput * input;
@property (nonatomic, assign) CGFloat effectiveScale;
@property (nonatomic, assign) CGFloat beginGestureScale;
@end

@implementation QrReaderViewController{
    UIView* _qrcodeview;
    int64_t _viewId;
    FlutterMethodChannel* _channel;
    NSObject<FlutterPluginRegistrar>* _registrar;
    NSNumber *height;
    NSNumber *width;
    BOOL isOpenFlash;
    BOOL _isReading;
    AVCaptureDevice *captureDevice;
}

- (instancetype)initWithFrame:(CGRect)frame
               viewIdentifier:(int64_t)viewId
                    arguments:(id _Nullable)args
              binaryRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar
{
    if ([super init]) {
        _registrar = registrar;
        _viewId = viewId;
        NSString *channelName = [NSString stringWithFormat:@"me.hetian.flutter_qr_reader.reader_view_%lld", viewId];
        _channel = [FlutterMethodChannel methodChannelWithName:channelName binaryMessenger:registrar.messenger];
        __weak __typeof__(self) weakSelf = self;
        [_channel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
            [weakSelf onMethodCall:call result:result];
        }];
        width = args[@"width"];
        height = args[@"height"];
        NSLog(@"%@,%@", width, height);
        _qrcodeview= [[UIView alloc] initWithFrame:CGRectMake(0, 0, width.floatValue, height.floatValue) ];
        _qrcodeview.opaque = NO;
        _qrcodeview.backgroundColor = [UIColor blackColor];
        isOpenFlash = NO;
        _isReading = NO;
    }
    return self;
}

- (void)onMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result
{
    if ([call.method isEqualToString:@"flashlight"]) {
        [self setFlashlight];
        result(isOpenFlash?@(YES):@(NO));
    }else if ([call.method isEqualToString:@"startCamera"]) {
        [self startReading];
    } else if ([call.method isEqualToString:@"stopCamera"]) {
        [self stopReading];
    }
}

- (nonnull UIView *)view {
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchDetected:)];
    pinch.delegate = self;
    [_qrcodeview addGestureRecognizer:pinch];
    return _qrcodeview;
}

- (BOOL)startReading {
    if (_isReading) return NO;
    _isReading = YES;
    NSError *error;
    _captureSession = [[AVCaptureSession alloc] init];
    captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    [captureDevice lockForConfiguration:nil];
    [captureDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
    [captureDevice unlockForConfiguration];
    self.input = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&error];
    if (!self.input) {
        NSLog(@"%@", [error localizedDescription]);
        return NO;
    }
    [_captureSession addInput:self.input];
    AVCaptureMetadataOutput *captureMetadataOutput = [[AVCaptureMetadataOutput alloc] init];
    [_captureSession addOutput:captureMetadataOutput];
    dispatch_queue_t dispatchQueue;
    dispatchQueue = dispatch_queue_create("myQueue", NULL);
    [captureMetadataOutput setMetadataObjectsDelegate:self queue:dispatchQueue];
    NSMutableArray *medadataObjectTypes = [NSMutableArray arrayWithObjects:AVMetadataObjectTypeQRCode, nil];
    captureMetadataOutput.metadataObjectTypes = medadataObjectTypes;
    _videoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_captureSession];
    [_videoPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    [_videoPreviewLayer setFrame:_qrcodeview.layer.bounds];
    [_qrcodeview.layer addSublayer:_videoPreviewLayer];
    
    self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    NSDictionary *outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys:AVVideoCodecJPEG, AVVideoCodecKey,nil];
    [self.stillImageOutput setOutputSettings:outputSettings]; if ([_captureSession canAddOutput:self.stillImageOutput]){
        [_captureSession addOutput:self.stillImageOutput];
    }
    
    [_captureSession startRunning];
    _hasAutoVideoZoom = NO;
    return YES;
}


-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection{
    if (metadataObjects != nil && [metadataObjects count] > 0) {
        AVMetadataMachineReadableCodeObject *metadataObj = [metadataObjects objectAtIndex:0];
        if ([[metadataObj type] isEqualToString:AVMetadataObjectTypeQRCode]) {
            NSMutableDictionary *dic = [[NSMutableDictionary alloc] init];
            [dic setObject:[metadataObj stringValue] forKey:@"text"];
            [_channel invokeMethod:@"onQRCodeRead" arguments:dic];
            [self performSelectorOnMainThread:@selector(stopReading) withObject:nil waitUntilDone:NO];
            _isReading = NO;
        }
    }
    if (!_hasAutoVideoZoom) {
        AVMetadataMachineReadableCodeObject *obj = (AVMetadataMachineReadableCodeObject *)[self.videoPreviewLayer transformedMetadataObjectForMetadataObject:metadataObjects.lastObject];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self changeVideoScale:obj];
        });
        _hasAutoVideoZoom  =YES;
        return;
    }
}


-(void)stopReading{
    [_captureSession stopRunning];
    _captureSession = nil;
    [_videoPreviewLayer removeFromSuperlayer];
    _isReading = NO;
}

// 手电筒开关
- (void) setFlashlight
{
    [captureDevice lockForConfiguration:nil];
    if (isOpenFlash == NO) {
        [captureDevice setTorchMode:AVCaptureTorchModeOn];
        isOpenFlash = YES;
    } else {
        [captureDevice setTorchMode:AVCaptureTorchModeOff];
        isOpenFlash = NO;
    }
    
    [captureDevice unlockForConfiguration];
}

#pragma mark - 二维码自动拉近

- (void)changeVideoScale:(AVMetadataMachineReadableCodeObject *)objc
{
    NSArray *array = objc.corners;
    NSLog(@"cornersArray = %@",array);
    CGPoint point = CGPointZero;
    // 把字典转换为点，存在point里，成功返回true 其他false
    CGPointMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)array[0], &point);
    
    NSLog(@"X:%f -- Y:%f",point.x,point.y);
    CGPoint point2 = CGPointZero;
    CGPointMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)array[2], &point2);
    NSLog(@"X:%f -- Y:%f",point2.x,point2.y);
    
    self.centerPoint = CGPointMake((point.x + point2.x) / 2, (point.y + point2.y) / 2);
    CGFloat scace = 150 / (point2.x - point.x); //当二维码图片宽小于150，进行放大
    [self setVideoScale:scace];
    return;
}

- (void)setVideoScale:(CGFloat)scale
{
    [self.input.device lockForConfiguration:nil];
    AVCaptureConnection *videoConnection = [self connectionWithMediaType:AVMediaTypeVideo fromConnections:[[self stillImageOutput] connections]];
    CGFloat maxScaleAndCropFactor = ([[self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo] videoMaxScaleAndCropFactor])/16;
    
    if (scale > maxScaleAndCropFactor){
        scale = maxScaleAndCropFactor;
    }else if (scale < 1){
        scale = 1;
    }
    
    CGFloat zoom = scale / videoConnection.videoScaleAndCropFactor;
    videoConnection.videoScaleAndCropFactor = scale;
    [self.input.device unlockForConfiguration];
    
    CGAffineTransform transform = _qrcodeview.transform;
    
    //自动拉近放大
    if (scale == 1) {
        _qrcodeview.transform = CGAffineTransformScale(transform, zoom, zoom);
        CGRect rect = _qrcodeview.frame;
        rect.origin = CGPointZero;
        _qrcodeview.frame = rect;
    } else {
        [CATransaction begin];
        [CATransaction setAnimationDuration:.025];
        _qrcodeview.transform = CGAffineTransformScale(transform, zoom, zoom);
        [CATransaction commit];
    }
    
    NSLog(@"放大%f",zoom);
}

#pragma mark 手势拉近/远 界面
- (void)pinchDetected:(UIPinchGestureRecognizer*)recognizer
{
    self.effectiveScale = self.beginGestureScale * recognizer.scale;
    if (self.effectiveScale < 1.0){
        self.effectiveScale = 1.0;
    }
    [self setVideoScale:self.effectiveScale];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if ( [gestureRecognizer isKindOfClass:[UIPinchGestureRecognizer class]] ) {
        _beginGestureScale = _effectiveScale;
    }
    return YES;
}

- (AVCaptureConnection *)connectionWithMediaType:(NSString *)mediaType fromConnections:(NSArray *)connections
{
    for ( AVCaptureConnection *connection in connections ) {
        for ( AVCaptureInputPort *port in [connection inputPorts] ) {
            if ( [[port mediaType] isEqual:mediaType] ) {
                return connection;
            }
        }
    }
    return nil;
}

@end

@implementation QrReaderViewFactory{
    NSObject<FlutterPluginRegistrar>* _registrar;
}
- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar
{
    self = [super init];
    if (self) {
        _registrar = registrar;
    }
    return self;
}

- (NSObject<FlutterMessageCodec>*)createArgsCodec {
    return [FlutterStandardMessageCodec sharedInstance];
}

- (NSObject<FlutterPlatformView>*)createWithFrame:(CGRect)frame
                                   viewIdentifier:(int64_t)viewId
                                        arguments:(id _Nullable)args
{
    QrReaderViewController* viewController = [[QrReaderViewController alloc] initWithFrame:frame
                                                                            viewIdentifier:viewId
                                                                                 arguments:args
                                                                           binaryRegistrar:_registrar];
    return viewController;
}
@end

