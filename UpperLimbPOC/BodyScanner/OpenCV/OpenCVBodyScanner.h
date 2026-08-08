#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const OCVBodyScannerErrorDomain;

typedef NS_ERROR_ENUM(OCVBodyScannerErrorDomain, OCVBodyScannerErrorCode) {
    OCVBodyScannerErrorInvalidInput = 1,
    OCVBodyScannerErrorModelMissing = 2,
    OCVBodyScannerErrorModelLoadFailed = 3,
    OCVBodyScannerErrorModelsNotLoaded = 4,
    OCVBodyScannerErrorNoPerson = 5,
    OCVBodyScannerErrorInferenceFailed = 6,
    OCVBodyScannerErrorNoPose = 7,
    OCVBodyScannerErrorMultiplePeople = 8,
};

/// Paths must refer to resources that have already passed the Swift manifest's
/// size and SHA-256 gate. Loading an ONNX file is not an integrity check.
@interface OCVBodyScannerModelPaths : NSObject

@property(nonatomic, copy, readonly) NSString *personDetectorPath;
@property(nonatomic, copy, readonly) NSString *poseEstimatorPath;

- (instancetype)initWithPersonDetectorPath:(NSString *)personDetectorPath
                          poseEstimatorPath:(NSString *)poseEstimatorPath NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

/// Raw MediaPipe pose evidence. The Swift mapper owns anatomical names,
/// confidence qualification, and construction of the frozen joint-frame type.
@interface OCVPoseLandmark : NSObject

@property(nonatomic, readonly) NSInteger mediaPipeIndex;
@property(nonatomic, readonly) double imageX;
@property(nonatomic, readonly) double imageY;
@property(nonatomic, readonly) double modelRelativeZ;
@property(nonatomic, readonly) double visibility;
@property(nonatomic, readonly) double presence;

@end

@interface OCVUpperLimbPoseResult : NSObject

@property(nonatomic, readonly) double personScore;
@property(nonatomic, readonly) double poseScore;
@property(nonatomic, readonly) double poseCropCenterX;
@property(nonatomic, readonly) double poseCropCenterY;
@property(nonatomic, readonly) double poseCropSize;
@property(nonatomic, copy, readonly) NSArray<OCVPoseLandmark *> *landmarks;

@end

/// OpenCV-only inference boundary. Callers provide an already oriented BGRA8
/// frame. Results are educational tracking evidence, not clinical findings.
@interface OCVBodyScanner : NSObject

@property(nonatomic, readonly, getter=areModelsLoaded) BOOL modelsLoaded;
@property(class, nonatomic, copy, readonly) NSString *linkedOpenCVVersion;

- (instancetype)initWithVerifiedModelPaths:(OCVBodyScannerModelPaths *)modelPaths
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)loadModels:(NSError **)error;

- (nullable OCVUpperLimbPoseResult *)inferBGRA8:(NSData *)pixels
                                          width:(NSInteger)width
                                         height:(NSInteger)height
                                    bytesPerRow:(NSInteger)bytesPerRow
                                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
