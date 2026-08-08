// SPDX-License-Identifier: Apache-2.0
// Contract derived from OpenCV Zoo MediaPipe person/pose wrappers at
// https://github.com/opencv/opencv_zoo/tree/47534e27c9851bb1128ccc0102f1145e27f23f98/models
// Local changes: typed raw evidence, no visualization/I/O, CPU-only bridge.
#pragma once

#include <opencv2/core.hpp>
#include <opencv2/dnn.hpp>

#include <array>
#include <stdexcept>
#include <vector>

namespace upper_limb::opencv {

struct PoseLandmark {
    int mediaPipeIndex;
    double imageX;
    double imageY;
    double modelRelativeZ;
    double visibility;
    double presence;
};

struct UpperLimbPoseResult {
    double personScore;
    double poseScore;
    double poseCropCenterX;
    double poseCropCenterY;
    double poseCropSize;
    std::vector<PoseLandmark> landmarks;
};

class NoPersonError final : public std::runtime_error {
public:
    NoPersonError() : std::runtime_error("no person met the detector threshold") {}
};

class NoPoseError final : public std::runtime_error {
public:
    NoPoseError() : std::runtime_error("no pose met the confidence threshold") {}
};

class MultiplePeopleError final : public std::runtime_error {
public:
    MultiplePeopleError() : std::runtime_error("multiple people met the detector threshold") {}
};

class MPPersonPosePipeline final {
public:
    MPPersonPosePipeline(cv::dnn::Net personDetector, cv::dnn::Net poseEstimator);

    UpperLimbPoseResult inferBGRA8(const cv::Mat &bgraImage);

private:
    struct PersonAnchor {
        float xCenter;
        float yCenter;
    };

    struct PersonDetection {
        cv::Rect2f bounds;
        std::array<cv::Point2f, 4> keypoints;
        float score;
    };

    struct PoseCrop {
        cv::Mat rgb;
        cv::Matx23f inputToImage;
        cv::Point2f center;
        float size;
    };

    static std::vector<PersonAnchor> generatePersonAnchors();
    static PersonDetection decodeBestPerson(
        const std::vector<cv::Mat> &outputs,
        const std::vector<PersonAnchor> &anchors,
        float resizeScale,
        float padX,
        float padY,
        cv::Size imageSize
    );
    static PoseCrop makePoseCrop(const cv::Mat &rgbImage, const PersonDetection &person);
    static std::vector<float> flattenOutputWithElementCount(
        const std::vector<cv::Mat> &outputs,
        size_t elementCount
    );
    static double sigmoid(double value);

    cv::dnn::Net personDetector_;
    cv::dnn::Net poseEstimator_;
    std::vector<PersonAnchor> personAnchors_;
};

}  // namespace upper_limb::opencv
