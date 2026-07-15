#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

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
    [self cp_scheduleChatGPTScrollRecovery];
}

- (BOOL)cp_isChatGPTScrollRecoveryURL:(NSURL *)url {
    NSString *host = url.host.lowercaseString;
    if (host.length == 0) return NO;
    return [host isEqualToString:@"chatgpt.com"] || [host hasSuffix:@".chatgpt.com"];
}

- (void)cp_enableNativeScrolling {
    UIScrollView *scrollView = self.scrollView;
    scrollView.scrollEnabled = YES;
    scrollView.userInteractionEnabled = YES;
    scrollView.directionalLockEnabled = NO;
    scrollView.panGestureRecognizer.enabled = YES;
    scrollView.delaysContentTouches = NO;
}

- (void)cp_scheduleChatGPTScrollRecovery {
    [self cp_enableNativeScrolling];

    __weak WKWebView *weakWebView = self;
    NSArray<NSNumber *> *delays = @[@0.5, @2.0, @5.0, @10.0, @16.0];
    for (NSNumber *delay in delays) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{
                WKWebView *webView = weakWebView;
                if (!webView || ![webView cp_isChatGPTScrollRecoveryURL:webView.URL]) return;
                [webView cp_enableNativeScrolling];
                [webView evaluateJavaScript:[webView cp_chatGPTScrollRecoveryScript]
                          completionHandler:nil];
            }
        );
    }
}

- (NSString *)cp_chatGPTScrollRecoveryScript {
    return @"(() => {"
        "try {"
          "const manager = window.__contextPortChatPerformance;"
          "if (manager && manager.providerID === 'chatgpt' && typeof manager.destroy === 'function') manager.destroy();"
          "document.getElementById('contextport-chat-performance-style')?.remove();"
          "document.querySelectorAll('.contextport-performance-hidden').forEach(element => {"
            "element.classList.remove('contextport-performance-hidden');"
            "element.removeAttribute('aria-hidden');"
            "element.removeAttribute('data-contextport-performance-message');"
          "});"
          "return true;"
        "} catch (_) { return false; }"
      "})()";
}

@end
