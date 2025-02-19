/*
 * Copyright (C) 2022 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "config.h"
#include "VideoFrameCV.h"

#if ENABLE(VIDEO) && USE(AVFOUNDATION)
#include "CVUtilities.h"
#include "ImageTransferSessionVT.h"
#include "Logging.h"
#include "NativeImage.h"
#include "PixelBuffer.h"
#include "ProcessIdentity.h"
#include <pal/avfoundation/MediaTimeAVFoundation.h>
#include <pal/cf/AudioToolboxSoftLink.h>
#include <pal/cf/CoreMediaSoftLink.h>
#include <wtf/Scope.h>

#include "CoreVideoSoftLink.h"

#if USE(LIBWEBRTC)
ALLOW_UNUSED_PARAMETERS_BEGIN
ALLOW_COMMA_BEGIN

#include <webrtc/sdk/WebKit/WebKitUtilities.h>

ALLOW_UNUSED_PARAMETERS_END
ALLOW_COMMA_END
#endif

namespace WebCore {

RefPtr<VideoFrame> VideoFrame::fromNativeImage(NativeImage& image)
{
    auto transferSession = ImageTransferSessionVT::create(kCVPixelFormatType_32ARGB, false);
    return transferSession->createVideoFrame(image.platformImage().get(), { }, image.size());
}

static const uint8_t* copyToCVPixelBufferPlane(CVPixelBufferRef pixelBuffer, size_t planeIndex, const uint8_t* source, size_t height, uint32_t bytesPerRowSource)
{
    auto* destination = static_cast<uint8_t*>(CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, planeIndex));
    uint32_t bytesPerRowDestination = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, planeIndex);
    for (unsigned i = 0; i < height; ++i) {
        std::memcpy(destination, source, std::min(bytesPerRowSource, bytesPerRowDestination));
        source += bytesPerRowSource;
        destination += bytesPerRowDestination;
    }
    return source;
}

RefPtr<VideoFrame> VideoFrame::createNV12(Span<const uint8_t> span, size_t width, size_t height, const ComputedPlaneLayout& planeY, const ComputedPlaneLayout& planeUV)
{
    CVPixelBufferRef rawPixelBuffer = nullptr;

    auto status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nullptr, &rawPixelBuffer);
    if (status != noErr || !rawPixelBuffer)
        return nullptr;
    auto pixelBuffer = adoptCF(rawPixelBuffer);

    status = CVPixelBufferLockBaseAddress(rawPixelBuffer, 0);
    if (status != noErr)
        return nullptr;

    auto scope = makeScopeExit([&rawPixelBuffer] {
        CVPixelBufferUnlockBaseAddress(rawPixelBuffer, 0);
    });

    auto* data = span.data();
    data = copyToCVPixelBufferPlane(rawPixelBuffer, 0, data, height, planeY.sourceWidthBytes);
    if (CVPixelBufferGetPlaneCount(rawPixelBuffer) == 2) {
        if (CVPixelBufferGetWidthOfPlane(rawPixelBuffer, 1) != (width / 2) || CVPixelBufferGetHeightOfPlane(rawPixelBuffer, 1) != (height / 2))
            return nullptr;
        copyToCVPixelBufferPlane(rawPixelBuffer, 1, data, height / 2, planeUV.sourceWidthBytes);
    }

    return VideoFrameCV::create({ }, false, Rotation::None, WTFMove(pixelBuffer));
}

RefPtr<VideoFrame> VideoFrame::createRGBA(Span<const uint8_t> span, size_t width, size_t height, const ComputedPlaneLayout& plane)
{
    CVPixelBufferRef rawPixelBuffer = nullptr;

    auto status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, nullptr, &rawPixelBuffer);
    if (status != noErr || !rawPixelBuffer)
        return nullptr;
    auto pixelBuffer = adoptCF(rawPixelBuffer);

    status = CVPixelBufferLockBaseAddress(rawPixelBuffer, 0);
    if (status != noErr)
        return nullptr;

    auto scope = makeScopeExit([&rawPixelBuffer] {
        CVPixelBufferUnlockBaseAddress(rawPixelBuffer, 0);
    });

    auto* source = span.data();
    auto* destination = static_cast<uint8_t*>(CVPixelBufferGetBaseAddressOfPlane(rawPixelBuffer, 0));
    size_t bytesPerRowDestination = CVPixelBufferGetBytesPerRowOfPlane(rawPixelBuffer, 0);
    for (unsigned i = 0; i < height; ++i) {
        size_t j = 0;
        while (j < std::min(plane.sourceWidthBytes, bytesPerRowDestination)) {
            // RGBA -> ARGB.
            destination[j] = source[j + 3];
            destination[j + 1] = source[j];
            destination[j + 2] = source[j + 1];
            destination[j + 3] = source[j + 2];
            j += 4;
        }
        source += plane.sourceWidthBytes;
        destination += bytesPerRowDestination;
    }

    return VideoFrameCV::create({ }, false, Rotation::None, WTFMove(pixelBuffer));
}

RefPtr<VideoFrame> VideoFrame::createBGRA(Span<const uint8_t> span, size_t width, size_t height, const ComputedPlaneLayout& plane)
{
    CVPixelBufferRef rawPixelBuffer = nullptr;

    auto status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nullptr, &rawPixelBuffer);
    if (status != noErr || !rawPixelBuffer)
        return nullptr;
    auto pixelBuffer = adoptCF(rawPixelBuffer);

    status = CVPixelBufferLockBaseAddress(rawPixelBuffer, 0);
    if (status != noErr)
        return nullptr;

    auto scope = makeScopeExit([&rawPixelBuffer] {
        CVPixelBufferUnlockBaseAddress(rawPixelBuffer, 0);
    });

    copyToCVPixelBufferPlane(rawPixelBuffer, 0, span.data(), height, plane.sourceWidthBytes);

    return VideoFrameCV::create({ }, false, Rotation::None, WTFMove(pixelBuffer));
}

RefPtr<VideoFrame> VideoFrame::createI420(Span<const uint8_t> buffer, size_t width, size_t height, const ComputedPlaneLayout& layoutY, const ComputedPlaneLayout& layoutU, const ComputedPlaneLayout& layoutV)
{
#if USE(LIBWEBRTC)
    size_t offsetLayoutU = layoutY.sourceLeftBytes + layoutY.sourceWidthBytes * height;
    size_t offsetLayoutV = offsetLayoutU + layoutU.sourceLeftBytes + layoutU.sourceWidthBytes * ((height + 1) / 2);
    webrtc::I420BufferLayout layout {
        layoutY.sourceLeftBytes, layoutY.sourceWidthBytes,
        offsetLayoutU, layoutU.sourceWidthBytes,
        offsetLayoutV, layoutV.sourceWidthBytes
    };
    auto pixelBuffer = adoptCF(webrtc::pixelBufferFromI420Buffer(buffer.data(), buffer.size(), width, height, layout));

    if (!pixelBuffer)
        return nullptr;

    return VideoFrameCV::create({ }, false, Rotation::None, WTFMove(pixelBuffer));
#else
    UNUSED_PARAM(buffer);
    UNUSED_PARAM(width);
    UNUSED_PARAM(height);
    UNUSED_PARAM(layoutY);
    UNUSED_PARAM(layoutU);
    UNUSED_PARAM(layoutV);
    return nullptr;
#endif
}

static Vector<PlaneLayout> copyRGBData(Span<uint8_t> span, const ComputedPlaneLayout& spanPlaneLayout, CVPixelBufferRef pixelBuffer, const Function<void(uint8_t*, const uint8_t*, size_t)>& copyRow)
{
    auto result = CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    if (result != kCVReturnSuccess) {
        RELEASE_LOG_ERROR(WebRTC, "VideoFrame::copyTo lock failed: %d", result);
        return { };
    }

    auto scope = makeScopeExit([&pixelBuffer] {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    });

    auto* planeA = static_cast<const uint8_t*>(CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0));
    if (!planeA) {
        RELEASE_LOG_ERROR(WebRTC, "VideoFrame::copyTo plane A is null");
        return { };
    }

    auto height = CVPixelBufferGetHeight(pixelBuffer);
    auto width = CVPixelBufferGetWidth(pixelBuffer);
    auto bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);

    PlaneLayout planeLayout { spanPlaneLayout.destinationOffset, spanPlaneLayout.destinationStride ? spanPlaneLayout.destinationStride : 4 * width };

    auto* destination = span.data() + planeLayout.offset;
    auto* source = planeA;
    for (size_t cptr = 0; cptr < height; ++cptr) {
        copyRow(destination, source, width);
        destination += planeLayout.stride;
        source += bytesPerRow;
    }

    Vector<PlaneLayout> planeLayouts;
    planeLayouts.append(planeLayout);
    return planeLayouts;
}

static Vector<PlaneLayout> copyNV12(Span<uint8_t> span, const ComputedPlaneLayout& spanPlaneLayoutY, const ComputedPlaneLayout& spanPlaneLayoutUV, CVPixelBufferRef pixelBuffer)
{
    auto result = CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    if (result != kCVReturnSuccess) {
        RELEASE_LOG_ERROR(WebRTC, "VideoFrame::copyTo lock failed: %d", result);
        return { };
    }

    auto scope = makeScopeExit([&pixelBuffer] {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    });

    auto* planeY = static_cast<const uint8_t*>(CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0));
    if (!planeY) {
        RELEASE_LOG_ERROR(WebRTC, "VideoFrame::copyTo plane Y is null");
        return { };
    }
    auto* planeUV = static_cast<const uint8_t*>(CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1));
    if (!planeUV) {
        RELEASE_LOG_ERROR(WebRTC, "VideoFrame::copyTo plane UV is null");
        return { };
    }

    auto widthY = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
    auto heightY = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
    auto bytesPerRowY = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    PlaneLayout planeLayoutY { spanPlaneLayoutY.destinationOffset, spanPlaneLayoutY.destinationStride ? spanPlaneLayoutY.destinationStride : widthY };

    auto* destination = span.data() + planeLayoutY.offset;
    auto* source = planeY;
    size_t size = bytesPerRowY < planeLayoutY.stride ? bytesPerRowY : planeLayoutY.stride;
    for (size_t cptr = 0; cptr < heightY; ++cptr) {
        std::memcpy(destination, source, size);
        destination += planeLayoutY.stride;
        source += bytesPerRowY;
    }

    auto widthUV = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1);
    auto heightUV = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);
    auto bytesPerRowUV = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    PlaneLayout planeLayoutUV { spanPlaneLayoutUV.destinationOffset, spanPlaneLayoutUV.destinationStride ? spanPlaneLayoutUV.destinationStride : widthUV };

    destination = span.data() + planeLayoutUV.offset;
    source = planeUV;
    size = bytesPerRowUV < planeLayoutUV.stride ? bytesPerRowUV : planeLayoutUV.stride;
    for (size_t cptr = 0; cptr < heightUV; ++cptr) {
        std::memcpy(destination, source, size);
        destination += planeLayoutUV.stride;
        source += bytesPerRowUV;
    }

    Vector<PlaneLayout> planeLayouts;
    planeLayouts.append(planeLayoutY);
    planeLayouts.append(planeLayoutUV);
    return planeLayouts;
}

void VideoFrame::copyTo(Span<uint8_t> span, VideoPixelFormat format, Vector<ComputedPlaneLayout>&& computedPlaneLayout, CompletionHandler<void(std::optional<Vector<PlaneLayout>>&&)>&& callback)
{
    if (format == VideoPixelFormat::NV12) {
        // FIXME: We should get the pixel buffer asynchronously if possible.
        callback(copyNV12(span, computedPlaneLayout[0], computedPlaneLayout[1], this->pixelBuffer()));
        return;
    }

    if (format == VideoPixelFormat::I420) {
#if USE(LIBWEBRTC)
        webrtc::I420BufferLayout layout {
            computedPlaneLayout[0].destinationOffset, computedPlaneLayout[0].destinationStride,
            computedPlaneLayout[1].destinationOffset, computedPlaneLayout[1].destinationStride,
            computedPlaneLayout[2].destinationOffset, computedPlaneLayout[2].destinationStride
        };
        // FIXME: We should get the pixel buffer asynchronously if possible.
        if (!webrtc::copyPixelBufferInI420Buffer(span.data(), span.size(), this->pixelBuffer(), layout)) {
            callback({ });
            return;
        }

        Vector<PlaneLayout> planeLayouts;
        planeLayouts.append({ layout.offsetY, layout.strideY });
        planeLayouts.append({ layout.offsetU, layout.strideU });
        planeLayouts.append({ layout.offsetV, layout.strideV });
        callback(WTFMove(planeLayouts));
        return;
#endif
    }

    if (format == VideoPixelFormat::RGBA) {
        ComputedPlaneLayout planeLayout;
        if (!computedPlaneLayout.isEmpty())
            planeLayout = computedPlaneLayout[0];
        // FIXME: We should get the pixel buffer asynchronously if possible.
        auto planeLayouts = copyRGBData(span, planeLayout, this->pixelBuffer(), [](auto* destination, auto* source, size_t pixelCount) {
            size_t i = 0;
            while (pixelCount-- > 0) {
                // ARGB -> RGBA.
                destination[i] = source[i + 1];
                destination[i + 1] = source[i + 2];
                destination[i + 2] = source[i + 3];
                destination[i + 3] = source[i];
                i += 4;
            }
        });
        callback(WTFMove(planeLayouts));
        return;
    }

    if (format == VideoPixelFormat::BGRA) {
        ComputedPlaneLayout planeLayout;
        if (!computedPlaneLayout.isEmpty())
            planeLayout = computedPlaneLayout[0];
        // FIXME: We should get the pixel buffer asynchronously if possible.
        auto planeLayouts = copyRGBData(span, planeLayout, this->pixelBuffer(), [](auto* destination, auto* source, size_t pixelCount) {
            std::memcpy(destination, source, pixelCount * 4);
        });
        callback(WTFMove(planeLayouts));
        return;
    }

    // FIXME: Add support for NV12 and I420.
    callback({ });
}

Ref<VideoFrameCV> VideoFrameCV::create(CMSampleBufferRef sampleBuffer, bool isMirrored, Rotation rotation)
{
    auto pixelBuffer = static_cast<CVPixelBufferRef>(PAL::CMSampleBufferGetImageBuffer(sampleBuffer));
    auto timeStamp = PAL::CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
    if (CMTIME_IS_INVALID(timeStamp))
        timeStamp = PAL::CMSampleBufferGetPresentationTimeStamp(sampleBuffer);

    return VideoFrameCV::create(PAL::toMediaTime(timeStamp), isMirrored, rotation, pixelBuffer);
}

Ref<VideoFrameCV> VideoFrameCV::create(MediaTime presentationTime, bool isMirrored, Rotation rotation, RetainPtr<CVPixelBufferRef>&& pixelBuffer)
{
    ASSERT(pixelBuffer);
    return adoptRef(*new VideoFrameCV(presentationTime, isMirrored, rotation, WTFMove(pixelBuffer)));
}

RefPtr<VideoFrameCV> VideoFrameCV::createFromPixelBuffer(Ref<PixelBuffer>&& pixelBuffer)
{
    auto size = pixelBuffer->size();
    auto width = size.width();
    auto height = size.height();

    auto dataBaseAddress = pixelBuffer->bytes();
    auto leakedBuffer = &pixelBuffer.leakRef();
    
    auto derefBuffer = [] (void* context, const void*) {
        static_cast<PixelBuffer*>(context)->deref();
    };

    CVPixelBufferRef cvPixelBufferRaw = nullptr;
    auto status = CVPixelBufferCreateWithBytes(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, dataBaseAddress, width * 4, derefBuffer, leakedBuffer, nullptr, &cvPixelBufferRaw);

    auto cvPixelBuffer = adoptCF(cvPixelBufferRaw);
    if (!cvPixelBuffer) {
        derefBuffer(leakedBuffer, nullptr);
        return nullptr;
    }
    ASSERT_UNUSED(status, !status);
    return create({ }, false, Rotation::None, WTFMove(cvPixelBuffer));
}

VideoFrameCV::VideoFrameCV(MediaTime presentationTime, bool isMirrored, Rotation rotation, RetainPtr<CVPixelBufferRef>&& pixelBuffer)
    : VideoFrame(presentationTime, isMirrored, rotation)
    , m_pixelBuffer(WTFMove(pixelBuffer))
{
}

VideoFrameCV::~VideoFrameCV() = default;

WebCore::FloatSize VideoFrameCV::presentationSize() const
{
    return { static_cast<float>(CVPixelBufferGetWidth(m_pixelBuffer.get())), static_cast<float>(CVPixelBufferGetHeight(m_pixelBuffer.get())) };
}

uint32_t VideoFrameCV::pixelFormat() const
{
    return CVPixelBufferGetPixelFormatType(m_pixelBuffer.get());
}

void VideoFrameCV::setOwnershipIdentity(const ProcessIdentity& resourceOwner)
{
    ASSERT(resourceOwner);
    auto buffer = pixelBuffer();
    ASSERT(buffer);
    setOwnershipIdentityForCVPixelBuffer(buffer, resourceOwner);
}

ImageOrientation VideoFrameCV::orientation() const
{
    // Sample transform first flips x-coordinates, then rotates.
    switch (rotation()) {
    case VideoFrame::Rotation::None:
        return isMirrored() ? ImageOrientation::OriginTopRight : ImageOrientation::OriginTopLeft;
    case VideoFrame::Rotation::Right:
        return isMirrored() ? ImageOrientation::OriginRightBottom : ImageOrientation::OriginRightTop;
    case VideoFrame::Rotation::UpsideDown:
        return isMirrored() ? ImageOrientation::OriginBottomLeft : ImageOrientation::OriginBottomRight;
    case VideoFrame::Rotation::Left:
        return isMirrored() ? ImageOrientation::OriginLeftTop : ImageOrientation::OriginLeftBottom;
    }
}

}

#endif
