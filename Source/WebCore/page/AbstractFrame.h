/*
 * Copyright (C) 2018 Apple Inc. All rights reserved.
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

#pragma once

#include "FrameTree.h"
#include <wtf/Ref.h>
#include <wtf/ThreadSafeRefCounted.h>
#include <wtf/WeakPtr.h>

namespace WebCore {

class AbstractDOMWindow;
class HTMLFrameOwnerElement;
class Page;
class WindowProxy;

// FIXME: Rename Frame to LocalFrame and AbstractFrame to Frame.
class AbstractFrame : public ThreadSafeRefCounted<AbstractFrame, WTF::DestructionThread::Main>, public CanMakeWeakPtr<AbstractFrame> {
public:
    virtual ~AbstractFrame();

    virtual bool isLocalFrame() const = 0;
    virtual bool isRemoteFrame() const = 0;

    WindowProxy& windowProxy() { return m_windowProxy; }
    const WindowProxy& windowProxy() const { return m_windowProxy; }
    AbstractDOMWindow* window() const { return virtualWindow(); }
    FrameTree& tree() const { return m_treeNode; }
    WEBCORE_EXPORT Page* page() const;
    WEBCORE_EXPORT void detachFromPage();

protected:
    AbstractFrame(Page&, HTMLFrameOwnerElement*);
    void resetWindowProxy();

private:
    virtual AbstractDOMWindow* virtualWindow() const = 0;

    WeakPtr<Page> m_page;
    mutable FrameTree m_treeNode;
    Ref<WindowProxy> m_windowProxy;
};

} // namespace WebCore
