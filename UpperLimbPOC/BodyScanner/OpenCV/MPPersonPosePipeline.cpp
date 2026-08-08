// SPDX-License-Identifier: Apache-2.0
// Decoder contract: OpenCV Zoo commit 47534e27c9851bb1128ccc0102f1145e27f23f98.
// This bounded port emits only shoulders, elbows, and wrists and performs no
// camera capture, rendering, persistence, or clinical interpretation.
#include "MPPersonPosePipeline.hpp"

#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

namespace upper_limb::opencv {
namespace {

constexpr int kPersonInput = 224;
constexpr int kPoseInput = 256;
constexpr int kPersonAnchorCount = 2254;
constexpr int kPersonRegressionWidth = 12;
constexpr int kPoseLandmarkCount = 39;
constexpr int kPoseValuesPerLandmark = 5;
constexpr float kPersonThreshold = 0.5F;
constexpr float kPersonNmsThreshold = 0.3F;
constexpr float kPoseThreshold = 0.5F;
constexpr float kCropExpansion = 1.25F;

cv::Point2f applyAffine(const cv::Matx23f &transform, cv::Point2f point) {
    return cv::Point2f(
        transform(0, 0) * point.x + transform(0, 1) * point.y + transform(0, 2),
        transform(1, 0) * point.x + transform(1, 1) * point.y + transform(1, 2)
    );
}

cv::Point2f rotateVector(cv::Point2f vector, float radians) {
    const float cosine = std::cos(radians);
    const float sine = std::sin(radians);
    return cv::Point2f(
        cosine * vector.x - sine * vector.y,
        sine * vector.x + cosine * vector.y
    );
}

}  // namespace

MPPersonPosePipeline::MPPersonPosePipeline(
    cv::dnn::Net personDetector,
    cv::dnn::Net poseEstimator
) : personDetector_(std::move(personDetector)),
    poseEstimator_(std::move(poseEstimator)),
    personAnchors_(generatePersonAnchors()) {
    if (personDetector_.empty() || poseEstimator_.empty()) {
        throw std::invalid_argument("person and pose networks must both be loaded");
    }
}

std::vector<MPPersonPosePipeline::PersonAnchor> MPPersonPosePipeline::generatePersonAnchors() {
    std::vector<PersonAnchor> anchors;
    anchors.reserve(kPersonAnchorCount);

    const auto appendGrid = [&anchors](int gridSize, int anchorsPerCell) {
        for (int y = 0; y < gridSize; ++y) {
            for (int x = 0; x < gridSize; ++x) {
                for (int repeat = 0; repeat < anchorsPerCell; ++repeat) {
                    anchors.push_back(PersonAnchor{
                        (static_cast<float>(x) + 0.5F) / static_cast<float>(gridSize),
                        (static_cast<float>(y) + 0.5F) / static_cast<float>(gridSize),
                    });
                }
            }
        }
    };

    // MediaPipe person detector: 28x28x2, 14x14x2, then 7x7x6.
    appendGrid(28, 2);
    appendGrid(14, 2);
    appendGrid(7, 6);
    if (anchors.size() != kPersonAnchorCount) {
        throw std::logic_error("person anchor contract produced the wrong count");
    }
    return anchors;
}

std::vector<float> MPPersonPosePipeline::flattenOutputWithElementCount(
    const std::vector<cv::Mat> &outputs,
    size_t elementCount
) {
    for (const cv::Mat &output : outputs) {
        if (output.total() != elementCount || output.depth() != CV_32F) {
            continue;
        }
        cv::Mat contiguous = output.isContinuous() ? output : output.clone();
        const float *begin = contiguous.ptr<float>();
        return std::vector<float>(begin, begin + elementCount);
    }
    throw std::runtime_error("model output shape does not match the pinned decoder");
}

double MPPersonPosePipeline::sigmoid(double value) {
    if (value >= 0) {
        const double exponential = std::exp(-value);
        return 1.0 / (1.0 + exponential);
    }
    const double exponential = std::exp(value);
    return exponential / (1.0 + exponential);
}

MPPersonPosePipeline::PersonDetection MPPersonPosePipeline::decodeBestPerson(
    const std::vector<cv::Mat> &outputs,
    const std::vector<PersonAnchor> &anchors,
    float resizeScale,
    float padX,
    float padY,
    cv::Size imageSize
) {
    const std::vector<float> regression = flattenOutputWithElementCount(
        outputs,
        kPersonAnchorCount * kPersonRegressionWidth
    );
    const std::vector<float> scores = flattenOutputWithElementCount(outputs, kPersonAnchorCount);

    std::vector<PersonDetection> candidates;
    std::vector<cv::Rect2d> boxes;
    std::vector<float> candidateScores;
    for (size_t index = 0; index < anchors.size(); ++index) {
        const float score = static_cast<float>(sigmoid(scores[index]));
        if (!std::isfinite(score) || score < kPersonThreshold) {
            continue;
        }
        const float *values = regression.data() + index * kPersonRegressionWidth;
        const PersonAnchor anchor = anchors[index];
        const auto detectorToImage = [=](float normalizedX, float normalizedY) {
            return cv::Point2f(
                (normalizedX * kPersonInput - padX) / resizeScale,
                (normalizedY * kPersonInput - padY) / resizeScale
            );
        };

        const float centerX = values[0] / kPersonInput + anchor.xCenter;
        const float centerY = values[1] / kPersonInput + anchor.yCenter;
        const float width = values[2] / kPersonInput;
        const float height = values[3] / kPersonInput;
        const cv::Point2f topLeft = detectorToImage(centerX - width * 0.5F, centerY - height * 0.5F);
        const cv::Point2f bottomRight = detectorToImage(centerX + width * 0.5F, centerY + height * 0.5F);

        PersonDetection candidate;
        candidate.bounds = cv::Rect2f(topLeft, bottomRight);
        candidate.score = score;
        const cv::Rect2f imageBounds(0, 0, static_cast<float>(imageSize.width), static_cast<float>(imageSize.height));
        candidate.bounds &= imageBounds;
        if (!std::isfinite(candidate.bounds.x)
            || !std::isfinite(candidate.bounds.y)
            || candidate.bounds.width < 1.0F
            || candidate.bounds.height < 1.0F) {
            continue;
        }
        for (size_t point = 0; point < candidate.keypoints.size(); ++point) {
            const float pointX = values[4 + point * 2] / kPersonInput + anchor.xCenter;
            const float pointY = values[5 + point * 2] / kPersonInput + anchor.yCenter;
            candidate.keypoints[point] = detectorToImage(pointX, pointY);
        }
        candidates.push_back(candidate);
        boxes.emplace_back(candidate.bounds.x, candidate.bounds.y, candidate.bounds.width, candidate.bounds.height);
        candidateScores.push_back(score);
    }

    std::vector<int> keptIndices;
    cv::dnn::NMSBoxes(
        boxes,
        candidateScores,
        kPersonThreshold,
        kPersonNmsThreshold,
        keptIndices
    );
    if (keptIndices.empty()) {
        throw NoPersonError();
    }
    if (keptIndices.size() > 1) {
        throw MultiplePeopleError();
    }
    return candidates[static_cast<size_t>(keptIndices[0])];
}

MPPersonPosePipeline::PoseCrop MPPersonPosePipeline::makePoseCrop(
    const cv::Mat &rgbImage,
    const PersonDetection &person
) {
    cv::Point2f center = person.keypoints[0];
    cv::Point2f scalePoint = person.keypoints[1];
    float radius = cv::norm(scalePoint - center);
    if (!std::isfinite(radius) || radius < 1.0F) {
        center = cv::Point2f(
            person.bounds.x + person.bounds.width * 0.5F,
            person.bounds.y + person.bounds.height * 0.5F
        );
        radius = 0.5F * std::max(person.bounds.width, person.bounds.height);
        scalePoint = center + cv::Point2f(0, -radius);
    }

    const float cropSize = std::max(2.0F, radius * 2.0F * kCropExpansion);
    const cv::Point2f torsoVector = scalePoint - center;
    const float rotation = static_cast<float>(CV_PI * 0.5)
        - std::atan2(-torsoVector.y, torsoVector.x);
    const float half = cropSize * 0.5F;
    const std::array<cv::Point2f, 3> source = {
        center + rotateVector(cv::Point2f(-half, -half), rotation),
        center + rotateVector(cv::Point2f(half, -half), rotation),
        center + rotateVector(cv::Point2f(-half, half), rotation),
    };
    const float destinationSpan = static_cast<float>(kPoseInput - 1);
    const cv::Point2f sourceX = (source[1] - source[0]) * (1.0F / destinationSpan);
    const cv::Point2f sourceY = (source[2] - source[0]) * (1.0F / destinationSpan);
    const cv::Matx23f inputToImage(
        sourceX.x, sourceY.x, source[0].x,
        sourceX.y, sourceY.y, source[0].y
    );
    const float determinant = sourceX.x * sourceY.y - sourceY.x * sourceX.y;
    if (!std::isfinite(determinant) || std::abs(determinant) < 1e-8F) {
        throw std::runtime_error("pose crop transform is singular");
    }
    const float inverseDeterminant = 1.0F / determinant;
    const cv::Matx22f imageToInputLinear(
        sourceY.y * inverseDeterminant,
        -sourceY.x * inverseDeterminant,
        -sourceX.y * inverseDeterminant,
        sourceX.x * inverseDeterminant
    );
    const cv::Vec2f imageToInputOffset = -imageToInputLinear
        * cv::Vec2f(source[0].x, source[0].y);
    const cv::Matx23f imageToInput(
        imageToInputLinear(0, 0), imageToInputLinear(0, 1), imageToInputOffset[0],
        imageToInputLinear(1, 0), imageToInputLinear(1, 1), imageToInputOffset[1]
    );
    cv::Mat crop;
    cv::warpAffine(
        rgbImage,
        crop,
        imageToInput,
        cv::Size(kPoseInput, kPoseInput),
        cv::INTER_LINEAR,
        cv::BORDER_CONSTANT,
        cv::Scalar(0, 0, 0)
    );

    return PoseCrop{crop, inputToImage, center, cropSize};
}

UpperLimbPoseResult MPPersonPosePipeline::inferBGRA8(const cv::Mat &bgraImage) {
    if (bgraImage.empty() || bgraImage.type() != CV_8UC4) {
        throw std::invalid_argument("input must be a non-empty CV_8UC4 image");
    }

    cv::Mat rgbImage;
    cv::cvtColor(bgraImage, rgbImage, cv::COLOR_BGRA2RGB);

    const float resizeScale = std::min(
        static_cast<float>(kPersonInput) / static_cast<float>(rgbImage.cols),
        static_cast<float>(kPersonInput) / static_cast<float>(rgbImage.rows)
    );
    const cv::Size resizedSize(
        std::max(1, static_cast<int>(std::round(rgbImage.cols * resizeScale))),
        std::max(1, static_cast<int>(std::round(rgbImage.rows * resizeScale)))
    );
    const float padX = 0.5F * static_cast<float>(kPersonInput - resizedSize.width);
    const float padY = 0.5F * static_cast<float>(kPersonInput - resizedSize.height);
    cv::Mat resized;
    cv::resize(rgbImage, resized, resizedSize);
    cv::Mat detectorImage(kPersonInput, kPersonInput, CV_8UC3, cv::Scalar(0, 0, 0));
    resized.copyTo(detectorImage(cv::Rect(
        static_cast<int>(std::floor(padX)),
        static_cast<int>(std::floor(padY)),
        resizedSize.width,
        resizedSize.height
    )));

    cv::Mat personBlob = cv::dnn::blobFromImage(
        detectorImage,
        1.0 / 127.5,
        cv::Size(kPersonInput, kPersonInput),
        cv::Scalar(127.5, 127.5, 127.5),
        false,
        false,
        CV_32F
    );
    personDetector_.setInput(personBlob);
    std::vector<cv::Mat> personOutputs;
    personDetector_.forward(personOutputs, personDetector_.getUnconnectedOutLayersNames());
    const PersonDetection person = decodeBestPerson(
        personOutputs,
        personAnchors_,
        resizeScale,
        std::floor(padX),
        std::floor(padY),
        rgbImage.size()
    );

    const PoseCrop poseCrop = makePoseCrop(rgbImage, person);
    cv::Mat normalizedPose;
    poseCrop.rgb.convertTo(normalizedPose, CV_32FC3, 1.0 / 255.0);
    const int poseShape[] = {1, kPoseInput, kPoseInput, 3};
    cv::Mat poseInput(4, poseShape, CV_32F);
    normalizedPose.copyTo(cv::Mat(kPoseInput, kPoseInput, CV_32FC3, poseInput.ptr<float>()));

    poseEstimator_.setInput(poseInput);
    std::vector<cv::Mat> poseOutputs;
    poseEstimator_.forward(poseOutputs, poseEstimator_.getUnconnectedOutLayersNames());
    const std::vector<float> rawLandmarks = flattenOutputWithElementCount(
        poseOutputs,
        kPoseLandmarkCount * kPoseValuesPerLandmark
    );
    const std::vector<float> rawPoseScore = flattenOutputWithElementCount(poseOutputs, 1);
    const float poseScore = rawPoseScore[0];
    if (!std::isfinite(poseScore) || poseScore < kPoseThreshold) {
        throw NoPoseError();
    }

    UpperLimbPoseResult result;
    result.personScore = person.score;
    result.poseScore = rawPoseScore[0];
    result.poseCropCenterX = poseCrop.center.x;
    result.poseCropCenterY = poseCrop.center.y;
    result.poseCropSize = poseCrop.size;
    result.landmarks.reserve(6);
    for (int index = 0; index < kPoseLandmarkCount; ++index) {
        switch (index) {
            case 11:
            case 12:
            case 13:
            case 14:
            case 15:
            case 16:
                break;
            default:
                continue;
        }

        const float *values = rawLandmarks.data() + index * kPoseValuesPerLandmark;
        const cv::Point2f imagePoint = applyAffine(
            poseCrop.inputToImage,
            cv::Point2f(values[0], values[1])
        );
        result.landmarks.push_back(PoseLandmark{
            index,
            imagePoint.x,
            imagePoint.y,
            values[2] / static_cast<double>(kPoseInput),
            sigmoid(values[3]),
            sigmoid(values[4]),
        });
    }
    return result;
}

}  // namespace upper_limb::opencv
