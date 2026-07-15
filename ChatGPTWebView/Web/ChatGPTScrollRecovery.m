#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

static const void *CPChatGPTScrollScriptInstalledKey = &CPChatGPTScrollScriptInstalledKey;

@interface WKWebView (ContextPortChatGPTScrollRecovery)
- (void)cp_scrollRecovery_didMoveToWindow;
@end

@implementation WKWebView (ContextPortChatGPTScrollRecovery)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method originalMove = class_getInstanceMethod(self, @selector(didMoveToWindow));
        Method replacementMove = class_getInstanceMethod(self, @selector(cp_scrollRecovery_didMoveToWindow));
        method_exchangeImplementations(originalMove, replacementMove);
    });
}

- (void)cp_scrollRecovery_didMoveToWindow {
    [self cp_scrollRecovery_didMoveToWindow];
    [self cp_installChatGPTScrollRecoveryScriptIfNeeded];
    [self cp_scheduleChatGPTScrollRecovery];
}

- (BOOL)cp_isChatGPTScrollRecoveryURL:(NSURL *)url {
    NSString *host = url.host.lowercaseString;
    if (host.length == 0) return NO;
    return [host isEqualToString:@"chatgpt.com"] || [host hasSuffix:@".chatgpt.com"];
}

- (void)cp_prepareNativeScrollViewForChatGPT {
    UIScrollView *scrollView = self.scrollView;
    scrollView.scrollEnabled = YES;
    scrollView.userInteractionEnabled = YES;
    scrollView.directionalLockEnabled = YES;
    scrollView.panGestureRecognizer.enabled = YES;
    scrollView.delaysContentTouches = NO;

    // ChatGPT scrolls inside its own DOM container. Prevent WKWebView's outer
    // scroll view from rubber banding or drifting horizontally.
    scrollView.bounces = NO;
    scrollView.alwaysBounceVertical = NO;
    scrollView.alwaysBounceHorizontal = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
}

- (void)cp_installChatGPTScrollRecoveryScriptIfNeeded {
    if ([objc_getAssociatedObject(self, CPChatGPTScrollScriptInstalledKey) boolValue]) return;

    WKUserScript *script = [[WKUserScript alloc]
        initWithSource:[self cp_chatGPTScrollRecoveryScript]
        injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
        forMainFrameOnly:YES];
    [self.configuration.userContentController addUserScript:script];
    objc_setAssociatedObject(self, CPChatGPTScrollScriptInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)cp_scheduleChatGPTScrollRecovery {
    [self cp_prepareNativeScrollViewForChatGPT];

    __weak WKWebView *weakWebView = self;
    NSArray<NSNumber *> *delays = @[@0.25, @0.75, @2.0, @5.0, @10.0, @16.0];
    for (NSNumber *delay in delays) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{
                WKWebView *webView = weakWebView;
                if (!webView || ![webView cp_isChatGPTScrollRecoveryURL:webView.URL]) return;
                [webView cp_prepareNativeScrollViewForChatGPT];
                [webView evaluateJavaScript:[webView cp_chatGPTScrollRecoveryScript]
                          completionHandler:nil];
            }
        );
    }
}

- (NSString *)cp_chatGPTScrollRecoveryScript {
    return @"(() => {"
        "try {"
          "if (!/(^|\\.)chatgpt\\.com$/.test(location.hostname)) return false;"
          "const manager = window.__contextPortChatPerformance;"
          "if (manager && manager.providerID === 'chatgpt' && typeof manager.destroy === 'function') manager.destroy();"
          "document.getElementById('contextport-chat-performance-style')?.remove();"
          "document.querySelectorAll('.contextport-performance-hidden').forEach(element => {"
            "element.classList.remove('contextport-performance-hidden');"
            "element.removeAttribute('aria-hidden');"
            "element.removeAttribute('data-contextport-performance-message');"
          "});"

          "const repair = () => {"
            "const candidates = Array.from(document.querySelectorAll('main, [data-scroll-root], [class*=overflow-y-auto], [class*=overflow-y-scroll]'));"
            "let best = null;"
            "let bestRange = 0;"
            "for (const element of candidates) {"
              "if (!(element instanceof HTMLElement)) continue;"
              "const range = element.scrollHeight - element.clientHeight;"
              "if (range > bestRange && element.clientHeight > 200) { best = element; bestRange = range; }"
            "}"
            "if (!best) return false;"
            "best.style.setProperty('overflow-y', 'auto', 'important');"
            "best.style.setProperty('overflow-x', 'hidden', 'important');"
            "best.style.setProperty('-webkit-overflow-scrolling', 'touch', 'important');"
            "best.style.setProperty('touch-action', 'pan-y', 'important');"
            "best.style.setProperty('overscroll-behavior-y', 'contain', 'important');"
            "best.style.setProperty('overscroll-behavior-x', 'none', 'important');"
            "best.scrollLeft = 0;"
            "document.documentElement.style.setProperty('overflow-x', 'hidden', 'important');"
            "document.documentElement.style.setProperty('overscroll-behavior', 'none', 'important');"
            "document.body?.style.setProperty('overflow-x', 'hidden', 'important');"
            "document.body?.style.setProperty('overscroll-behavior', 'none', 'important');"
            "return true;"
          "};"

          "repair();"
          "clearInterval(window.__contextPortChatScrollRepairTimer);"
          "window.__contextPortChatScrollRepairTimer = setInterval(repair, 1500);"
          "setTimeout(() => clearInterval(window.__contextPortChatScrollRepairTimer), 30000);"
          "return true;"
        "} catch (_) { return false; }"
      "})()";
}

@end
