#import "OpenCVBodyScanner.h"

#include "MPPersonPosePipeline.hpp"

#include <opencv2/core/version.hpp>
#include <opencv2/dnn.hpp>

#include <memory>
#include <string>

static_assert(CV_VERSION_MAJOR == 4, "The body-scanner spike requires OpenCV 4.13.0");
static_assert(CV_VERSION_MINOR == 13, "The body-scanner spike requires OpenCV 4.13.0");
static_assert(CV_VERSION_REVISION == 0, "The body-scanner spike requires OpenCV 4.13.0");

NSErrorDomain const OCVBodyScannerErrorDomain = @"com.upperlimbpoc.body-scanner.opencv";

namespace {

NSError *MakeError(OCVBodyScannerErrorCode code, NSString *description) {
    return [NSError errorWithDomain:OCVBodyScannerErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

}  // namespace

@implementation OCVBodyScannerModelPaths

- (instancetype)initWithPersonDetectorPath:(NSString *)personDetectorPath
                          poseEstimatorPath:(NSString *)poseEstimatorPath {
    self = [super init];
    if (self) {
        _personDetectorPath = [personDetectorPath copy];
        _poseEstimatorPath = [poseEstimatorPath copy];
    }
    return self;
}

@end

@interface OCVPoseLandmark ()
- (instancetype)initWithLandmark:(const upper_limb::opencv::PoseLandmark &)landmark;
@end

@implementation OCVPoseLandmark

- (instancetype)initWithLandmark:(const upper_limb::opencv::PoseLandmark &)landmark {
    self = [super init];
    if (self) {
        _mediaPipeIndex = landmark.mediaPipeIndex;
        _imageX = landmark.imageX;
        _imageY = landmark.imageY;
        _modelRelativeZ = landmark.modelRelativeZ;
        _visibility = landmark.visibility;
        _presence = landmark.presence;
    }
    return self;
}

@end

@interface OCVUpperLimbPoseResult ()
- (instancetype)initWithResult:(const upper_limb::opencv::UpperLimbPoseResult &)result;
@end

@implementation OCVUpperLimbPoseResult

- (instancetype)initWithResult:(const upper_limb::opencv::UpperLimbPoseResult &)result {
    self = [super init];
    if (self) {
        _personScore = result.personScore;
        _poseScore = result.poseScore;
        _poseCropCenterX = result.poseCropCenterX;
        _poseCropCenterY = result.poseCropCenterY;
        _poseCropSize = result.poseCropSize;
        NSMutableArray<OCVPoseLandmark *> *landmarks = [NSMutableArray arrayWithCapacity:result.landmarks.size()];
        for (const auto &landmark : result.landmarks) {
            [landmarks addObject:[[OCVPoseLandmark alloc] initWithLandmark:landmark]];
        }
        _landmarks = [landmarks copy];
    }
    return self;
}

@end

@interface OCVBodyScanner () {
    OCVBodyScannerModelPaths *_modelPaths;
    std::unique_ptr<upper_limb::opencv::MPPersonPosePipeline> _pipeline;
}
@end

@implementation OCVBodyScanner

+ (NSString *)linkedOpenCVVersion {
    return [NSString stringWithUTF8String:CV_VERSION];
}

- (instancetype)initWithVerifiedModelPaths:(OCVBodyScannerModelPaths *)modelPaths {
    self = [super init];
    if (self) {
        _modelPaths = modelPaths;
    }
    return self;
}

- (BOOL)areModelsLoaded {
    return _pipeline != nullptr;
}

- (BOOL)loadModels:(NSError **)error {
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files isReadableFileAtPath:_modelPaths.personDetectorPath]
        || ![files isReadableFileAtPath:_modelPaths.poseEstimatorPath]) {
        if (error) {
            *error = MakeError(OCVBodyScannerErrorModelMissing, @"A pinned person or pose ONNX resource is missing.");
        }
        return NO;
    }

    try {
        cv::dnn::Net personDetector = cv::dnn::readNetFromONNX(_modelPaths.personDetectorPath.UTF8String);
        cv::dnn::Net poseEstimator = cv::dnn::readNetFromONNX(_modelPaths.poseEstimatorPath.UTF8String);
        personDetector.setPreferableBackend(cv::dnn::DNN_BACKEND_OPENCV);
        personDetector.setPreferableTarget(cv::dnn::DNN_TARGET_CPU);
        poseEstimator.setPreferableBackend(cv::dnn::DNN_BACKEND_OPENCV);
        poseEstimator.setPreferableTarget(cv::dnn::DNN_TARGET_CPU);
        _pipeline = std::make_unique<upper_limb::opencv::MPPersonPosePipeline>(
            std::move(personDetector),
            std::move(poseEstimator)
        );
        return YES;
    } catch (const cv::Exception &exception) {
        _pipeline.reset();
        if (error) {
            NSString *detail = [NSString stringWithUTF8String:exception.what()];
            *error = MakeError(OCVBodyScannerErrorModelLoadFailed, detail);
        }
        return NO;
    } catch (const std::exception &exception) {
        _pipeline.reset();
        if (error) {
            NSString *detail = [NSString stringWithUTF8String:exception.what()];
            *error = MakeError(OCVBodyScannerErrorModelLoadFailed, detail);
        }
        return NO;
    }
}

- (nullable OCVUpperLimbPoseResult *)inferBGRA8:(NSData *)pixels
                                          width:(NSInteger)width
                                         height:(NSInteger)height
                                    bytesPerRow:(NSInteger)bytesPerRow
                                          error:(NSError **)error {
    if (!_pipeline) {
        if (error) {
            *error = MakeError(OCVBodyScannerErrorModelsNotLoaded, @"Call loadModels before inference.");
        }
        return nil;
    }
    if (width <= 0 || height <= 0 || bytesPerRow < width * 4
        || pixels.length < (NSUInteger)(bytesPerRow * height)) {
        if (error) {
            *error = MakeError(OCVBodyScannerErrorInvalidInput, @"The BGRA8 buffer dimensions are inconsistent.");
        }
        return nil;
    }

    try {
        cv::Mat bgra(
            static_cast<int>(height),
            static_cast<int>(width),
            CV_8UC4,
            const_cast<void *>(pixels.bytes),
            static_cast<size_t>(bytesPerRow)
        );
        const upper_limb::opencv::UpperLimbPoseResult result = _pipeline->inferBGRA8(bgra);
        return [[OCVUpperLimbPoseResult alloc] initWithResult:result];
    } catch (const upper_limb::opencv::NoPersonError &exception) {
        if (error) {
            *error = MakeError(OCVBodyScannerErrorNoPerson, @"No person met the pinned detector threshold.");
        }
        return nil;
    } catch (const upper_limb::opencv::NoPoseError &exception) {
        if (error) {
            *error = MakeError(OCVBodyScannerErrorNoPose, @"No pose met the pinned confidence threshold.");
        }
        return nil;
    } catch (const upper_limb::opencv::MultiplePeopleError &exception) {
        if (error) {
            *error = MakeError(OCVBodyScannerErrorMultiplePeople, @"More than one person is visible — frame only the consenting participant.");
        }
        return nil;
    } catch (const std::exception &exception) {
        if (error) {
            NSString *detail = [NSString stringWithUTF8String:exception.what()];
            *error = MakeError(OCVBodyScannerErrorInferenceFailed, detail);
        }
        return nil;
    }
}

@end
